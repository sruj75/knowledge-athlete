import XCTest

@testable import Omi_Computer

@MainActor
final class SBOnboardingCaptureSelectionTests: XCTestCase {
  func testDefaultCaptureSelectionRecordsOnlyDuringMeetings() {
    let selection = SBOnboardingModel.defaultCaptureSelection

    XCTAssertEqual(selection.systemAudioCaptureMode, .onlyDuringMeetings)
    XCTAssertFalse(selection.capturesWithoutActiveMeeting)
  }

  func testContinuousCaptureSelectionCapturesWithoutActiveMeeting() {
    let selection = SBOnboardingModel.CaptureSelection.continuous

    XCTAssertEqual(selection.systemAudioCaptureMode, .always)
    XCTAssertTrue(selection.capturesWithoutActiveMeeting)
  }
}
