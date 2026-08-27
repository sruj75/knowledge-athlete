import OmiSupport
import XCTest

final class DesktopLocalProfileTests: XCTestCase {
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
}
