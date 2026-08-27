import OmiSupport
import XCTest

final class DesktopLocalProfileTests: XCTestCase {
  func testNamedDevelopmentBundleUsesDedicatedStorageRoot() {
    XCTAssertEqual(
      DesktopStorageIdentity(
        bundleIdentifier: "com.heyintentive.intuitive.dev.memory-atlas-types",
        localProfileEnabled: false,
        localProfileStorageName: nil
      ).applicationSupportPathComponents,
      ["Intuitive Dev Bundles", "com.heyintentive.intuitive.dev.memory-atlas-types"]
    )
  }

  func testStableAndCanonicalDevelopmentUseTheirOwnedRoots() {
    let cases = [
      ("com.heyintentive.intuitive", ["Intuitive"]),
      ("com.heyintentive.intuitive.dev", ["Intuitive Dev"]),
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
        bundleIdentifier: "com.heyintentive.intuitive.dev.memory-atlas-types",
        localProfileEnabled: true,
        localProfileStorageName: "intuitive-local-test"
      ).applicationSupportPathComponents,
      ["Intuitive Dev Bundles", "com.heyintentive.intuitive.dev.memory-atlas-types"]
    )
  }
}
