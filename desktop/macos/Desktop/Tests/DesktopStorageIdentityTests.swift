import OmiSupport
import XCTest

@testable import Omi_Computer

final class DesktopStorageIdentityTests: XCTestCase {
  func testNamedDevelopmentBundlesHaveDistinctIdentityDerivedRoots() {
    let first = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intuitive.dev.memory-atlas",
      localProfileEnabled: false,
      localProfileStorageName: nil)
    let second = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intuitive.dev.rewind-fix",
      localProfileEnabled: false,
      localProfileStorageName: nil)

    XCTAssertTrue(first.usesIsolatedStorage)
    XCTAssertTrue(second.usesIsolatedStorage)
    XCTAssertEqual(
      first.applicationSupportPathComponents,
      ["Intuitive Dev Bundles", "com.heyintentive.intuitive.dev.memory-atlas"])
    XCTAssertEqual(
      second.applicationSupportPathComponents,
      ["Intuitive Dev Bundles", "com.heyintentive.intuitive.dev.rewind-fix"])
    XCTAssertNotEqual(first.applicationSupportPathComponents, second.applicationSupportPathComponents)
  }

  func testCanonicalDevelopmentOwnsItsRootAndUnknownIdentityFailsClosed() {
    let dev = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intuitive.dev",
      localProfileEnabled: false,
      localProfileStorageName: nil)
    let review = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intuitive.review-build",
      localProfileEnabled: false,
      localProfileStorageName: nil)

    XCTAssertTrue(dev.usesIsolatedStorage)
    XCTAssertFalse(review.usesIsolatedStorage)
    XCTAssertEqual(dev.applicationSupportPathComponents, ["Intuitive Dev"])
    XCTAssertNil(review.applicationSupportPathComponents)
  }

  func testNamedLocalProfileStillUsesTheBundleIDBoundary() {
    let identity = DesktopStorageIdentity(
      bundleIdentifier: "com.heyintentive.intuitive.dev.local-memory",
      localProfileEnabled: true,
      localProfileStorageName: "caller-controlled-name")

    XCTAssertEqual(
      identity.applicationSupportPathComponents,
      ["Intuitive Dev Bundles", "com.heyintentive.intuitive.dev.local-memory"])
  }

  func testInvalidNamedBundleIDCannotSelectAnIsolatedPath() {
    for bundleID in [
      "com.heyintentive.intuitive.dev.",
      "com.heyintentive.intuitive.dev.../escape",
      "com.heyintentive.intuitive.dev.测试",
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
    XCTAssertEqual(beta.applicationSupportPathComponents, ["Intuitive Beta"])
  }

  func testBetaProductionIdentityIgnoresHarnessLocalProfile() {
    // A shipped Omi Beta must never follow harness environment overrides into
    // another storage root.
    let beta = DesktopStorageIdentity(
      bundleIdentifier: DesktopProductIdentity.betaBundleIdentifier,
      localProfileEnabled: true,
      localProfileStorageName: "IntuitiveHarness")

    XCTAssertEqual(beta.applicationSupportPathComponents, ["Intuitive Beta"])
  }

  func testRuntimeManifestIsOwnerOnlyAndContainsNoCredentials() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("omi-runtime-manifest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manifest = DesktopDevRuntimeManifest(
      bundleIdentifier: "com.omi.omi-manifest-test",
      processID: 42,
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      appPath: "/Applications/omi-manifest-test.app",
      profileRoot: root.path,
      logPath: "/private/tmp/omi-dev-com.omi.omi-manifest-test-42.log",
      automationPort: 47777)
    try DesktopDevRuntimeManifestStore.write(manifest, in: root)

    let path = DesktopDevRuntimeManifestStore.path(in: root)
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    let contents = try String(contentsOf: path, encoding: .utf8)
    XCTAssertFalse(contents.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(contents.localizedCaseInsensitiveContains("credential"))
    XCTAssertFalse(contents.localizedCaseInsensitiveContains("backend"))
  }
}
