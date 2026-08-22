import XCTest

@testable import Omi_Computer

@MainActor
final class SettingsDestinationContractTests: XCTestCase {
  func testEveryTypedDestinationIsSearchableAndEverySearchResultIsTyped() {
    let searchable = Set(SettingsSearchItem.allSearchableItems.map(\.destination))
    XCTAssertEqual(searchable, Set(SettingsDestination.allCases))
  }

  func testGroupedDestinationsRouteToTheirMountedOwnerSections() {
    XCTAssertEqual(
      SettingsSidebar.visibleSections,
      [
        .general, .account, .transcription, .floatingBar, .notifications, .rewind, .shortcuts,
        .advanced, .about,
      ])
    XCTAssertEqual(SettingsDestination.currentPlan.section, .planUsage)
    XCTAssertEqual(SettingsDestination.localData.section, .privacy)
    XCTAssertEqual(SettingsDestination.openOmiShortcut.section, .shortcuts)
    XCTAssertEqual(SettingsDestination.askMode.section, .advanced)
  }

  func testSearchOnlyExposesAlwaysMountedTargetsAndRevealsHiddenStatsContainer() {
    XCTAssertFalse(SettingsSearchItem.allSearchableItems.contains { $0.name == "Available Plans" })
    XCTAssertFalse(
      SettingsSearchItem.availableSearchItems(systemAudioSupported: false).contains {
        $0.destination == .systemAudio
      })
    XCTAssertTrue(
      SettingsSearchItem.availableSearchItems(systemAudioSupported: true).contains {
        $0.destination == .systemAudio
      })
    XCTAssertTrue(
      SettingsDestination.notificationFrequency.isMountedForSearch(
        systemAudioSupported: false))
    XCTAssertTrue(
      SettingsDestination.focusNotifications.isMountedForSearch(
        systemAudioSupported: false))
    XCTAssertTrue(
      SettingsDestination.autoInstallUpdates.isMountedForSearch(
        systemAudioSupported: false))
    XCTAssertTrue(SettingsDestination.aiUserProfile.revealsProfileAndStats)
    XCTAssertTrue(SettingsDestination.stats.revealsProfileAndStats)
    XCTAssertFalse(SettingsDestination.currentPlan.revealsProfileAndStats)
    XCTAssertEqual(
      SettingsDeepLinkPresentation(rawValue: SettingsDestination.stats.rawValue),
      SettingsDeepLinkPresentation(
        settingId: SettingsDestination.stats.rawValue,
        revealsProfileAndStats: true))

    var refreshState = SettingsStatsRefreshState()
    let mountedTaskID = refreshState.ownerGeneration
    refreshState.ownerDidChange()
    XCTAssertNotEqual(refreshState.ownerGeneration, mountedTaskID)

    XCTAssertEqual(Set(PlanUsageCardIdentity.allCases.map(\.rawValue)).count, 4)
    XCTAssertEqual(
      PlanUsageCardIdentity.currentPlan.rawValue,
      SettingsDestination.currentPlan.rawValue)
  }

  func testBrokenAndDuplicateDestinationsAreNotRepresentable() {
    let rawValues = Set(SettingsDestination.allCases.map(\.rawValue))
    XCTAssertFalse(rawValues.contains("account.signout"))
    XCTAssertFalse(rawValues.contains("planusage.overview"))
    XCTAssertFalse(rawValues.contains("privacy.privacy"))
    XCTAssertFalse(rawValues.contains("advanced.goals"))
    XCTAssertFalse(rawValues.contains("advanced.goals.autogenerate"))
    XCTAssertFalse(rawValues.contains("planusage.purchase"))
  }

  /// Source-inspection tripwire for exact retired About labels assigned by S-21.
  func testAboutRemovesHelpCenterAndUsesLocalPrivacyAndDataLabel() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(
        "Sources/MainWindow/Pages/Settings/Components/SettingsContentView+Controls.swift")
    // omi-test-quality: source-inspection -- static contract: the retired remote Help Center and Privacy Policy labels must not return; typed Settings routing is exercised by the other contract tests.
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertFalse(source.contains("Help Center"))
    XCTAssertFalse(source.contains("Privacy Policy"))
    XCTAssertTrue(source.contains("Privacy & Data"))
  }
}
