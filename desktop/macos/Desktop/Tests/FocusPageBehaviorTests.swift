import XCTest

@testable import Omi_Computer

final class FocusPageBehaviorTests: XCTestCase {
  func testFocusHistoryDoesNotImplyAutomaticTracking() {
    XCTAssertEqual(FocusMonitoringPresentation.statusText, "Saved Focus history")
  }

  func testEmptyCopyAndRefreshLabelAreExact() {
    XCTAssertEqual(FocusMonitoringPresentation.emptyTitle, "No sessions yet")
    XCTAssertEqual(
      FocusMonitoringPresentation.emptyBody,
      "Your saved Focus sessions remain here. Automatic Focus tracking has been retired."
    )
    XCTAssertEqual(FocusMonitoringPresentation.refreshLabel, "Refresh")
    XCTAssertEqual(FocusMonitoringPresentation.historyTitle, "Today's sessions")
    XCTAssertEqual(
      FocusMonitoringPresentation.errorText("disk unavailable"),
      "Focus history could not be loaded: disk unavailable")
  }
}
