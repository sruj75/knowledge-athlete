import OmiSupport
import XCTest

final class DesktopLocalProfileTests: XCTestCase {
  func testLocalProviderModeRequiresExplicitRealSelection() {
    XCTAssertEqual(DesktopLocalProviderMode(configuredValue: "real"), .real)
    for configuredValue in [nil, "", "offline", "typo", "REAL"] {
      XCTAssertEqual(DesktopLocalProviderMode(configuredValue: configuredValue), .offline)
    }
  }

  func testHermeticVoiceTransportRequiresBothLocalDataAndOfflineProviders() {
    XCTAssertTrue(DesktopLocalProviderMode.offline.usesHermeticTransport(localProfileEnabled: true))
    XCTAssertFalse(DesktopLocalProviderMode.real.usesHermeticTransport(localProfileEnabled: true))
    XCTAssertFalse(DesktopLocalProviderMode.offline.usesHermeticTransport(localProfileEnabled: false))
    XCTAssertFalse(DesktopLocalProviderMode.real.usesHermeticTransport(localProfileEnabled: false))
  }

  func testNamedDevelopmentBundleUsesDedicatedStorageRoot() {
    XCTAssertEqual(
      DesktopStorageIdentity(
        bundleIdentifier: "com.heyintentive.intentive.dev.memory-atlas-types",
        localProfileEnabled: false,
        localProfileStorageName: nil
      ).applicationSupportPathComponents,
      ["Intentive Dev Bundles", "com.heyintentive.intentive.dev.memory-atlas-types"]
    )
  }

  func testStableAndCanonicalDevelopmentUseTheirOwnedRoots() {
    let cases = [
      ("com.heyintentive.intentive", ["Intentive"]),
      ("com.heyintentive.intentive.dev", ["Intentive Dev"]),
    ]
    for (bundleIdentifier, expectedComponents) in cases {
      XCTAssertEqual(
        DesktopStorageIdentity(
          bundleIdentifier: bundleIdentifier,
          localProfileEnabled: false,
          localProfileStorageName: nil
        ).applicationSupportPathComponents,
        expectedComponents
      )
    }
  }

  func testNamedDevelopmentBundleTakesPrecedenceOverLocalProfileStorage() {
    XCTAssertEqual(
      DesktopStorageIdentity(
        bundleIdentifier: "com.heyintentive.intentive.dev.memory-atlas-types",
        localProfileEnabled: true,
        localProfileStorageName: "heyintentive-local-test"
      ).applicationSupportPathComponents,
      ["Intentive Dev Bundles", "com.heyintentive.intentive.dev.memory-atlas-types"]
    )
  }

  func testUnknownAndInheritedOmiBundlesCannotResolveWritableStorage() {
    for bundleIdentifier in [nil, "com.omi.desktop", "com.omi.computer-macos"] {
      XCTAssertNil(
        DesktopStorageIdentity(
          bundleIdentifier: bundleIdentifier,
          localProfileEnabled: false,
          localProfileStorageName: nil
        ).applicationSupportPathComponents,
        bundleIdentifier ?? "nil"
      )
    }
  }
}
