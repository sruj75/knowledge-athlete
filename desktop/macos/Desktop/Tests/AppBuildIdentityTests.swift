import Foundation
import XCTest

@testable import Omi_Computer

final class AppBuildIdentityTests: XCTestCase {
  func testShippingInfoPlistUsesTheApprovedIntentiveIdentity() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let plistURL = testsDirectory.deletingLastPathComponent().appendingPathComponent("Info.plist")
    let data = try Data(contentsOf: plistURL)
    let value = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

    XCTAssertEqual(value["CFBundleDisplayName"] as? String, "Intentive")
    XCTAssertEqual(value["CFBundleIconFile"] as? String, "IntentiveIcon")
    for key in [
      "NSScreenCaptureUsageDescription",
      "NSMicrophoneUsageDescription",
      "NSLocationUsageDescription",
      "NSAudioCaptureUsageDescription",
    ] {
      let description = try XCTUnwrap(value[key] as? String, key)
      XCTAssertTrue(description.hasPrefix("Intentive "), "\(key): \(description)")
      XCTAssertFalse(description.localizedCaseInsensitiveContains("Omi"), "\(key): \(description)")
    }
  }
}
