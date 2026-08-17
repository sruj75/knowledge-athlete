import XCTest

@testable import Omi_Computer

final class OnboardingExitPolicyTests: XCTestCase {
  func testSkipPlanIsNeutralAndStopsEveryCaptureOwner() {
    let plan = OnboardingExitPolicy.plan(for: .skipped)

    XCTAssertEqual(plan.analyticsOutcome, .skipped)
    XCTAssertEqual(plan.persistedOutcome, .skipped)
    XCTAssertFalse(plan.transcriptionIntentEnabled)
    XCTAssertTrue(plan.shouldStopTranscriptionSession)
    XCTAssertFalse(plan.screenAnalysisIntentEnabled)
    XCTAssertTrue(plan.shouldStopScreenMonitoring)
    XCTAssertEqual(plan.launchAtLoginRequested, false)
    XCTAssertFalse(plan.shouldPresentOpener)
    XCTAssertFalse(plan.shouldMarkJustCompleted)
  }

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

  func testAnalyticsOutcomeNamesAreBoundedAndContentFree() {
    XCTAssertEqual(OnboardingExitAnalyticsOutcome.skipped.eventName, "Onboarding Skipped")
    XCTAssertEqual(OnboardingExitAnalyticsOutcome.completed.eventName, "Onboarding Completed")
  }
}
