import OmiSupport
import XCTest

final class DesktopProductIdentityTests: XCTestCase {
  func testApprovedBundleFamilyResolvesExactCapabilitiesAndNamespaces() throws {
    let cases: [(String, DesktopProductIdentity.Family, [String], String, Bool, Bool, Bool)] = [
      (
        "com.heyintentive.intuitive",
        .stable,
        ["Intuitive"],
        "intuitive",
        false,
        true,
        true
      ),
      (
        "com.heyintentive.intuitive.beta",
        .beta,
        ["Intuitive Beta"],
        "intuitive-beta",
        false,
        true,
        true
      ),
      (
        "com.heyintentive.intuitive.dev",
        .canonicalDevelopment,
        ["Intuitive Dev"],
        "intuitive-dev",
        true,
        true,
        false
      ),
      (
        "com.heyintentive.intuitive.dev.omi-wave5-s28",
        .namedDevelopment("omi-wave5-s28"),
        ["Intuitive Dev Bundles", "com.heyintentive.intuitive.dev.omi-wave5-s28"],
        "intuitive-omi-wave5-s28",
        true,
        false,
        false
      ),
      (
        "com.heyintentive.intuitive.preview.p8b1f42a9",
        .preview("p8b1f42a9"),
        ["Intuitive Preview Builds", "com.heyintentive.intuitive.preview.p8b1f42a9"],
        "intuitive-preview-p8b1f42a9",
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
    XCTAssertEqual(DesktopProductIdentity.productSlug, "intuitive")
    XCTAssertEqual(DesktopProductIdentity.applicationFilename, "Intuitive.app")
    XCTAssertEqual(DesktopProductIdentity.databaseFilename, "intuitive.db")
    XCTAssertEqual(DesktopProductIdentity.agentRuntimeDatabaseFilename, "intuitive-agent.sqlite3")
    XCTAssertEqual(DesktopProductIdentity.logPrefix, "intuitive")
    XCTAssertEqual(DesktopProductIdentity.lockPrefix, "intuitive")
    XCTAssertEqual(DesktopProductIdentity.automationTokenPrefix, "intuitive-automation")
    XCTAssertEqual(DesktopProductIdentity.archiveCacheRootName, "IntuitiveDesktop")
    XCTAssertEqual(DesktopProductIdentity.runtimeManifestFilename, ".intuitive-dev-runtime.json")
    XCTAssertEqual(DesktopProductIdentity.agentStateEnvironmentVariable, "INTUITIVE_AGENT_STATE_DIR")
    XCTAssertEqual(DesktopProductIdentity.installerSkipEnvironmentVariable, "INTUITIVE_SKIP_INSTALL_GATE")
    XCTAssertEqual(
      DesktopProductIdentity.authKeychainServiceBase,
      "com.heyintentive.intuitive.firebase-rest-session"
    )
    XCTAssertEqual(
      DesktopProductIdentity.clientDeviceKeychainServiceBase,
      "com.heyintentive.intuitive.client-device-id"
    )
  }

  func testUnknownMalformedAndOmiBundleIdentifiersFailClosed() {
    for bundleID in [
      nil,
      "",
      "com.heyintentive.intuitive.dev.",
      "com.heyintentive.intuitive.dev.../escape",
      "com.heyintentive.intuitive.dev.测试",
      "com.heyintentive.intuitive.preview.",
      "com.heyintentive.intuitive.preview.bad.value",
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
    XCTAssertEqual(DesktopProductIdentity.stableBundleIdentifier, "com.heyintentive.intuitive")
    XCTAssertEqual(DesktopProductIdentity.betaBundleIdentifier, "com.heyintentive.intuitive.beta")
    XCTAssertEqual(
      DesktopProductIdentity.canonicalDevelopmentBundleIdentifier,
      "com.heyintentive.intuitive.dev"
    )
    XCTAssertEqual(
      DesktopProductIdentity.namedDevelopmentBundlePrefix,
      "com.heyintentive.intuitive.dev."
    )
    XCTAssertEqual(
      DesktopProductIdentity.previewBundlePrefix,
      "com.heyintentive.intuitive.preview."
    )
  }
}
