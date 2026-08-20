import XCTest

@testable import Omi_Computer

private actor PausingInsightMutationPersistence: InsightMutationPersisting {
  private var markAllStarted = false
  private var markAllStartWaiters: [CheckedContinuation<Void, Never>] = []
  private var markAllRelease: CheckedContinuation<Void, Never>?

  func persistMarkInsightRead(
    id: String,
    authorization: LocalMutationAuthorization
  ) async throws {}

  func persistMarkAllInsightsRead(authorization: LocalMutationAuthorization) async throws {
    markAllStarted = true
    let waiters = markAllStartWaiters
    markAllStartWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { markAllRelease = $0 }
  }

  func persistMarkInsightDismissed(
    id: String,
    isDismissed: Bool,
    authorization: LocalMutationAuthorization
  ) async throws {}

  func persistDeleteInsight(
    id: String,
    authorization: LocalMutationAuthorization
  ) async throws {}

  func persistClearInsights(authorization: LocalMutationAuthorization) async throws -> Int { 0 }

  func waitUntilMarkAllStarts() async {
    guard !markAllStarted else { return }
    await withCheckedContinuation { markAllStartWaiters.append($0) }
  }

  func releaseMarkAll() {
    markAllRelease?.resume()
    markAllRelease = nil
  }
}

final class InsightMutationBehaviorTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "insight-mutations")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testExactAndBulkMutationsAreStrictlyTipsScoped() async throws {
    let ordinary = try await insert(content: "Keep me", tags: ["personal"])
    let first = try await insert(content: "First tip", tags: ["tips", "health"])
    let second = try await insert(content: "Second tip", tags: ["tips", "learning"])

    try await MemoryStorage.shared.markInsightRead(
      id: first.id,
      authorization: .unrestricted
    )
    try await MemoryStorage.shared.markInsightDismissed(
      id: second.id,
      isDismissed: true,
      authorization: .unrestricted
    )
    try await MemoryStorage.shared.markAllInsightsRead(authorization: .unrestricted)

    let firstAfter = try await MemoryStorage.shared.memory(id: first.id)
    let secondAfter = try await MemoryStorage.shared.memory(id: second.id)
    let ordinaryAfter = try await MemoryStorage.shared.memory(id: ordinary.id)
    XCTAssertEqual(firstAfter?.isRead, true)
    XCTAssertEqual(secondAfter?.isDismissed, true)
    XCTAssertEqual(ordinaryAfter?.isRead, false)

    try await MemoryStorage.shared.deleteInsight(
      id: first.id,
      authorization: .unrestricted
    )
    let deleted = try await MemoryStorage.shared.memory(id: first.id)
    XCTAssertNil(deleted)

    let cleared = try await MemoryStorage.shared.clearInsights(authorization: .unrestricted)
    XCTAssertEqual(cleared, 1)
    let ordinaryRetained = try await MemoryStorage.shared.memory(id: ordinary.id)
    XCTAssertNotNil(ordinaryRetained)
  }

  func testOrdinaryMemoryCannotBeMutatedThroughInsightSurface() async throws {
    let ordinary = try await insert(content: "Protected", tags: ["personal"])

    do {
      try await MemoryStorage.shared.markInsightRead(
        id: ordinary.id,
        authorization: .unrestricted
      )
      XCTFail("ordinary Memory unexpectedly admitted through Insight mutation surface")
    } catch {
      XCTAssertEqual(error as? MemoryStorageError, .recordNotFound)
    }
  }

  func testMutationErrorsHaveVisiblePresentationCopy() {
    XCTAssertEqual(
      InsightErrorPresentation.message("disk unavailable"),
      "Insights could not be updated: disk unavailable")
  }

  private func insert(content: String, tags: [String]) async throws -> MemoryItem {
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

@MainActor
final class InsightMutationOwnerFenceTests: XCTestCase {
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func tearDown() async throws {
    await ownerFixture.restore()
  }

  func testCompletedMutationCannotPublishAcrossOwnerScopeReset() async {
    await ownerFixture.establish(authOwnerID: "insight-owner-a")
    let center = NotificationCenter()
    let persistence = PausingInsightMutationPersistence()
    let storage = InsightStorage(
      startAutomatically: false,
      notificationCenter: center,
      mutationPersistence: persistence)
    storage.addInsight(insightResult("Owner A"), memoryID: 1)

    let mutation = Task { await storage.markAllAsRead() }
    await persistence.waitUntilMarkAllStarts()

    center.post(name: .runtimeOwnerDidChange, object: nil)
    storage.addInsight(insightResult("Owner B"), memoryID: 2)
    await persistence.releaseMarkAll()
    await mutation.value

    XCTAssertEqual(storage.insightHistory.map(\.id), ["2"])
    XCTAssertEqual(storage.insightHistory.first?.isRead, false)
    XCTAssertNil(storage.lastSyncError)
  }

  private func insightResult(_ text: String) -> InsightExtractionResult {
    InsightExtractionResult(
      hasInsight: true,
      insight: ExtractedInsight(
        insight: text,
        headline: nil,
        reasoning: nil,
        category: .productivity,
        sourceApp: "Tests",
        confidence: 1),
      contextSummary: "Context",
      currentActivity: "Testing")
  }
}
