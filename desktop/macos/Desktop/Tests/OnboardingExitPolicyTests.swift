import XCTest

@testable import Omi_Computer

final class OnboardingExitPolicyTests: XCTestCase {
  func testSkipPlanIsNeutralAndStopsEveryCaptureOwner() {
    let plan = OnboardingExitPolicy.plan(for: .skipped)

    XCTAssertEqual(plan.analyticsOutcome, .skipped)
    XCTAssertEqual(plan.persistedOutcome, .skipped)
    XCTAssertNil(plan.systemAudioCaptureMode)
    XCTAssertFalse(plan.transcriptionIntentEnabled)
    XCTAssertFalse(plan.shouldStartTranscriptionSession)
    XCTAssertTrue(plan.shouldStopTranscriptionSession)
    XCTAssertFalse(plan.screenAnalysisIntentEnabled)
    XCTAssertTrue(plan.shouldStopScreenMonitoring)
    XCTAssertEqual(plan.launchAtLoginRequested, false)
    XCTAssertFalse(plan.shouldPresentOpener)
    XCTAssertFalse(plan.shouldMarkJustCompleted)
  }

  func testCompletionAlwaysEnablesAllDayListening() {
    let plan = OnboardingExitPolicy.plan(for: .completed)

    XCTAssertEqual(plan.analyticsOutcome, .completed)
    XCTAssertEqual(plan.persistedOutcome, .completed)
    XCTAssertEqual(plan.systemAudioCaptureMode, .always)
    XCTAssertTrue(plan.transcriptionIntentEnabled)
    XCTAssertTrue(plan.shouldStartTranscriptionSession)
    XCTAssertFalse(plan.shouldStopTranscriptionSession)
  }

  func testAnalyticsOutcomeNamesAreBoundedAndContentFree() {
    XCTAssertEqual(OnboardingExitAnalyticsOutcome.skipped.eventName, "Onboarding Skipped")
    XCTAssertEqual(OnboardingExitAnalyticsOutcome.completed.eventName, "Onboarding Completed")
  }
}
