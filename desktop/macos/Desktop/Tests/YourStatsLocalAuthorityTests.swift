import XCTest

@testable import Omi_Computer

private actor StatsReadGate {
  private var entered = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func pause() async {
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

@MainActor
final class YourStatsLocalAuthorityTests: XCTestCase {
  private enum TestError: Error { case failed }
  private enum SuspendedReader: String, CaseIterable {
    case conversations
    case chatMessages
    case screenshots
    case focusSessions
    case taskCounts
    case goals
    case memories
  }

  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture?.establish(authOwnerID: "stats-owner")
  }

  override func tearDown() async throws {
    await ownerFixture?.restore()
    ownerFixture = nil
  }

  func testLoaderComposesEveryRetainedLocalCount() async throws {
    let loaded = try await YourStatsLocalLoader.load(readers: readers())
    let snapshot = try XCTUnwrap(loaded)
    XCTAssertEqual(
      snapshot,
      YourStatsSnapshot(
        conversations: 1,
        chatMessages: 2,
        screenshots: 3,
        focusSessions: 4,
        tasksTodo: 5,
        tasksDone: 6,
        tasksDeleted: 7,
        goals: 8,
        memories: 9
      )
    )
  }

  func testChatAndScreenshotFailuresUseTheDecidedZeroFallbacks() async throws {
    var readers = readers()
    readers.chatMessages = { _ in throw TestError.failed }
    readers.screenshots = { _ in throw TestError.failed }

    let loaded = try await YourStatsLocalLoader.load(readers: readers)
    let snapshot = try XCTUnwrap(loaded)
    XCTAssertEqual(snapshot.chatMessages, 0)
    XCTAssertEqual(snapshot.screenshots, 0)
    XCTAssertEqual(snapshot.conversations, 1)
  }

  func testChatCountUsesTheCapturedOwnerAuthorizedCatalog() async throws {
    let expectedAuthorization = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var receivedAuthorization: RuntimeOwnerAuthorizationSnapshot?

    let count = try await YourStatsChatCatalogReader.messageCount(
      authorizationSnapshot: expectedAuthorization,
      catalogReader: { authorization in
        receivedAuthorization = authorization
        return LocalChatCatalogSnapshot(
          chats: [
            try self.chatSummary(id: "default", messageCount: 4),
            try self.chatSummary(id: "named", messageCount: 7),
          ],
          retainedAttachmentURIs: [])
      })

    XCTAssertEqual(receivedAuthorization, expectedAuthorization)
    XCTAssertEqual(count, 11)
  }

  func testChatCountRejectsCatalogResultAfterOwnerChanges() async throws {
    let expectedAuthorization = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    do {
      _ = try await YourStatsChatCatalogReader.messageCount(
        authorizationSnapshot: expectedAuthorization,
        catalogReader: { [ownerFixture] _ in
          await ownerFixture?.establish(authOwnerID: "stats-owner-b")
          return LocalChatCatalogSnapshot(chats: [], retainedAttachmentURIs: [])
        })
      XCTFail("owner-A catalog result must fail closed")
    } catch {
      guard case BridgeError.authMissing = error else {
        return XCTFail("expected authMissing, got \(error)")
      }
    }
  }

  func testRequiredReaderFailurePreservesCardFailure() async {
    var readers = readers()
    readers.memories = { _ in throw TestError.failed }

    do {
      _ = try await YourStatsLocalLoader.load(readers: readers)
      XCTFail("required local reader failure must fail the combined card")
    } catch {
      XCTAssertTrue(error is TestError)
    }
  }

  func testOwnerSwitchWhileAnyReaderIsSuspendedCannotPublishOldCounts() async throws {
    for suspendedReader in SuspendedReader.allCases {
      await ownerFixture?.establish(authOwnerID: "stats-owner")
      let gate = StatsReadGate()
      let load = Task { @MainActor in
        try await YourStatsLocalLoader.load(readers: readers(pausing: suspendedReader, at: gate))
      }

      await gate.waitUntilEntered()
      await ownerFixture?.establish(authOwnerID: "stats-owner-b")
      await gate.release()

      let snapshot = try await load.value
      XCTAssertNil(snapshot, "\(suspendedReader.rawValue) published an owner-A projection")
    }
  }

  func testSameUIDABAWhileAnyReaderIsSuspendedCannotPublishOldCounts() async throws {
    for suspendedReader in SuspendedReader.allCases {
      await ownerFixture?.establish(authOwnerID: "stats-owner")
      let gate = StatsReadGate()
      let load = Task { @MainActor in
        try await YourStatsLocalLoader.load(readers: readers(pausing: suspendedReader, at: gate))
      }

      await gate.waitUntilEntered()
      await ownerFixture?.establish(authOwnerID: "stats-owner")
      await gate.release()

      let snapshot = try await load.value
      XCTAssertNil(snapshot, "\(suspendedReader.rawValue) published a pre-ABA projection")
    }
  }

  private func readers() -> YourStatsLocalReaders {
    YourStatsLocalReaders(
      conversations: { _ in 1 },
      chatMessages: { _ in 2 },
      screenshots: { _ in 3 },
      focusSessions: { _ in 4 },
      taskCounts: { _ in YourStatsTaskCounts(todo: 5, done: 6, deleted: 7) },
      goals: { _ in 8 },
      memories: { _ in 9 }
    )
  }

  private func chatSummary(id: String, messageCount: Int) throws -> LocalChatSummary {
    try XCTUnwrap(
      LocalChatSummary(dictionary: [
        "chatId": id,
        "title": id,
        "titleOrigin": "default",
        "messageCount": messageCount,
        "createdAtMs": 1_000,
        "lastActivityAtMs": 2_000,
        "starred": false,
      ]))
  }

  private func readers(
    pausing suspendedReader: SuspendedReader,
    at gate: StatsReadGate
  ) -> YourStatsLocalReaders {
    var result = readers()
    switch suspendedReader {
    case .conversations:
      result.conversations = { _ in
        await gate.pause()
        return 1
      }
    case .chatMessages:
      result.chatMessages = { _ in
        await gate.pause()
        return 2
      }
    case .screenshots:
      result.screenshots = { _ in
        await gate.pause()
        return 3
      }
    case .focusSessions:
      result.focusSessions = { _ in
        await gate.pause()
        return 4
      }
    case .taskCounts:
      result.taskCounts = { _ in
        await gate.pause()
        return YourStatsTaskCounts(todo: 5, done: 6, deleted: 7)
      }
    case .goals:
      result.goals = { _ in
        await gate.pause()
        return 8
      }
    case .memories:
      result.memories = { _ in
        await gate.pause()
        return 9
      }
    }
    return result
  }
}
