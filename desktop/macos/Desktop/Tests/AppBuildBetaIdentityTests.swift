import XCTest

@testable import Omi_Computer

/// The Intentive Beta identity must behave as a shipped
/// production artifact — never as a dev/test bundle — while keeping its own update
/// channel, storage root, and log path so it can run beside stable.
final class AppBuildBetaIdentityTests: XCTestCase {
  private let validReleaseInfo: [String: Any] = [
    AppBuild.sparkleFeedInfoKey: "https://updates.heyintentive.com/v2/desktop/appcast.xml",
    AppBuild.sparklePublicKeyInfoKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    AppBuild.manualDownloadInfoKey: "https://updates.heyintentive.com/v2/desktop/download/latest",
    AppBuild.releasesInfoKey: "https://github.com/sruj75/knowledge-athlete/releases",
  ]

  func testBetaIdentityIsProductionGrade() {
    let config = AppBuild.configuration(
      bundleIdentifier: AppBuild.betaProductionBundleIdentifier,
      infoDictionary: validReleaseInfo)

    XCTAssertFalse(config.isNonProduction)
    XCTAssertFalse(config.allowsLocalAutomation)
    XCTAssertTrue(config.allowsSparkleUpdates)
    XCTAssertFalse(config.isExternalPreview)
  }

  func testStableIdentityGatingIsUnchanged() {
    let config = AppBuild.configuration(
      bundleIdentifier: AppBuild.productionBundleIdentifier,
      infoDictionary: validReleaseInfo)

    XCTAssertFalse(config.isNonProduction)
    XCTAssertFalse(config.allowsLocalAutomation)
    XCTAssertTrue(config.allowsSparkleUpdates)
  }

  func testNamedDevBundleStaysNonProduction() {
    let config = AppBuild.configuration(
      bundleIdentifier: "com.heyintentive.intentive.dev.feature-test",
      infoDictionary: validReleaseInfo)

    XCTAssertTrue(config.isNonProduction)
    XCTAssertTrue(config.allowsLocalAutomation)
  }

  func testProductionFamilyMembership() {
    XCTAssertEqual(
      AppBuild.productionFamilyBundleIdentifiers,
      [AppBuild.productionBundleIdentifier, AppBuild.betaProductionBundleIdentifier])
  }

  func testManualDownloadURLCarriesBetaIdentity() {
    XCTAssertEqual(
      AppBuild.manualDownloadURL(
        infoDictionary: validReleaseInfo, channel: "beta", isBetaIdentity: true)?.absoluteString,
      "https://updates.heyintentive.com/v2/desktop/download/latest?channel=beta&identity=beta")
    XCTAssertEqual(
      AppBuild.manualDownloadURL(
        infoDictionary: validReleaseInfo, channel: "beta", isBetaIdentity: false)?.absoluteString,
      "https://updates.heyintentive.com/v2/desktop/download/latest?channel=beta")
    XCTAssertEqual(
      AppBuild.manualDownloadURL(
        infoDictionary: validReleaseInfo, channel: "stable", isBetaIdentity: false)?.absoluteString,
      "https://updates.heyintentive.com/v2/desktop/download/latest?channel=stable")
  }

  func testChangelogURLUsesExactOwnedRunningVersionTag() {
    XCTAssertEqual(
      AppBuild.changelogURL(
        infoDictionary: validReleaseInfo,
        isProductionBundle: true,
        releaseTag: "v1.2.3+12003-macos")?.absoluteString,
      "https://github.com/sruj75/knowledge-athlete/releases/tag/v1.2.3%2B12003-macos"
    )
    XCTAssertEqual(
      AppBuild.changelogURL(
        infoDictionary: validReleaseInfo,
        isProductionBundle: false,
        releaseTag: "v1.2.3+12003-macos")?.absoluteString,
      "https://github.com/sruj75/knowledge-athlete/releases"
    )
  }

  func testProductionUpdaterFailsClosedWithoutSignedReleaseMetadata() {
    let config = AppBuild.configuration(
      bundleIdentifier: AppBuild.productionBundleIdentifier,
      infoDictionary: [:])

    XCTAssertTrue(config.identity?.isProductionFamily == true)
    XCTAssertNil(config.releaseConfiguration)
    XCTAssertFalse(config.allowsSparkleUpdates)
  }

  func testProductionUpdaterRejectsInheritedOmiReleaseMetadata() {
    var inherited = validReleaseInfo
    inherited[AppBuild.sparkleFeedInfoKey] = "https://api.omi.me/v2/desktop/appcast.xml"

    let config = AppBuild.configuration(
      bundleIdentifier: AppBuild.productionBundleIdentifier,
      infoDictionary: inherited)

    XCTAssertNil(config.releaseConfiguration)
    XCTAssertFalse(config.allowsSparkleUpdates)
  }

  func testProductionUpdaterRejectsMalformedSparklePublicKey() {
    var malformed = validReleaseInfo
    malformed[AppBuild.sparklePublicKeyInfoKey] = "not-a-32-byte-base64-key"

    let config = AppBuild.configuration(
      bundleIdentifier: AppBuild.productionBundleIdentifier,
      infoDictionary: malformed)

    XCTAssertNil(config.releaseConfiguration)
    XCTAssertFalse(config.allowsSparkleUpdates)
  }

  func testProductionUpdaterRejectsAReleaseRepositoryIdentityMismatch() {
    var mismatched = validReleaseInfo
    mismatched[AppBuild.releasesInfoKey] = "https://github.com/BasedHardware/omi/releases"

    let config = AppBuild.configuration(
      bundleIdentifier: AppBuild.productionBundleIdentifier,
      infoDictionary: mismatched)

    XCTAssertNil(config.releaseConfiguration)
    XCTAssertFalse(config.allowsSparkleUpdates)
  }

  func testPublicDestinationsAcceptOnlyTheOwnedDomain() {
    XCTAssertEqual(
      AppBuild.publicDestinationURL(
        infoDictionary: [AppBuild.termsInfoKey: "https://heyintentive.com/terms"],
        infoKey: AppBuild.termsInfoKey
      )?.absoluteString,
      "https://heyintentive.com/terms")
    XCTAssertNil(
      AppBuild.publicDestinationURL(
        infoDictionary: [AppBuild.termsInfoKey: "https://omi.me/terms"],
        infoKey: AppBuild.termsInfoKey))
    XCTAssertNil(
      AppBuild.publicDestinationURL(
        infoDictionary: [AppBuild.termsInfoKey: "https://example.com/terms"],
        infoKey: AppBuild.termsInfoKey))
  }

  func testSettingsExternalDestinationsExposeEveryStampedOwnedPublicLink() {
    let info: [String: Any] = [
      AppBuild.productWebsiteInfoKey: "https://heyintentive.com",
      AppBuild.termsInfoKey: "https://heyintentive.com/terms",
      AppBuild.privacyInfoKey: "https://heyintentive.com/privacy",
      AppBuild.supportInfoKey: "https://heyintentive.com/support",
    ]

    let destinations = AppBuild.settingsExternalDestinations(infoDictionary: info)

    XCTAssertEqual(
      destinations.map(\.title),
      ["Visit Website", "Privacy Policy", "Terms of Service", "Support"])
    XCTAssertEqual(
      destinations.map(\.url.absoluteString),
      [
        "https://heyintentive.com",
        "https://heyintentive.com/privacy",
        "https://heyintentive.com/terms",
        "https://heyintentive.com/support",
      ])
  }

  func testProductionLogPathsAreSeparatePerIdentity() {
    XCTAssertEqual(
      OmiLogPathResolver.logPath(
        bundleIdentifier: AppBuild.productionBundleIdentifier,
        processID: 1),
      "/tmp/heyintentive.log")
    XCTAssertEqual(
      OmiLogPathResolver.logPath(
        bundleIdentifier: AppBuild.betaProductionBundleIdentifier,
        processID: 1),
      "/tmp/heyintentive-beta.log")
  }
}
