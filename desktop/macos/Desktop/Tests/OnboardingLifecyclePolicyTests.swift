import XCTest

@testable import Omi_Computer

final class OnboardingLifecyclePolicyTests: XCTestCase {
  func testDirectFlagIsACompletionOnlyBypass() {
    XCTAssertEqual(
      DirectOnboardingBypassPolicy.action(arguments: ["omi", "--skip-onboarding"]),
      .markCompletionOnly)
    XCTAssertEqual(
      DirectOnboardingBypassPolicy.action(arguments: ["omi", "--mode=rewind"]),
      .none)
  }

  func testLastWindowTerminatesOnlyBeforeCompletion() {
    XCTAssertTrue(
      OnboardingWindowLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
        hasCompletedOnboarding: false))
    XCTAssertFalse(
      OnboardingWindowLifecyclePolicy.shouldTerminateAfterLastWindowClosed(
        hasCompletedOnboarding: true))
  }

  func testAppKitRelaunchIsEnabledOnlyForCompletedProductionBundles() {
    XCTAssertEqual(
      AppKitRelaunchAtLogoutPolicy.decision(
        isProductionBundle: true,
        hasCompletedOnboarding: false),
      .disable)
    XCTAssertEqual(
      AppKitRelaunchAtLogoutPolicy.decision(
        isProductionBundle: true,
        hasCompletedOnboarding: true),
      .enable)
    XCTAssertEqual(
      AppKitRelaunchAtLogoutPolicy.decision(
        isProductionBundle: false,
        hasCompletedOnboarding: true),
      .disable)
  }

  func testCompletionWinsOverResumeAndJournalDisagreement() {
    let resolution = OnboardingSetupAuthorityPolicy.resolve(
      hasCompletedOnboarding: true,
      hasActiveStage: true,
      hasPersistedResume: true,
      hasActiveJournal: true)

    XCTAssertTrue(resolution.hasCompletedOnboarding)
    XCTAssertEqual(
      Set(resolution.disagreements.map(\.target)),
      [.stage, .persistedResume, .setupJournal])
    XCTAssertTrue(resolution.disagreements.allSatisfy { $0.source == .completedFlag })
  }

  func testLegacyLoginMigrationIsAbsent() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/OmiApp.swift")
    // omi-test-quality: source-inspection -- static contract: the explicitly retired login-item migration and its persisted marker must remain absent; lifecycle behavior is covered above through typed production policies
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertFalse(source.contains("migrateLaunchAtLoginDefault"))
    XCTAssertFalse(source.contains("didMigrateLaunchAtLoginV1"))
  }
}
