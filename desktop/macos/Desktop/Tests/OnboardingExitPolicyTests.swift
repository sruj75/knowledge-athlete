import XCTest

@testable import Omi_Computer

final class OnboardingExitPolicyTests: XCTestCase {
  func testMeetingOnlyCompletionArmsOneMeetingGatedTranscriptionSession() {
    let plan = OnboardingExitPolicy.plan(for: .completed(.onlyDuringMeetings))

    XCTAssertEqual(plan.systemAudioCaptureMode, .onlyDuringMeetings)
    XCTAssertTrue(plan.transcriptionIntentEnabled)
    XCTAssertTrue(plan.shouldStartTranscriptionSession)
    XCTAssertFalse(plan.shouldCaptureWithoutActiveMeeting)
  }

  func testContinuousCompletionArmsOneImmediatelyCapturingTranscriptionSession() {
    let plan = OnboardingExitPolicy.plan(for: .completed(.continuous))

    XCTAssertEqual(plan.systemAudioCaptureMode, .always)
    XCTAssertTrue(plan.transcriptionIntentEnabled)
    XCTAssertTrue(plan.shouldStartTranscriptionSession)
    XCTAssertTrue(plan.shouldCaptureWithoutActiveMeeting)
  }

  func testListeningChoiceDoesNotDependOnCalendarOrPermissionInputs() {
    XCTAssertEqual(
      OnboardingExitPolicy.plan(for: .completed(.onlyDuringMeetings)),
      OnboardingExitPolicy.plan(for: .completed(.onlyDuringMeetings)))
  }
}
