import XCTest

@testable import Omi_Computer

final class DMGVolumeIdentityTests: XCTestCase {
  func testEjectionTargetsIntentiveAndGenericTransientVolumesOnly() {
    XCTAssertTrue(AppState.isIntentiveDMGVolumeName("Intentive"))
    XCTAssertTrue(AppState.isIntentiveDMGVolumeName("Intentive Beta"))
    XCTAssertTrue(AppState.isIntentiveDMGVolumeName("dmg.A1B2C3"))
    XCTAssertFalse(AppState.isIntentiveDMGVolumeName("Omi"))
    XCTAssertFalse(AppState.isIntentiveDMGVolumeName("Documents"))
  }
}
