import Foundation
import OmiSupport

actor AgentRuntimeStartupSingleFlight<Key: Equatable & Sendable, Output: Sendable> {
  private struct Attempt {
    let id: UUID
    let key: Key
    let task: Task<Output, Error>
  }

  private var attempt: Attempt?
  private var participantCount = 0

  func run(
    key: Key,
    operation: @escaping @Sendable () async throws -> Output
  ) async throws -> Output {
    participantCount += 1
    defer { participantCount -= 1 }
    if let attempt {
      guard attempt.key == key else { throw BridgeError.stopped }
      return try await attempt.task.value
    }

    let id = UUID()
    let task = Task { try await operation() }
    attempt = Attempt(id: id, key: key, task: task)
    do {
      let output = try await task.value
      clearAttempt(id: id)
      return output
    } catch {
      clearAttempt(id: id)
      throw error
    }
  }

  func participantCountForTesting() -> Int {
    participantCount
  }

  /// A reducer can enter `.starting` just before the owning task reaches this
  /// actor. Callers must distinguish that short launch-admission window from a
  /// real in-flight launch; treating both as "wait for init" strands the first
  /// launch forever.
  func hasActiveAttempt() -> Bool {
    attempt != nil
  }

  private func clearAttempt(id: UUID) {
    guard attempt?.id == id else { return }
    attempt = nil
  }
}

final class AgentRuntimeStdoutChunkReader: @unchecked Sendable {
  private let lock = NSLock()
  private var nextSequence: UInt64 = 0

  func read(from handle: FileHandle) -> (sequence: UInt64, data: Data) {
    lock.lock()
    defer { lock.unlock() }
    let data = handle.availableData
    let sequence = nextSequence
    if !data.isEmpty {
      nextSequence &+= 1
    }
    return (sequence, data)
  }
}

struct AgentRuntimeOrderedStdoutBuffer {
  private var nextSequence: UInt64 = 0
  private var pendingChunks: [UInt64: Data] = [:]
  private var lineBuffer = Data()

  mutating func ingest(_ data: Data, sequence: UInt64) -> [Data] {
    guard !data.isEmpty, sequence >= nextSequence else { return [] }
    guard pendingChunks[sequence] == nil else { return [] }
    pendingChunks[sequence] = data

    var lines: [Data] = []
    while let chunk = pendingChunks.removeValue(forKey: nextSequence) {
      nextSequence &+= 1
      lineBuffer.append(chunk)
      while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
        lines.append(Data(lineBuffer[lineBuffer.startIndex..<newlineIndex]))
        lineBuffer = Data(lineBuffer[lineBuffer.index(after: newlineIndex)...])
      }
    }
    return lines
  }

  mutating func reset() {
    nextSequence = 0
    pendingChunks.removeAll(keepingCapacity: false)
    lineBuffer.removeAll(keepingCapacity: false)
  }
}

/// Owns one local SQLite journal subprocess. No model or tool execution lives here.
actor AgentRuntimeProcess {
  static let shared = AgentRuntimeProcess()
  static let expectedProtocolVersion = 2
  struct JournalFirstCompletedRealExchange: Sendable, Equatable {
    let continuityKey: String
    let userText: String
    let assistantText: String
  }

  struct JournalOperationResult: Sendable {
    let operation: String
    let conversationId: String
    let turn: KernelJournalTurn?
    let turns: [KernelJournalTurn]
    let clearedCount: Int
    let highWaterTurnSeq: Int
    let conversationGeneration: Int
    let generationBaseTurnSeq: Int
    let firstCompletedRealPair: Bool
    let firstCompletedRealExchange: JournalFirstCompletedRealExchange?

    init(
      operation: String,
      conversationId: String,
      turn: KernelJournalTurn?,
      turns: [KernelJournalTurn],
      clearedCount: Int,
      highWaterTurnSeq: Int,
      conversationGeneration: Int,
      generationBaseTurnSeq: Int,
      firstCompletedRealPair: Bool = false,
      firstCompletedRealExchange: JournalFirstCompletedRealExchange? = nil
    ) {
      self.operation = operation
      self.conversationId = conversationId
      self.turn = turn
      self.turns = turns
      self.clearedCount = clearedCount
      self.highWaterTurnSeq = highWaterTurnSeq
      self.conversationGeneration = conversationGeneration
      self.generationBaseTurnSeq = generationBaseTurnSeq
      self.firstCompletedRealPair = firstCompletedRealPair
      self.firstCompletedRealExchange = firstCompletedRealExchange
    }
  }

  typealias JournalTurnChangedHandler = @Sendable (KernelJournalTurn) -> Void
  private struct Pending {
    let authorization: RuntimeOwnerAuthorizationSnapshot
    let continuation: CheckedContinuation<RuntimeJSONPayloadBox, Error>
  }
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var errors: FileHandle?
  private var buffer = AgentRuntimeOrderedStdoutBuffer()
  private var generation: UInt64 = 0
  private var ownerID: String?
  private var ready = false
  private var startWaiters: [CheckedContinuation<Void, Error>] = []
  private var pending: [String: Pending] = [:]
  private var journalHandler: JournalTurnChangedHandler?

  var isAlive: Bool { ready && process?.isRunning == true }

  func start(authorization: RuntimeOwnerAuthorizationSnapshot) async throws {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorization) else { throw BridgeError.authMissing }
    if process != nil, ownerID != authorization.ownerID { stop() }
    if isAlive { return }
    if process == nil { try launch(owner: authorization.ownerID) }
    try await withCheckedThrowingContinuation { startWaiters.append($0) }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorization), ownerID == authorization.ownerID else {
      throw BridgeError.authMissing
    }
  }

  private func launch(owner: String) throws {
    guard let node = findNodeBinary() else { throw BridgeError.nodeNotFound }
    guard let script = findBridgeScript() else { throw BridgeError.bridgeScriptNotFound }
    generation &+= 1
    let epoch = generation
    let task = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    task.executableURL = URL(fileURLWithPath: node)
    task.arguments = [script]
    // Local storage receives no provider credentials or inherited cloud secrets.
    task.environment = [
      "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
      "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
      "INTENTIVE_STORAGE_OWNER_ID": owner,
      "HEYINTENTIVE_AGENT_STATE_DIR": try Self.defaultStateDirectory(),
    ]
    task.standardInput = stdin
    task.standardOutput = stdout
    task.standardError = stderr
    task.terminationHandler = { [weak self] _ in Task { await self?.exited(epoch: epoch) } }
    let reader = AgentRuntimeStdoutChunkReader()
    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let chunk = reader.read(from: handle)
      Task { await self?.receive(chunk.data, sequence: chunk.sequence, epoch: epoch) }
    }
    stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
    process = task
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    errors = stderr.fileHandleForReading
    ownerID = owner
    ready = false
    do { try task.run() } catch {
      stop()
      throw error
    }
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(10))
      await self?.startupTimeout(epoch: epoch)
    }
  }

  func request(_ payload: RuntimeJSONPayloadBox, authorization: RuntimeOwnerAuthorizationSnapshot) async throws
    -> RuntimeJSONPayloadBox
  {
    try await start(authorization: authorization)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorization) else { throw BridgeError.authMissing }
    var value = payload.value
    let id = UUID().uuidString
    value["requestId"] = id
    value["clientId"] = "desktop-conversation"
    value["ownerId"] = authorization.ownerID
    value["protocolVersion"] = Self.expectedProtocolVersion
    guard JSONSerialization.isValidJSONObject(value) else { throw BridgeError.encodingError }
    var bytes = try JSONSerialization.data(withJSONObject: value)
    guard bytes.count <= 4_000_000 else { throw BridgeError.encodingError }
    bytes.append(10)
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        pending[id] = Pending(authorization: authorization, continuation: continuation)
        do { try input?.write(contentsOf: bytes) } catch { complete(id, error: BridgeError.processExited) }
        Task { [weak self] in
          try? await Task.sleep(for: .seconds(15))
          await self?.complete(id, error: BridgeError.timeout)
        }
      }
    } onCancel: {
      Task { await self.complete(id, error: CancellationError()) }
    }
  }

  private func receive(_ data: Data, sequence: UInt64, epoch: UInt64) {
    guard epoch == generation, !data.isEmpty else { return }
    for line in buffer.ingest(data, sequence: sequence) {
      guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
      if message["type"] as? String == "init" {
        guard message["protocolVersion"] as? Int == Self.expectedProtocolVersion,
          message["ownerId"] as? String == ownerID
        else {
          stop()
          return
        }
        ready = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        continue
      }
      if message["type"] as? String == "journal_turn_changed" {
        guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID),
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorization),
          let row = message["turn"] as? [String: Any],
          let turn = KernelJournalTurn(
            dictionary: row,
            surfaceFallback: AgentSurfaceReference(
              surfaceKind: message["surfaceKind"] as? String ?? "",
              externalRefKind: message["externalRefKind"] as? String ?? "chat",
              externalRefId: message["externalRefId"] as? String ?? "default"),
            conversationGenerationFallback: message["conversationGeneration"] as? Int ?? 1,
            generationBaseTurnSeqFallback: message["generationBaseTurnSeq"] as? Int ?? 0)
        else { continue }
        journalHandler?(turn)
        continue
      }
      guard let id = message["requestId"] as? String, let request = pending.removeValue(forKey: id) else { continue }
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(request.authorization),
        message["ownerId"] as? String == request.authorization.ownerID
      else {
        request.continuation.resume(throwing: BridgeError.authMissing)
        continue
      }
      if message["type"] as? String == "error" || message["ok"] as? Bool == false {
        request.continuation.resume(
          throwing: BridgeError.agentError(message["errorCode"] as? String ?? "conversation_storage_failed"))
      } else {
        request.continuation.resume(returning: RuntimeJSONPayloadBox(message))
      }
    }
  }

  private func startupTimeout(epoch: UInt64) { if generation == epoch, !ready { stop(error: .timeout) } }
  private func exited(epoch: UInt64) { if generation == epoch { stop(error: .processExited) } }
  private func complete(_ id: String, error: Error) {
    pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
  }
  func setJournalTurnChangedHandler(_ handler: JournalTurnChangedHandler?) { journalHandler = handler }
  #if !DISTRIBUTION
    func journalTurnChangedHandlerCount() -> Int { journalHandler == nil ? 0 : 1 }
    func dispatchJournalTurnChangedForTesting(_ turn: KernelJournalTurn) { journalHandler?(turn) }
  #endif
  func revokeOwnerRuntime(previousOwnerID: String?, cleanupCapability: RuntimeOwnerTransitionCleanupCapability) {
    guard RuntimeOwnerIdentity.authorizesTransitionCleanup(cleanupCapability, previousOwnerID: previousOwnerID),
      ownerID == previousOwnerID
    else { return }
    stop(error: .authMissing)
  }
  func stop(error: BridgeError = .stopped) {
    generation &+= 1
    let oldProcess = process
    process = nil
    ready = false
    ownerID = nil
    output?.readabilityHandler = nil
    errors?.readabilityHandler = nil
    try? input?.close()
    try? output?.close()
    try? errors?.close()
    input = nil
    output = nil
    errors = nil
    buffer.reset()
    if oldProcess?.isRunning == true {
      oldProcess?.terminate()
      oldProcess?.waitUntilExit()
    }
    let waiters = startWaiters
    startWaiters.removeAll()
    for waiter in waiters { waiter.resume(throwing: error) }
    let requests = pending.values
    pending.removeAll()
    for request in requests { request.continuation.resume(throwing: error) }
  }
  static func defaultStateDirectory(
    bundleIdentifier: String? = Bundle.main.bundleIdentifier,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> String {
    guard let identity = DesktopProductIdentity(bundleIdentifier: bundleIdentifier) else {
      throw BridgeError.agentError("invalid_desktop_product_identity")
    }
    return identity.applicationSupportURL(homeDirectory: homeDirectory)
      .appendingPathComponent("AgentRuntime")
      .path
  }

  static func defaultArtifactsDirectory(
    bundleIdentifier: String? = Bundle.main.bundleIdentifier,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> String {
    guard let identity = DesktopProductIdentity(bundleIdentifier: bundleIdentifier) else {
      throw BridgeError.agentError("invalid_desktop_product_identity")
    }
    return identity.applicationSupportURL(homeDirectory: homeDirectory)
      .appendingPathComponent("Artifacts")
      .path
  }

  /// Resource lookup must be optional at this boundary. `Bundle.resourceBundle`
  /// intentionally traps when an app bundle is malformed, but SwiftPM test
  /// executables have no app-style `Contents/Resources` root and must be able to
  /// fall through to the system Node candidates without crashing the process.
  nonisolated static func runtimeResourceExecutableCandidates(
    named resourceName: String,
    bundleURLs: [URL],
    executableURL: URL?
  ) -> [String] {
    let bundleName = "Omi Computer_Omi Computer.bundle"
    var candidates: [String] = []
    var seen = Set<String>()
    func append(_ url: URL) {
      let path = url.standardizedFileURL.path
      if seen.insert(path).inserted { candidates.append(path) }
    }
    for bundleURL in bundleURLs {
      append(
        bundleURL
          .appendingPathComponent("Contents/Resources")
          .appendingPathComponent(bundleName)
          .appendingPathComponent(resourceName))
      append(
        bundleURL
          .appendingPathComponent(bundleName)
          .appendingPathComponent(resourceName))
      append(
        bundleURL.deletingLastPathComponent()
          .appendingPathComponent(bundleName)
          .appendingPathComponent(resourceName))
    }
    if let executableDirectory = executableURL?.deletingLastPathComponent() {
      append(
        executableDirectory
          .appendingPathComponent(bundleName)
          .appendingPathComponent(resourceName))
      append(
        executableDirectory.deletingLastPathComponent()
          .appendingPathComponent(bundleName)
          .appendingPathComponent(resourceName))
    }
    return candidates
  }

  private func findNodeBinary() -> String? {
    let bundleURLs =
      [Bundle.main.bundleURL]
      + Bundle.allBundles.map(\.bundleURL)
      + Bundle.allFrameworks.map(\.bundleURL)
    for bundledNode in Self.runtimeResourceExecutableCandidates(
      named: "node",
      bundleURLs: bundleURLs,
      executableURL: Bundle.main.executableURL
    ) where FileManager.default.isExecutableFile(atPath: bundledNode) {
      return bundledNode
    }

    let candidates = [
      "/opt/homebrew/bin/node",
      "/usr/local/bin/node",
      "/usr/bin/node",
    ]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
      return path
    }

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let nvmDir = (home as NSString).appendingPathComponent(".nvm/versions/node")
    if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
      let sorted = versions.sorted { lhs, rhs in
        lhs.compare(rhs, options: .numeric) == .orderedDescending
      }
      for version in sorted {
        let nodePath = (nvmDir as NSString).appendingPathComponent("\(version)/bin/node")
        if FileManager.default.isExecutableFile(atPath: nodePath) {
          return nodePath
        }
      }
    }

    let whichProcess = Process()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProcess.arguments = ["node"]
    let pipe = Pipe()
    whichProcess.standardOutput = pipe
    try? whichProcess.run()
    whichProcess.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !path.isEmpty,
      FileManager.default.isExecutableFile(atPath: path)
    {
      return path
    }

    return nil
  }

  private func findBridgeScript() -> String? {
    if let bundlePath = Bundle.main.resourcePath {
      let bundledScript = (bundlePath as NSString).appendingPathComponent("agent/dist/index.js")
      if FileManager.default.fileExists(atPath: bundledScript) {
        return bundledScript
      }
    }

    if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
      let devPaths = [
        execDir.appendingPathComponent("../../../agent/dist/index.js").path,
        execDir.appendingPathComponent("../../../../agent/dist/index.js").path,
      ]
      for path in devPaths {
        let resolved = (path as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: resolved) {
          return resolved
        }
      }
    }

    let cwdPath = FileManager.default.currentDirectoryPath
    let cwdCandidates = [
      "agent/dist/index.js",
      "desktop/macos/agent/dist/index.js",
      "../agent/dist/index.js",
    ]
    for relativePath in cwdCandidates {
      let candidate = (cwdPath as NSString).appendingPathComponent(relativePath)
      let resolved = (candidate as NSString).standardizingPath
      if FileManager.default.fileExists(atPath: resolved) {
        return resolved
      }
    }

    return nil
  }
}
