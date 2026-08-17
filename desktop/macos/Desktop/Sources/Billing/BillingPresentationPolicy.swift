import Foundation

enum BillingPresentationPolicy {
  static func primaryLabel(for availability: BillingAvailability) -> String {
    availability.checkoutEnabled && availability.presentation == .checkout ? "Upgrade" : "Skip"
  }

  static func performPrimaryAction(
    for availability: BillingAvailability,
    onCheckout: () -> Void,
    onDismiss: () -> Void
  ) {
    if availability.checkoutEnabled && availability.presentation == .checkout {
      onCheckout()
    } else {
      onDismiss()
    }
  }
}
