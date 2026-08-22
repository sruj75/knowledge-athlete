import Foundation
import XCTest

@testable import Omi_Computer

@MainActor
final class LocalUserDataExportTests: XCTestCase {
  func testExportPaginatesEveryCollectionAndWritesDeterministicCompleteJSON() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "export-owner")
    defer { Task { @MainActor in await fixture.restore() } }
    let reader = ExportReaderFake(
      conversations: (0..<101).map(Self.conversation),
      memories: (0..<101).map(Self.memory),
      tasks: (0..<101).map(Self.task),
      goals: (0..<101).map(Self.goal),
      chats: [try Self.chat("chat-b"), try Self.chat("chat-a")],
      turnsByChat: [
        "chat-a": try (0..<101).map { try Self.turn($0 + 1, chatID: "chat-a") },
        "chat-b": [],
      ],
      focus: [Self.focus(2), Self.focus(1)],
      exportedSettings: ["askModeEnabled": .bool(true)])
    let exporter = LocalUserDataExport(
      reader: reader,
      now: { Date(timeIntervalSince1970: 1_700_000_000) })
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LocalUserDataExportTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstURL = directory.appendingPathComponent("first.json")
    let secondURL = directory.appendingPathComponent("second.json")

    try await exporter.export(ownerID: "export-owner", to: firstURL)
    try await exporter.export(ownerID: "export-owner", to: secondURL)

    let firstData = try Data(contentsOf: firstURL)
    XCTAssertEqual(firstData, try Data(contentsOf: secondURL))
    let document = try JSONDecoder.exportDecoder.decode(
      LocalUserDataExportDocument.self, from: firstData)
    XCTAssertEqual(document.schemaVersion, 1)
    XCTAssertEqual(document.conversations.count, 101)
    XCTAssertEqual(document.memories.count, 101)
    XCTAssertEqual(document.tasks.count, 101)
    XCTAssertEqual(document.goals.count, 101)
    XCTAssertEqual(document.chatHistory.map(\.summary.chatId), ["chat-a", "chat-b"])
    XCTAssertEqual(document.chatHistory[0].turns.count, 101)
    XCTAssertEqual(document.focusData.compactMap(\.id), [1, 2])
    XCTAssertEqual(document.settings, ["askModeEnabled": .bool(true)])
    let memoryOffsets = await reader.offsets(for: "memory")
    let taskOffsets = await reader.offsets(for: "task")
    let goalOffsets = await reader.offsets(for: "goal")
    let chatOffsets = await reader.chatOffsets(chatID: "chat-a")
    XCTAssertEqual(memoryOffsets, [0, 100, 0, 100])
    XCTAssertEqual(taskOffsets, [0, 100, 0, 100])
    XCTAssertEqual(goalOffsets, [0, 100, 0, 100])
    XCTAssertEqual(chatOffsets, [0, 100, 0, 100])
  }

  func testOwnerRevocationStopsBeforeWritingAnyFile() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "export-owner")
    defer { Task { @MainActor in await fixture.restore() } }
    let current = LockedBool(true)
    let reader = ExportReaderFake(onFirstTaskPage: { current.set(false) })
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("revoked-export-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: destination) }
    let exporter = LocalUserDataExport(
      reader: reader,
      isAuthorizationCurrent: { _ in current.value })

    do {
      try await exporter.export(ownerID: "export-owner", to: destination)
      XCTFail("Expected owner revocation")
    } catch {
      XCTAssertEqual(error as? LocalUserDataExportError, .ownerChanged)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  func testOwnerTransitionWaitsForPhysicalExportCommit() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "export-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let writer = BlockingExportWriter()
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("leased-export-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: destination) }
    let exporter = LocalUserDataExport(reader: ExportReaderFake(), writer: writer)

    let export = Task {
      try await exporter.export(ownerID: "export-owner-a", to: destination)
    }
    await writer.waitUntilWriteStarts()
    let transition = Task { @MainActor in
      await fixture.establish(authOwnerID: "export-owner-b")
    }
    await EffectiveOwnerTransitionFence.shared.waitUntilTransitionIsPending()

    XCTAssertEqual(RuntimeOwnerIdentity.currentOwnerId(), "export-owner-a")
    writer.allowWriteToFinish()
    try await export.value
    await transition.value

    XCTAssertEqual(RuntimeOwnerIdentity.currentOwnerId(), "export-owner-b")
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
  }

  func testReadAndWriteFailuresLeaveNoPartialFile() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "export-owner")
    defer { Task { @MainActor in await fixture.restore() } }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("failed-export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let readURL = directory.appendingPathComponent("read.json")
    let failingReader = ExportReaderFake(readError: ExportTestError.failed)
    do {
      try await LocalUserDataExport(reader: failingReader)
        .export(ownerID: "export-owner", to: readURL)
      XCTFail("Expected read failure")
    } catch {
      guard case .readFailed = error as? LocalUserDataExportError else {
        return XCTFail("Expected read failure, got \(error)")
      }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: readURL.path))

    let writeURL = directory.appendingPathComponent("write.json")
    do {
      try await LocalUserDataExport(reader: ExportReaderFake(), writer: FailingExportWriter())
        .export(ownerID: "export-owner", to: writeURL)
      XCTFail("Expected write failure")
    } catch {
      guard case .writeFailed = error as? LocalUserDataExportError else {
        return XCTFail("Expected write failure, got \(error)")
      }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: writeURL.path))
  }

  func testSettingsAllowlistExcludesCredentialsDiagnosticsAndPrompts() throws {
    let suite = "LocalUserDataExportSettingsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let promptKey = "assistant" + "Prompt"
    let diagnosticKey = "diagnostic" + "BundlePath"
    defaults.set(true, forKey: .askModeEnabled)
    defaults.set("secret", forKey: .authIdToken)
    defaults.set("private prompt", forKey: promptKey)
    defaults.set("diagnostic", forKey: diagnosticKey)

    let settings = LocalUserDataExportSettings.snapshot(defaults: defaults)

    XCTAssertEqual(settings["askModeEnabled"], .bool(true))
    XCTAssertNil(settings["auth_idToken"])
    XCTAssertNil(settings["assistantPrompt"])
    XCTAssertNil(settings["diagnosticBundlePath"])
  }

  private static func conversation(_ index: Int) -> ConversationArchiveRecord {
    ConversationArchiveRecord(
      conversationId: String(format: "conversation-%03d", index),
      startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
      finishedAt: nil,
      language: "en",
      timezone: "UTC",
      inputDeviceName: nil,
      status: "completed",
      title: "Conversation \(index)",
      overview: nil,
      emoji: nil,
      commitmentsJson: nil,
      geolocationJson: nil,
      starred: false,
      folderId: nil,
      createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
      updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
      contentGeneration: 1,
      segments: [])
  }

  private static func memory(_ index: Int) -> LocalUserDataMemory {
    LocalUserDataMemory(
      MemoryItem(
        id: "memory-\(index)",
        content: "Memory \(index)",
        category: .system,
        layer: .longTerm,
        expiresAt: nil,
        revision: 1,
        createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
        updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
        correctedAt: nil,
        conversationId: nil,
        sourceSegmentId: nil,
        manuallyAdded: false,
        source: .desktop,
        confidence: nil,
        sourceApp: nil,
        contextSummary: nil,
        isRead: true,
        isDismissed: false,
        tags: [],
        reasoning: nil,
        currentActivity: nil,
        inputDeviceName: nil,
        windowTitle: nil,
        screenshotId: nil))
  }

  private static func task(_ index: Int) -> TaskActionItem {
    TaskActionItem(
      id: "local_\(index)",
      description: "Task \(index)",
      completed: false,
      createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
  }

  private static func goal(_ index: Int) -> LocalUserDataGoal {
    LocalUserDataGoal(
      LocalGoal(
        id: "local_\(index)",
        rowID: Int64(index),
        title: "Goal \(index)",
        description: nil,
        isActive: true,
        completedAt: nil,
        createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
        updatedAt: Date(timeIntervalSince1970: TimeInterval(index))))
  }

  private static func chat(_ id: String) throws -> LocalUserDataChatSummary {
    LocalUserDataChatSummary(
      try XCTUnwrap(
        LocalChatSummary(dictionary: [
          "chatId": id,
          "title": id,
          "titleOrigin": "manual",
          "messageCount": 0,
          "createdAtMs": 1,
          "lastActivityAtMs": 1,
          "starred": false,
        ])))
  }

  private static func turn(_ sequence: Int, chatID: String) throws -> LocalUserDataChatTurn {
    LocalUserDataChatTurn(
      try XCTUnwrap(
        KernelJournalTurn(dictionary: [
          "conversationId": chatID,
          "turnId": "turn-\(sequence)",
          "turnSeq": sequence,
          "role": "user",
          "content": "Message \(sequence)",
          "status": "completed",
          "createdAtMs": sequence,
        ])))
  }

  private static func focus(_ id: Int64) -> LocalUserDataFocusSession {
    LocalUserDataFocusSession(
      FocusSessionRecord(
        id: id,
        status: "focused",
        appOrSite: "Editor",
        description: "Focus",
        createdAt: Date(timeIntervalSince1970: TimeInterval(id))))
  }
}

private actor ExportReaderFake: LocalUserDataExportReading {
  private let conversations: [ConversationArchiveRecord]
  private let memories: [LocalUserDataMemory]
  private let tasks: [TaskActionItem]
  private let goals: [LocalUserDataGoal]
  private let chats: [LocalUserDataChatSummary]
  private let turnsByChat: [String: [LocalUserDataChatTurn]]
  private let focus: [LocalUserDataFocusSession]
  nonisolated let exportedSettings: [String: LocalUserDataSettingValue]
  private let readError: Error?
  private let onFirstTaskPage: (@Sendable () -> Void)?
  private var pageOffsets: [String: [Int]] = [:]
  private var turnOffsets: [String: [Int]] = [:]

  init(
    conversations: [ConversationArchiveRecord] = [],
    memories: [LocalUserDataMemory] = [],
    tasks: [TaskActionItem] = [],
    goals: [LocalUserDataGoal] = [],
    chats: [LocalUserDataChatSummary] = [],
    turnsByChat: [String: [LocalUserDataChatTurn]] = [:],
    focus: [LocalUserDataFocusSession] = [],
    exportedSettings: [String: LocalUserDataSettingValue] = [:],
    readError: Error? = nil,
    onFirstTaskPage: (@Sendable () -> Void)? = nil
  ) {
    self.conversations = conversations
    self.memories = memories
    self.tasks = tasks
    self.goals = goals
    self.chats = chats
    self.turnsByChat = turnsByChat
    self.focus = focus
    self.exportedSettings = exportedSettings
    self.readError = readError
    self.onFirstTaskPage = onFirstTaskPage
  }

  func conversationPage(
    after conversationID: String?, limit: Int,
    authorization _: RuntimeOwnerAuthorizationSnapshot
  ) throws -> [ConversationArchiveRecord] {
    try failIfRequested()
    let start =
      conversationID.flatMap { id in
        conversations.firstIndex(where: { $0.conversationId == id }).map { $0 + 1 }
      } ?? 0
    return Array(conversations.dropFirst(start).prefix(limit))
  }

  func memoryPage(
    offset: Int, limit: Int, authorization _: RuntimeOwnerAuthorizationSnapshot
  ) throws -> [LocalUserDataMemory] {
    pageOffsets["memory", default: []].append(offset)
    return Array(memories.dropFirst(offset).prefix(limit))
  }

  func taskPage(
    offset: Int, limit: Int, authorization _: RuntimeOwnerAuthorizationSnapshot
  ) throws -> [TaskActionItem] {
    pageOffsets["task", default: []].append(offset)
    if offset == 0 { onFirstTaskPage?() }
    return Array(tasks.dropFirst(offset).prefix(limit))
  }

  func goalPage(
    offset: Int, limit: Int, authorization _: RuntimeOwnerAuthorizationSnapshot
  ) throws -> [LocalUserDataGoal] {
    pageOffsets["goal", default: []].append(offset)
    return Array(goals.dropFirst(offset).prefix(limit))
  }

  func focusData(
    authorization _: RuntimeOwnerAuthorizationSnapshot
  ) -> [LocalUserDataFocusSession] { focus }

  func chatCatalog(
    authorization _: RuntimeOwnerAuthorizationSnapshot
  ) -> [LocalUserDataChatSummary] { chats }

  func chatTurnPage(
    chatID: String, after sequence: Int, limit: Int,
    authorization _: RuntimeOwnerAuthorizationSnapshot
  ) -> [LocalUserDataChatTurn] {
    turnOffsets[chatID, default: []].append(sequence)
    return Array((turnsByChat[chatID] ?? []).filter { $0.turnSequence > sequence }.prefix(limit))
  }

  nonisolated func settings() -> [String: LocalUserDataSettingValue] { exportedSettings }

  func offsets(for name: String) -> [Int] { pageOffsets[name] ?? [] }
  func chatOffsets(chatID: String) -> [Int] { turnOffsets[chatID] ?? [] }

  private func failIfRequested() throws {
    if let readError { throw readError }
  }
}

private struct FailingExportWriter: LocalUserDataExportFileWriting {
  func writeAtomically(_: Data, to _: URL) throws { throw ExportTestError.failed }
}

private final class BlockingExportWriter: LocalUserDataExportFileWriting, @unchecked Sendable {
  private let lock = NSLock()
  private var writeStarted = false
  private var writeStartedContinuation: CheckedContinuation<Void, Never>?
  private let finishWrite = DispatchSemaphore(value: 0)

  func writeAtomically(_ data: Data, to destination: URL) throws {
    let continuation = lock.withLock {
      writeStarted = true
      defer { writeStartedContinuation = nil }
      return writeStartedContinuation
    }
    continuation?.resume()
    finishWrite.wait()
    try LocalUserDataAtomicFileWriter().writeAtomically(data, to: destination)
  }

  func waitUntilWriteStarts() async {
    await withCheckedContinuation { continuation in
      let shouldResume = lock.withLock {
        if writeStarted { return true }
        writeStartedContinuation = continuation
        return false
      }
      if shouldResume { continuation.resume() }
    }
  }

  func allowWriteToFinish() {
    finishWrite.signal()
  }
}

private enum ExportTestError: Error { case failed }

private final class LockedBool: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Bool

  init(_ value: Bool) { storedValue = value }

  var value: Bool { lock.withLock { storedValue } }
  func set(_ value: Bool) { lock.withLock { storedValue = value } }
}

extension JSONDecoder {
  fileprivate static var exportDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}
