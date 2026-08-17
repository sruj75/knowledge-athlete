import XCTest

@testable import Omi_Computer

/// IR-145 is the external product authority for the expected value here:
/// genuine onboarding completion requests Launch at Login on, while the
/// ordinary Settings control remains free to request it off later.
@MainActor
final class SBOnboardingLaunchAtLoginCompletionTests: XCTestCase {
  func testIR145CompletionAlwaysRequestsLaunchAtLoginEnabled() {
    for selection in [SBOnboardingModel.CaptureSelection.onlyDuringMeetings, .continuous] {
      let plan = OnboardingExitPolicy.plan(for: .completed(selection))
      XCTAssertTrue(plan.launchAtLoginRequested)
      XCTAssertEqual(
        LaunchAtLoginIntentPolicy.requestedEnabled(for: .onboardingCompletion),
        true)
    }
  }

  func testSettingsCanSubsequentlyRequestLaunchAtLoginDisabled() {
    XCTAssertFalse(LaunchAtLoginIntentPolicy.requestedEnabled(for: .settings(false)))
    XCTAssertFalse(LaunchAtLoginIntentPolicy.requestedEnabled(for: .onboardingSkip))
  }

  func testFailedRegistrationDoesNotReportAFalseSuccess() {
    var requested: Bool?
    var reports: [(Bool, String)] = []

    let succeeded = LaunchAtLoginIntentPolicy.apply(
      .onboardingCompletion,
      setEnabled: {
        requested = $0
        return false
      },
      report: { reports.append(($0, $1)) })

    XCTAssertFalse(succeeded)
    XCTAssertEqual(requested, true)
    XCTAssertTrue(reports.isEmpty)
  }

  func testSuccessfulSettingsDisableReportsUserSource() {
    var reports: [(Bool, String)] = []

    let succeeded = LaunchAtLoginIntentPolicy.apply(
      .settings(false),
      setEnabled: { _ in true },
      report: { reports.append(($0, $1)) })

    XCTAssertTrue(succeeded)
    XCTAssertEqual(reports.count, 1)
    XCTAssertEqual(reports.first?.0, false)
    XCTAssertEqual(reports.first?.1, "user")
  }
}
