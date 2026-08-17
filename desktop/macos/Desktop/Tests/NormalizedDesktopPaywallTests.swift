import XCTest

@testable import Omi_Computer

/// A verified paid entitlement clears a stale trial flag before audio admission.
@MainActor
final class NormalizedDesktopPaywallTests: XCTestCase {
  private let paywallKey = "desktop_isPaywalled"

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: paywallKey)
    super.tearDown()
  }

  func testActivePaidEntitlementClearsStickyPaywallBeforeAudioStartAdmission() {
    let state = AppState()
    state.isPaywalled = true
    XCTAssertTrue(state.blockIfPaywalled(), "setup: stale paywall blocks audio admission")

    let limiter = FloatingBarUsageLimiter()
    limiter.applyPlan(plan: .bounded, status: .active)

    XCTAssertFalse(state.isPaywalled)
    XCTAssertFalse(UserDefaults.standard.bool(forKey: paywallKey))
    XCTAssertFalse(state.blockIfPaywalled(), "active paid entitlement must pass the audio-start paywall guard")
  }
}
