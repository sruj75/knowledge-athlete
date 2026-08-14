import XCTest

@testable import Omi_Computer

@MainActor
final class HomeStatusStoreTests: XCTestCase {
  func testRefreshLoadsRetainedKnowledgeCounts() async {
    let defaults = isolatedDefaults()
    defaults.set("user-a", forKey: DefaultsKey.authUserId.rawValue)
    let store = HomeStatusStore(
      defaults: defaults,
      loader: HomeStatusLoader(
        loadScreenshotCount: { 12 },
        loadKnowledgeCounts: { includeDeviceHistory in
          XCTAssertTrue(includeDeviceHistory)
          return HomeKnowledgeCounts(
            conversations: 7,
            memories: 8,
            tasks: 9,
            hasOmiDeviceConversations: true
          )
        }
      ),
      localDatabaseReady: true
    )

    await store.refreshIfNeeded(force: true)

    XCTAssertEqual(store.screenshotCount, 12)
    XCTAssertEqual(store.conversationCount, 7)
    XCTAssertEqual(store.memoryCount, 8)
    XCTAssertEqual(store.taskCount, 9)
    XCTAssertTrue(store.accountHasOmiDeviceConversations)
  }

  func testScreenshotCountWaitsUntilDatabaseIsReady() async {
    var screenshotLoads = 0
    let store = HomeStatusStore(
      defaults: isolatedDefaults(),
      loader: HomeStatusLoader(
        loadScreenshotCount: {
          screenshotLoads += 1
          return 4
        },
        loadKnowledgeCounts: { _ in
          HomeKnowledgeCounts(
            conversations: nil,
            memories: nil,
            tasks: nil,
            hasOmiDeviceConversations: nil
          )
        }
      )
    )

    await store.refreshIfNeeded(force: true)
    XCTAssertEqual(screenshotLoads, 0)
    XCTAssertNil(store.screenshotCount)

    await store.databaseDidBecomeReady()
    XCTAssertEqual(screenshotLoads, 1)
    XCTAssertEqual(store.screenshotCount, 4)
  }

  func testResetClearsCachedValues() async {
    let store = HomeStatusStore(
      defaults: isolatedDefaults(),
      loader: HomeStatusLoader(
        loadScreenshotCount: { 1 },
        loadKnowledgeCounts: { _ in
          HomeKnowledgeCounts(
            conversations: 2,
            memories: 3,
            tasks: 4,
            hasOmiDeviceConversations: nil
          )
        }
      ),
      localDatabaseReady: true
    )
    await store.refreshIfNeeded(force: true)

    store.resetSessionState()

    XCTAssertNil(store.screenshotCount)
    XCTAssertNil(store.conversationCount)
    XCTAssertNil(store.memoryCount)
    XCTAssertNil(store.taskCount)
    XCTAssertFalse(store.accountHasOmiDeviceConversations)
  }

  private func isolatedDefaults() -> UserDefaults {
    let suite = "HomeStatusStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }
}
