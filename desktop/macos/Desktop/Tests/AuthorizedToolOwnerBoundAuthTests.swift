import Foundation
import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

extension APIClient {
  fileprivate func setOwnerBoundTestAuthHeader(_ header: String) {
    testAuthHeader = header
  }
}

private final class AuthorizedToolRequestGate: @unchecked Sendable {
  private struct RequestWaiter {
    let path: String
    let continuation: CheckedContinuation<URLRequest, Never>
  }

  private let lock = NSLock()
  private var pendingProtocols: [AuthorizedToolOwnerURLProtocol] = []
  private var selectedProtocols: [String: AuthorizedToolOwnerURLProtocol] = [:]
  private var requestWaiters: [RequestWaiter] = []

  func reset() async {
    lock.withLock {
      pendingProtocols.removeAll()
      selectedProtocols.removeAll()
      requestWaiters.removeAll()
    }
  }

  /// Synchronous so `URLProtocol.startLoading()` (nonisolated) can register itself without
  /// spawning a `Task`/crossing an actor boundary, which trips Swift 6 region-based sendability
  /// for the URLProtocol instance (shared with the URL-loading infrastructure). State is
  /// serialized by `lock`; continuations are resumed outside the lock to avoid re-entrancy.
  func receive(_ urlProtocol: AuthorizedToolOwnerURLProtocol) {
    var toResume: RequestWaiter?
    lock.withLock {
      pendingProtocols.append(urlProtocol)
      let path = urlProtocol.request.url?.path ?? ""
      if let index = requestWaiters.firstIndex(where: { $0.path == path }) {
        toResume = requestWaiters.remove(at: index)
        selectedProtocols[path] = urlProtocol
      }
    }
    if let waiter = toResume {
      waiter.continuation.resume(returning: urlProtocol.request)
    }
  }

  func waitForRequest(path: String) async -> URLRequest {
    await withCheckedContinuation { continuation in
      var immediate: URLRequest?
      lock.withLock {
        if let pendingProtocol = pendingProtocols.last(where: { $0.request.url?.path == path }) {
          selectedProtocols[path] = pendingProtocol
          immediate = pendingProtocol.request
        } else {
          requestWaiters.append(RequestWaiter(path: path, continuation: continuation))
        }
      }
      if let request = immediate {
        continuation.resume(returning: request)
      }
    }
  }

  func succeed(path: String, with body: String) async {
    let pendingProtocol: AuthorizedToolOwnerURLProtocol? = lock.withLock {
      let proto = selectedProtocols.removeValue(forKey: path)
      if let proto {
        pendingProtocols.removeAll { $0 === proto }
      }
      return proto
    }
    guard let pendingProtocol else { return }
    let response = HTTPURLResponse(
      url: pendingProtocol.request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    pendingProtocol.client?.urlProtocol(
      pendingProtocol,
      didReceive: response,
      cacheStoragePolicy: .notAllowed)
    pendingProtocol.client?.urlProtocol(pendingProtocol, didLoad: Data(body.utf8))
    pendingProtocol.client?.urlProtocolDidFinishLoading(pendingProtocol)
  }
}

private final class AuthorizedToolOwnerURLProtocol: URLProtocol, @unchecked Sendable {
  static let gate = AuthorizedToolRequestGate()

  static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let readCount = stream.read(buffer, maxLength: 4_096)
      if readCount > 0 {
        data.append(buffer, count: readCount)
      } else {
        break
      }
    }
    return data.isEmpty ? nil : data
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.gate.receive(self)
  }

  override func stopLoading() {}
}

private actor AuthorizedToolPhysicalEffectGate {
  private var entered = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func suspendEffectPreparation() async {
    entered = true
    enteredWaiters.forEach { $0.resume() }
    enteredWaiters.removeAll()
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor PermissionCallbackBox<Value: Sendable> {
  private var callback: (@Sendable (Value) -> Void)?
  private var installWaiters: [CheckedContinuation<Void, Never>] = []

  func install(_ callback: @escaping @Sendable (Value) -> Void) {
    self.callback = callback
    installWaiters.forEach { $0.resume() }
    installWaiters.removeAll()
  }

  func waitUntilInstalled() async {
    if callback != nil { return }
    await withCheckedContinuation { installWaiters.append($0) }
  }

  func resolve(_ value: Value) {
    callback?(value)
  }
}

@MainActor final class AuthorizedToolOwnerBoundAuthTests: XCTestCase {
  private var originalAuthOwner: String?
  private var originalOwnerOverride: String?
  private var originalOwnerBackup: String?

  override func setUp() async throws {
    originalAuthOwner = UserDefaults.standard.string(forKey: .authUserId)
    originalOwnerOverride = UserDefaults.standard.string(forKey: .automationOwnerOverride)
    originalOwnerBackup = UserDefaults.standard.string(forKey: .automationOwnerABackup)
  }

  override func tearDown() async throws {
    await restoreOriginalOwnerDefaults()
    await AuthorizedToolOwnerURLProtocol.gate.reset()
  }

  func testRealtimeMintNeverReleasesOwnerATokenAfterMidFlightAccountSwitch() async {
    let client = await makeClient()
    let operation = Task { @MainActor in
      do {
        _ = try await client.mintRealtimeToken(
          expectedOwnerID: "owner-a",
          customBaseURL: "https://owner-bound.invalid/")
        return false
      } catch AuthError.userChangedDuringRequest {
        return true
      } catch {
        return false
      }
    }

    let request = await AuthorizedToolOwnerURLProtocol.gate.waitForRequest(path: "/v2/realtime/session")
    XCTAssertEqual(request.url?.path, "/v2/realtime/session")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-a-token")

    UserDefaults.standard.set("owner-b", forKey: .authUserId)
    await AuthorizedToolOwnerURLProtocol.gate.succeed(
      path: "/v2/realtime/session",
      with: #"{"token":"owner-a-private-ephemeral-token"}"#)

    let rejectedLateToken = await operation.value
    XCTAssertTrue(rejectedLateToken)
  }

  func testPermissionCallbackCancellationReturnsWithoutWaitingAndIgnoresLateCompletion() async {
    let callbackBox = PermissionCallbackBox<Bool>()
    let operation = Task {
      await ChatToolExecutor.awaitCancellablePermissionRequest { completion in
        Task { await callbackBox.install(completion) }
      }
    }

    await callbackBox.waitUntilInstalled()
    operation.cancel()
    let result = await operation.value

    XCTAssertNil(result, "cancellation must release the tracked owner-bound permission task")
    await callbackBox.resolve(true)
    await callbackBox.resolve(false)
    XCTAssertNil(
      result,
      "late or duplicate OS callbacks must not resume the revoked continuation again")
  }

  func testRetainedPhysicalEffectsAreNotInvokedAfterOwnerSwap() async {
    for effectName in ["permission", "task_update"] {
      var currentOwner = "owner-a"
      var invoked = false
      let result = await ChatToolExecutor.performOwnerBoundAsyncPhysicalEffect(
        expectedOwnerID: "owner-a",
        ownerIsCurrent: { $0 == currentOwner },
        prepare: {
          currentOwner = "owner-b"
        },
        effect: {
          invoked = true
          return effectName
        })

      XCTAssertNil(result)
      XCTAssertFalse(invoked, "\(effectName) physical effect must fail closed")
    }
  }

  func testSuspendedPhysicalEffectStaysRevokedAcrossSameOwnerSessionReplacement() async {
    await establishStandardOwner("owner-a")
    guard
      let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot(
        expectedOwnerID: "owner-a")
    else {
      XCTFail("owner-a authorization snapshot was not available")
      return
    }
    let gate = AuthorizedToolPhysicalEffectGate()
    var effectCount = 0
    let operation = Task { @MainActor in
      await ChatToolExecutor.performOwnerBoundAsyncPhysicalEffect(
        expectedOwnerID: "owner-a",
        authorizationSnapshot: authorization,
        prepare: { await gate.suspendEffectPreparation() },
        effect: {
          effectCount += 1
          return "owner-a-private-result"
        })
    }

    await gate.waitUntilEntered()
    await replaceStandardOwner(with: nil)
    await replaceStandardOwner(with: "owner-a")
    await gate.release()

    let result = await operation.value
    XCTAssertNil(result)
    XCTAssertEqual(effectCount, 0)
    XCTAssertFalse(RuntimeOwnerIdentity.isAuthorizationCurrent(authorization))
  }

  func testSQLTaskAndGoalWritesRequireTypedLocalTools() {
    XCTAssertTrue(
      ChatToolExecutor.requiresTypedLocalMutation(
        "INSERT INTO action_items (description) VALUES ('owner-a-private-task')"))
    XCTAssertTrue(
      ChatToolExecutor.requiresTypedLocalMutation(
        "UPDATE goals SET title = 'unsafe' WHERE id = 1"))
    XCTAssertFalse(
      ChatToolExecutor.requiresTypedLocalMutation(
        "INSERT INTO owner_probe(value) VALUES ('ordinary-local-write')"))
  }

  func testNonHubProviderDispatchIsNotCalledAfterOwnerChangesDuringPreparation() async {
    var currentOwner = "owner-a"
    let coordinator = VoiceTurnCoordinator(
      ownerIDProvider: { "owner-a" },
      ownerIsCurrent: { $0 == currentOwner })
    let turnID = coordinator.begin(intent: .hold)
    var providerDispatchCount = 0

    let outcome = await FloatingControlBarManager.performOwnerBoundVoiceDispatch(
      turnID: turnID,
      coordinator: coordinator,
      prepare: {
        currentOwner = "owner-b"
      },
      dispatch: {
        providerDispatchCount += 1
        return "sent"
      })

    if case .rejectedOwnerChange = outcome {
      // Expected.
    } else {
      XCTFail("stale non-hub voice owner must reject provider dispatch")
    }
    XCTAssertEqual(providerDispatchCount, 0)
    XCTAssertEqual(coordinator.model.lastTerminal?.turnID, turnID)
    XCTAssertEqual(coordinator.model.lastTerminal?.reason, .cancelled)
  }

  func testSignedOutOnboardingPermissionStatusIsTheOnlyNarrowNilOwnerPath() async {
    await establishStandardOwner(nil)

    let permissionResult = await ChatToolExecutor.execute(
      ToolCall(
        name: "request_permission",
        arguments: [:],
        thoughtSignature: nil),
      isOnboardingSurface: true)
    XCTAssertFalse(permissionResult.contains("authorized_execution_owner_changed"))

    let authenticatedDataResult = await ChatToolExecutor.execute(
      ToolCall(
        name: "execute_sql",
        arguments: ["query": "SELECT 1", "read_only": true],
        thoughtSignature: nil))
    XCTAssertEqual(authenticatedDataResult, ChatToolExecutor.authorizedOwnerChangedResult())
  }

  private func makeClient() async -> APIClient {
    await AuthorizedToolOwnerURLProtocol.gate.reset()
    await establishStandardOwner("owner-a")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthorizedToolOwnerURLProtocol.self]
    let client = APIClient(session: URLSession(configuration: configuration))
    await client.setOwnerBoundTestAuthHeader("Bearer owner-a-token")
    return client
  }

  private func replaceStandardOwner(with ownerID: String?) async {
    do {
      try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
        defaults: .standard,
        allowAutomationOverride: false,
        plannedNextOwner: { _, _ in ownerID },
        quiesceVoice: { _, _ in },
        revokeKernelOwner: { _, _ in },
        retargetLocalStorage: { _, _ in },
        ownerDidChange: {}
      ) { defaults in
        defaults.removeObject(forKey: .automationOwnerOverride)
        defaults.removeObject(forKey: .automationOwnerABackup)
        if let ownerID {
          defaults.set(ownerID, forKey: .authUserId)
        } else {
          defaults.removeObject(forKey: .authUserId)
        }
      }
    } catch {
      XCTFail("owner transition failed: \(error)")
    }
  }

  private func establishStandardOwner(_ ownerID: String?) async {
    let bootstrapOwner = "authorized-tool-owner-bootstrap"
    if ownerID == bootstrapOwner {
      await replaceStandardOwner(with: nil)
    } else {
      await replaceStandardOwner(with: bootstrapOwner)
    }
    await replaceStandardOwner(with: ownerID)
  }

  private func restoreOriginalOwnerDefaults() async {
    let authOwner = originalAuthOwner
    let ownerOverride = originalOwnerOverride
    let ownerBackup = originalOwnerBackup
    let effectiveOwner =
      ownerOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? ownerOverride
      : authOwner
    // Force one distinct completed generation first so even an authority that
    // a mismatch test deliberately left revoked is quiescent before restore.
    await replaceStandardOwner(with: "authorized-tool-owner-restore")
    do {
      try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
        defaults: .standard,
        allowAutomationOverride: true,
        plannedNextOwner: { _, _ in effectiveOwner },
        quiesceVoice: { _, _ in },
        revokeKernelOwner: { _, _ in },
        retargetLocalStorage: { _, _ in },
        ownerDidChange: {}
      ) { defaults in
        for (key, value) in [
          (DefaultsKey.authUserId, authOwner),
          (DefaultsKey.automationOwnerOverride, ownerOverride),
          (DefaultsKey.automationOwnerABackup, ownerBackup),
        ] {
          if let value {
            defaults.set(value, forKey: key.rawValue)
          } else {
            defaults.removeObject(forKey: key.rawValue)
          }
        }
      }
    } catch {
      XCTFail("owner restoration failed: \(error)")
    }
  }
}
