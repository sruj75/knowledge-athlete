import XCTest

@testable import Omi_Computer

final class LaunchAtLoginBundlePolicyTests: XCTestCase {
  func testOnlyOwnedProductionFamiliesMayRegisterLoginItem() {
    XCTAssertTrue(
      LaunchAtLoginBundlePolicy.allowsRegistration(
        bundleIdentifier: "com.heyintentive.intentive"))
    XCTAssertTrue(
      LaunchAtLoginBundlePolicy.allowsRegistration(
        bundleIdentifier: "com.heyintentive.intentive.beta"))

    for bundleIdentifier in [
      "com.heyintentive.intentive.dev",
      "com.heyintentive.intentive.dev.omi-wave5-s28",
      "com.heyintentive.intentive.preview.review",
      "com.omi.computer-macos",
      "com.omi.computer-macos.beta",
      "org.example.app",
    ] {
      XCTAssertFalse(
        LaunchAtLoginBundlePolicy.allowsRegistration(bundleIdentifier: bundleIdentifier),
        "unexpected login-item authority for \(bundleIdentifier)")
    }
    XCTAssertFalse(LaunchAtLoginBundlePolicy.allowsRegistration(bundleIdentifier: nil))
  }
}
