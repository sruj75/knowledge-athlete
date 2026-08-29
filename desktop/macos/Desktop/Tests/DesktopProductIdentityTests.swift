import OmiSupport
import XCTest

final class DesktopProductIdentityTests: XCTestCase {
  func testApprovedBundleFamilyResolvesExactCapabilitiesAndNamespaces() throws {
    let cases: [(String, DesktopProductIdentity.Family, [String], String, Bool, Bool, Bool)] = [
      (
        "com.heyintentive.intentive",
        .stable,
        ["Intentive"],
        "heyintentive",
        false,
        true,
        true
      ),
      (
        "com.heyintentive.intentive.beta",
        .beta,
        ["Intentive Beta"],
        "heyintentive-beta",
        false,
        true,
        true
      ),
      (
        "com.heyintentive.intentive.dev",
        .canonicalDevelopment,
        ["Intentive Dev"],
        "heyintentive-dev",
        true,
        true,
        false
      ),
      (
        "com.heyintentive.intentive.dev.omi-wave5-s28",
        .namedDevelopment("omi-wave5-s28"),
        ["Intentive Dev Bundles", "com.heyintentive.intentive.dev.omi-wave5-s28"],
        "heyintentive-omi-wave5-s28",
        true,
        false,
        false
      ),
      (
        "com.heyintentive.intentive.preview.p8b1f42a9",
        .preview("p8b1f42a9"),
        ["Intentive Preview Builds", "com.heyintentive.intentive.preview.p8b1f42a9"],
        "heyintentive-preview-p8b1f42a9",
        false,
        false,
        false
      ),
    ]

    for (bundleID, family, path, scheme, allowsAutomation, allowsSparkle, allowsLoginItem) in cases {
      let identity = try XCTUnwrap(DesktopProductIdentity(bundleIdentifier: bundleID))
      XCTAssertEqual(identity.family, family, bundleID)
      XCTAssertEqual(identity.applicationSupportPathComponents, path, bundleID)
      XCTAssertEqual(identity.cachePathComponents, path, bundleID)
      XCTAssertEqual(identity.urlScheme, scheme, bundleID)
      XCTAssertEqual(identity.allowsLocalAutomation, allowsAutomation, bundleID)
      XCTAssertEqual(identity.allowsSparkleUpdates, allowsSparkle, bundleID)
      XCTAssertEqual(identity.allowsLoginItem, allowsLoginItem, bundleID)
      XCTAssertNil(identity.appGroupIdentifier, bundleID)
    }
  }

  func testExactTechnicalComponentsAreOwnedAndDisplayIndependent() {
    XCTAssertEqual(DesktopProductIdentity.reverseDNSOwner, "com.heyintentive")
    XCTAssertEqual(DesktopProductIdentity.productSlug, "heyintentive")
    XCTAssertEqual(DesktopProductIdentity.applicationFilename, "Intentive.app")
    XCTAssertEqual(DesktopProductIdentity.databaseFilename, "heyintentive.db")
    XCTAssertEqual(DesktopProductIdentity.runningFlagFilename, ".heyintentive_running")
    XCTAssertEqual(DesktopProductIdentity.agentRuntimeDatabaseFilename, "heyintentive-agent.sqlite3")
    XCTAssertEqual(DesktopProductIdentity.logPrefix, "heyintentive")
    XCTAssertEqual(DesktopProductIdentity.lockPrefix, "heyintentive")
    XCTAssertEqual(DesktopProductIdentity.automationTokenPrefix, "heyintentive-automation")
    XCTAssertEqual(DesktopProductIdentity.archiveCacheRootName, "heyintentive-desktop")
    XCTAssertEqual(DesktopProductIdentity.runtimeManifestFilename, ".heyintentive-dev-runtime.json")
    XCTAssertEqual(DesktopProductIdentity.agentStateEnvironmentVariable, "HEYINTENTIVE_AGENT_STATE_DIR")
    XCTAssertEqual(
      DesktopProductIdentity.agentArtifactsEnvironmentVariable,
      "HEYINTENTIVE_AGENT_ARTIFACTS_DIR")
    XCTAssertEqual(DesktopProductIdentity.installerSkipEnvironmentVariable, "HEYINTENTIVE_SKIP_INSTALL_GATE")
    XCTAssertEqual(
      DesktopProductIdentity.authKeychainServiceBase,
      "com.heyintentive.intentive.firebase-rest-session"
    )
    XCTAssertEqual(
      DesktopProductIdentity.clientDeviceKeychainServiceBase,
      "com.heyintentive.intentive.client-device-id"
    )
  }

  func testUnknownMalformedAndOmiBundleIdentifiersFailClosed() {
    for bundleID in [
      nil,
      "",
      "com.heyintentive.intentive.dev.",
      "com.heyintentive.intentive.dev.../escape",
      "com.heyintentive.intentive.dev.测试",
      "com.heyintentive.intentive.preview.",
      "com.heyintentive.intentive.preview.bad.value",
      "com.heyintentive.other",
      "com.omi.computer-macos",
      "com.omi.computer-macos.beta",
      "com.omi.desktop-dev",
      "com.omi.omi-wave5-s28",
    ] as [String?] {
      XCTAssertNil(DesktopProductIdentity(bundleIdentifier: bundleID), bundleID ?? "nil")
    }
  }

  func testStableBetaAndCanonicalDevelopmentConstantsStayExact() {
    XCTAssertEqual(DesktopProductIdentity.stableBundleIdentifier, "com.heyintentive.intentive")
    XCTAssertEqual(DesktopProductIdentity.betaBundleIdentifier, "com.heyintentive.intentive.beta")
    XCTAssertEqual(
      DesktopProductIdentity.canonicalDevelopmentBundleIdentifier,
      "com.heyintentive.intentive.dev"
    )
    XCTAssertEqual(
      DesktopProductIdentity.namedDevelopmentBundlePrefix,
      "com.heyintentive.intentive.dev."
    )
    XCTAssertEqual(
      DesktopProductIdentity.previewBundlePrefix,
      "com.heyintentive.intentive.preview."
    )
  }
}
