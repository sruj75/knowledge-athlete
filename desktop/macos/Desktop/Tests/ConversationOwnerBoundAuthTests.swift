import Foundation
import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

extension APIClient {
  fileprivate func setOwnerBoundTestAuthHeader(_ header: String) {
    testAuthHeader = header
  }
}

private final class ConversationRequestGate: @unchecked Sendable {
  private struct RequestWaiter {
    let path: String
    let continuation: CheckedContinuation<URLRequest, Never>
  }

  private let lock = NSLock()
  private var pendingProtocols: [ConversationOwnerURLProtocol] = []
  private var selectedProtocols: [String: ConversationOwnerURLProtocol] = [:]
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
  func receive(_ urlProtocol: ConversationOwnerURLProtocol) {
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

  func succeed(path: String, with body: String) async throws {
    let pendingProtocol: ConversationOwnerURLProtocol? = lock.withLock {
      let proto = selectedProtocols.removeValue(forKey: path)
      if let proto {
        pendingProtocols.removeAll { $0 === proto }
      }
      return proto
    }
    guard let pendingProtocol else { return }
    let requestURL = try XCTUnwrap(pendingProtocol.request.url)
    let response = try XCTUnwrap(
      HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      ))
    pendingProtocol.client?.urlProtocol(
      pendingProtocol,
      didReceive: response,
      cacheStoragePolicy: .notAllowed)
    pendingProtocol.client?.urlProtocol(pendingProtocol, didLoad: Data(body.utf8))
    pendingProtocol.client?.urlProtocolDidFinishLoading(pendingProtocol)
  }
}

private final class ConversationOwnerURLProtocol: URLProtocol, @unchecked Sendable {
  static let gate = ConversationRequestGate()

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

@MainActor final class ConversationOwnerBoundAuthTests: XCTestCase {
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
    await ConversationOwnerURLProtocol.gate.reset()
  }

  func testPromptReceiptNeverEscapesAfterMidFlightAccountSwitch() async throws {
    let client = await makeClient()
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let operation = Task { @MainActor in
      do {
        _ = try await client.bootstrapConversation(
          conversationID: "test-conversation",
          authorizationSnapshot: snapshot)
        return false
      } catch AuthError.userChangedDuringRequest {
        return true
      } catch {
        return false
      }
    }

    let request = await ConversationOwnerURLProtocol.gate.waitForRequest(path: "/v1/conversation/session")
    XCTAssertEqual(request.url?.path, "/v1/conversation/session")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-a-token")

    UserDefaults.standard.set("owner-b", forKey: .authUserId)
    try await ConversationOwnerURLProtocol.gate.succeed(
      path: "/v1/conversation/session",
      with:
        #"{"conversation_id":"test-conversation","prompt":{"text":"private","name":"intentive-live-system","version":"1","source":"langfuse","sha256":"not-released"}}"#
    )

    let rejectedLateToken = await operation.value
    XCTAssertTrue(rejectedLateToken)
  }

  private func makeClient() async -> APIClient {
    await ConversationOwnerURLProtocol.gate.reset()
    await establishStandardOwner("owner-a")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConversationOwnerURLProtocol.self]
    let client = APIClient(
      session: URLSession(configuration: configuration), testBaseURL: "https://owner-bound.invalid/")
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
    let bootstrapOwner = "conversation-owner-bootstrap"
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
    await replaceStandardOwner(with: "conversation-owner-restore")
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
