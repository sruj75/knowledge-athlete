import OmiSupport
import XCTest

@testable import Omi_Computer

final class DesktopStorageIdentityTests: XCTestCase {
  func testNamedDevelopmentBundlesHaveDistinctIdentityDerivedRoots() {
    let first = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intentive.dev.memory-atlas",
      localProfileEnabled: false,
      localProfileStorageName: nil)
    let second = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intentive.dev.rewind-fix",
      localProfileEnabled: false,
      localProfileStorageName: nil)

    XCTAssertTrue(first.usesIsolatedStorage)
    XCTAssertTrue(second.usesIsolatedStorage)
    XCTAssertEqual(
      first.applicationSupportPathComponents,
      ["Intentive Dev Bundles", "com.heyintentive.intentive.dev.memory-atlas"])
    XCTAssertEqual(
      second.applicationSupportPathComponents,
      ["Intentive Dev Bundles", "com.heyintentive.intentive.dev.rewind-fix"])
    XCTAssertNotEqual(first.applicationSupportPathComponents, second.applicationSupportPathComponents)
  }

  func testCanonicalDevelopmentOwnsItsRootAndUnknownIdentityFailsClosed() {
    let dev = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intentive.dev",
      localProfileEnabled: false,
      localProfileStorageName: nil)
    let review = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intentive.review-build",
      localProfileEnabled: false,
      localProfileStorageName: nil)

    XCTAssertTrue(dev.usesIsolatedStorage)
    XCTAssertFalse(review.usesIsolatedStorage)
    XCTAssertEqual(dev.applicationSupportPathComponents, ["Intentive Dev"])
    XCTAssertNil(review.applicationSupportPathComponents)
  }

  func testNamedLocalProfileStillUsesTheBundleIDBoundary() {
    let identity = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intentive.dev.local-memory",
      localProfileEnabled: true,
      localProfileStorageName: "caller-controlled-name")

    XCTAssertEqual(
      identity.applicationSupportPathComponents,
      ["Intentive Dev Bundles", "com.heyintentive.intentive.dev.local-memory"])
  }

  func testInvalidNamedBundleIDCannotSelectAnIsolatedPath() {
    for bundleID in [
      "com.heyintentive.intentive.dev.",
      "com.heyintentive.intentive.dev.../escape",
      "com.heyintentive.intentive.dev.测试",
      "com.omi.omi-wave5-s28",
    ] {
      let identity = DesktopStorageIdentity(
        bundleIdentifier: bundleID,
        localProfileEnabled: false,
        localProfileStorageName: nil)

      XCTAssertFalse(identity.isNamedDevelopmentBundle, "Unexpected named bundle ID: \(bundleID)")
      XCTAssertNil(identity.applicationSupportPathComponents)
    }
  }

  func testBetaProductionIdentityOwnsAnIsolatedRoot() {
    let beta = DesktopStorageIdentity(
      bundleIdentifier: DesktopProductIdentity.betaBundleIdentifier,
      localProfileEnabled: false,
      localProfileStorageName: nil)

    XCTAssertTrue(beta.isBetaProductionBundle)
    XCTAssertTrue(beta.usesIsolatedStorage)
    XCTAssertEqual(beta.applicationSupportPathComponents, ["Intentive Beta"])
  }

  func testBetaProductionIdentityIgnoresHarnessLocalProfile() {
    // A shipped Omi Beta must never follow harness environment overrides into
    // another storage root.
    let beta = DesktopStorageIdentity(
      bundleIdentifier: DesktopProductIdentity.betaBundleIdentifier,
      localProfileEnabled: true,
      localProfileStorageName: "IntentiveHarness")

    XCTAssertEqual(beta.applicationSupportPathComponents, ["Intentive Beta"])
  }

  func testRuntimeManifestIsOwnerOnlyAndContainsNoCredentials() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("heyintentive-runtime-manifest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manifest = DesktopDevRuntimeManifest(
      bundleIdentifier: "com.heyintentive.intentive.dev.omi-manifest-test",
      processID: 42,
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      appPath: "/Applications/omi-manifest-test.app",
      profileRoot: root.path,
      logPath: "/private/tmp/heyintentive-dev-com.heyintentive.intentive.dev.omi-manifest-test-42.log",
      automationPort: 47777)
    try DesktopDevRuntimeManifestStore.write(manifest, in: root)

    let path = DesktopDevRuntimeManifestStore.path(in: root)
    XCTAssertEqual(path.lastPathComponent, ".heyintentive-dev-runtime.json")
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    let contents = try String(contentsOf: path, encoding: .utf8)
    XCTAssertFalse(contents.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(contents.localizedCaseInsensitiveContains("credential"))
    XCTAssertFalse(contents.localizedCaseInsensitiveContains("backend"))
  }
}
