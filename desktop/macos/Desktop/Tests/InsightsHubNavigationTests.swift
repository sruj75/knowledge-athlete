import XCTest

@testable import Omi_Computer

@MainActor
final class InsightsHubNavigationTests: XCTestCase {
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func tearDown() async throws {
    await ownerFixture.restore()
  }

  func testRequestCarriesTypedSegmentAndStableLocalInsightID() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let center = NotificationCenter()
    let store = InsightsHubNavigationStore(notificationCenter: center)

    XCTAssertTrue(store.request(segment: .insights, insightID: "42"))
    let request = try XCTUnwrap(store.consume())

    XCTAssertEqual(request.segment, .insights)
    XCTAssertEqual(request.insightID, "42")
    XCTAssertEqual(request.authorizationSnapshot.ownerID, "owner-a")
    XCTAssertNil(store.pendingRequest)
  }

  func testRevokedOwnerRequestFailsClosedAsUnavailable() async {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let center = NotificationCenter()
    let store = InsightsHubNavigationStore(notificationCenter: center)
    XCTAssertTrue(store.request(segment: .insights, insightID: "42"))

    await ownerFixture.establish(authOwnerID: "owner-b")

    XCTAssertNil(store.consume())
    XCTAssertEqual(store.unavailableMessage, "Insight unavailable")
  }

  func testCanonicalHubIsTheOnlyInsightsRoute() {
    XCTAssertEqual(InsightsHubSegment.allCases, [.insights, .focus])
    XCTAssertEqual(DesktopDestination.insights.rawValue, 5)
    XCTAssertNil(DesktopDestination(rawValue: 6))
    XCTAssertEqual(
      TopNavigationRoutes.primaryItems.map(\.title),
      ["Home", "Memory", "Tasks", "Insights"]
    )
  }

  func testTopLevelInsightsRequestResetsAPreviouslySelectedFocusSegment() async {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let store = InsightsHubNavigationStore(notificationCenter: NotificationCenter())
    XCTAssertTrue(store.request(segment: .focus))
    XCTAssertEqual(store.consume()?.segment, .focus)

    XCTAssertTrue(store.request(segment: .insights))

    XCTAssertEqual(store.consume()?.segment, .insights)
  }

  func testPrimaryShortcutsMatchCanonicalNavigationAndExcludeNumberedRewind() {
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "1"), .home)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "2"), .memories)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "3"), .tasks)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "4"), .insights)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: ","), .settings)
    XCTAssertNil(DesktopNavigationPolicy.destination(forShortcut: "5"))
    XCTAssertNil(DesktopNavigationPolicy.destination(forShortcut: "rewind"))
    XCTAssertEqual(MemoryHubDestination.destination(for: .memories), .memories)
    XCTAssertEqual(MemoryHubDestination.destination(for: .memory), .conversations)
  }
}
