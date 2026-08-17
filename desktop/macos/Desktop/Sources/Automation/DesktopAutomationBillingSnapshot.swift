func desktopAutomationBillingSnapshot(_ response: UserSubscriptionResponse) -> [String: String] {
  let subscription = response.subscription
  return [
    "plan": subscription.plan.rawValue,
    "status": subscription.status.rawValue,
    "billing_presentation": response.billingAvailability.presentation.rawValue,
    "checkout_enabled": response.billingAvailability.checkoutEnabled ? "true" : "false",
    "portal_enabled": response.billingAvailability.portalEnabled ? "true" : "false",
    "primary_action": BillingPresentationPolicy.primaryLabel(for: response.billingAvailability),
    "show_subscription_ui": response.showSubscriptionUI ? "true" : "false",
    "transcription_seconds_used": "\(response.transcriptionSecondsUsed)",
    "transcription_seconds_limit": "\(response.transcriptionSecondsLimit)",
  ]
}
