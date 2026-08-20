import XCTest

@testable import Omi_Computer

final class InsightLocalAuthorityTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "insight-local-authority")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testNewestHundredProjectionDoesNotDeleteOlderTipsOrOrdinaryMemories() async throws {
    let ordinary = try await insertMemory(content: "Ordinary memory", tags: ["personal"])
    for index in 0..<105 {
      _ = try await insertMemory(content: "Insight \(index)", tags: ["tips", "productivity"])
    }

    let projected = try await MemoryStorage.shared.listInsights(limit: 100, includeDismissed: true)
    let allTips = try await MemoryStorage.shared.listInsights(limit: 200, includeDismissed: true)
    let ordinaryAfter = try await MemoryStorage.shared.memory(id: ordinary.id)

    XCTAssertEqual(projected.count, 100)
    XCTAssertEqual(allTips.count, 105)
    XCTAssertEqual(ordinaryAfter?.content, "Ordinary memory")
    XCTAssertTrue(projected.allSatisfy { $0.tags.contains("tips") })
  }

  @MainActor
  func testRetiredInsightProjectionCacheIsDeletedAndNeverLoaded() throws {
    let suiteName = "insight-local-authority-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let key = "omi.advice.history.owner.some-owner"
    defaults.set(Data("stale".utf8), forKey: key)

    let storage = InsightStorage(defaults: defaults, startAutomatically: false)

    XCTAssertTrue(storage.insightHistory.isEmpty)
    XCTAssertNil(defaults.object(forKey: key))
  }

  private func insertMemory(content: String, tags: [String]) async throws -> MemoryItem {
    try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(
        content: content,
        category: .interesting,
        tags: tags,
        source: tags.contains("tips") ? .insight : .manual
      ),
      authorization: .unrestricted
    )
  }
}
