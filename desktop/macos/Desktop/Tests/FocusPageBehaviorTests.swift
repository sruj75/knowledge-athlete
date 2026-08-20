import XCTest

@testable import Omi_Computer

final class FocusPageBehaviorTests: XCTestCase {
  func testMonitoringStatusUsesCanonicalCaptureState() {
    XCTAssertEqual(
      FocusMonitoringPresentation.statusText(
        focusEnabled: false,
        captureStatus: .active),
      "Focus disabled"
    )
    XCTAssertEqual(
      FocusMonitoringPresentation.statusText(
        focusEnabled: true,
        captureStatus: .active),
      "Monitoring"
    )
    XCTAssertEqual(
      FocusMonitoringPresentation.statusText(
        focusEnabled: true,
        captureStatus: .inactive),
      "Capture off"
    )
    XCTAssertEqual(
      FocusMonitoringPresentation.statusText(
        focusEnabled: true,
        captureStatus: .blocked),
      "Capture blocked"
    )
  }

  func testEmptyCopyAndRefreshLabelAreExact() {
    XCTAssertEqual(FocusMonitoringPresentation.emptyTitle, "No sessions yet")
    XCTAssertEqual(
      FocusMonitoringPresentation.emptyBody,
      "Focus sessions appear here as you work.\nEnable Focus monitoring in Settings to begin."
    )
    XCTAssertEqual(FocusMonitoringPresentation.refreshLabel, "Refresh")
    XCTAssertEqual(FocusMonitoringPresentation.historyTitle, "Today's sessions")
    XCTAssertEqual(
      FocusMonitoringPresentation.errorText("disk unavailable"),
      "Focus history could not be loaded: disk unavailable")
  }
}
