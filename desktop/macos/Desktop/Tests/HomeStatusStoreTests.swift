import XCTest

@testable import Omi_Computer

@MainActor
final class HomeStatusStoreTests: XCTestCase {
  func testRefreshLoadsLocalKnowledgeCounts() async throws {
    let store = HomeStatusStore(
      defaults: try isolatedDefaults(),
      loader: HomeStatusLoader(
        loadScreenshotCount: { 12 },
        loadKnowledgeCounts: {
          HomeKnowledgeCounts(conversations: 7, memories: 8, tasks: 9)
        }),
      localDatabaseReady: true)

    await store.refreshIfNeeded(force: true)

    XCTAssertEqual(store.screenshotCount, 12)
    XCTAssertEqual(store.conversationCount, 7)
    XCTAssertEqual(store.memoryCount, 8)
    XCTAssertEqual(store.taskCount, 9)
  }

  func testScreenshotCountWaitsUntilDatabaseIsReady() async throws {
    var screenshotLoads = 0
    let store = HomeStatusStore(
      defaults: try isolatedDefaults(),
      loader: HomeStatusLoader(
        loadScreenshotCount: {
          screenshotLoads += 1
          return 4
        },
        loadKnowledgeCounts: {
          HomeKnowledgeCounts(conversations: nil, memories: nil, tasks: nil)
        }))

    await store.refreshIfNeeded(force: true)
    XCTAssertEqual(screenshotLoads, 0)
    XCTAssertNil(store.screenshotCount)

    await store.databaseDidBecomeReady()
    XCTAssertEqual(screenshotLoads, 1)
    XCTAssertEqual(store.screenshotCount, 4)
  }

  func testResetClearsCachedValues() async throws {
    let store = HomeStatusStore(
      defaults: try isolatedDefaults(),
      loader: HomeStatusLoader(
        loadScreenshotCount: { 1 },
        loadKnowledgeCounts: {
          HomeKnowledgeCounts(conversations: 2, memories: 3, tasks: 4)
        }),
      localDatabaseReady: true)
    await store.refreshIfNeeded(force: true)

    store.resetSessionState()

    XCTAssertNil(store.screenshotCount)
    XCTAssertNil(store.conversationCount)
    XCTAssertNil(store.memoryCount)
    XCTAssertNil(store.taskCount)
  }

  private func isolatedDefaults() throws -> UserDefaults {
    let suite = "HomeStatusStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }
}
