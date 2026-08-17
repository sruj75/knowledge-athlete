import XCTest

@testable import Omi_Computer

final class BillingAvailabilityTests: XCTestCase {
  func testDisabledPresentationIsSkipAndOnlyDismisses() {
    let availability = BillingAvailability(
      checkoutEnabled: false,
      portalEnabled: false,
      presentation: .skip)
    var calls: [String] = []

    XCTAssertEqual(BillingPresentationPolicy.primaryLabel(for: availability), "Skip")
    BillingPresentationPolicy.performPrimaryAction(
      for: availability,
      onCheckout: { calls.append("checkout") },
      onDismiss: { calls.append("dismiss") })

    XCTAssertEqual(calls, ["dismiss"])
  }

  func testActivePresentationRoutesToHostedCheckout() {
    let availability = BillingAvailability(
      checkoutEnabled: true,
      portalEnabled: true,
      presentation: .checkout)
    var calls: [String] = []

    XCTAssertEqual(BillingPresentationPolicy.primaryLabel(for: availability), "Upgrade")
    BillingPresentationPolicy.performPrimaryAction(
      for: availability,
      onCheckout: { calls.append("checkout") },
      onDismiss: { calls.append("dismiss") })

    XCTAssertEqual(calls, ["checkout"])
  }
}
