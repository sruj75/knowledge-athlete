import Foundation

extension DesktopAutomationActionRegistry {
  func registerBillingActions() {
    register(
      name: "subscription_snapshot",
      summary: "Return cached subscription/plan info from the billing API"
    ) { _ in
      let response = try await APIClient.shared.getUserSubscription()
      return desktopAutomationBillingSnapshot(response)
    }

    register(
      name: "show_usage_limit_popup",
      summary: "Present the real usage-limit popup through AppState. Non-prod only.",
      params: ["reason"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "show_usage_limit_popup is disabled on production bundles"]
      }
      return await MainActor.run {
        guard let appState = AppState.current else {
          return ["error": "app state unavailable"]
        }
        appState.triggerUsageLimitPopup(reason: params["reason"] ?? "chat")
        return [
          "popup_visible": appState.showUsageLimitPopup ? "true" : "false",
          "primary_action": BillingPresentationPolicy.primaryLabel(for: appState.billingAvailability),
        ]
      }
    }

    register(
      name: "select_usage_limit_primary_action",
      summary: "Select the real usage-limit primary policy action and report state preservation. Non-prod only."
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "select_usage_limit_primary_action is disabled on production bundles"]
      }
      return await MainActor.run {
        guard let appState = AppState.current else {
          return ["error": "app state unavailable"]
        }
        let availability = appState.billingAvailability
        let paywall = appState.isPaywalled
        let limiter = FloatingBarUsageLimiter.shared
        let remainingQueries = limiter.remainingQueries
        let limitReached = limiter.isLimitReached
        let wasVisible = appState.showUsageLimitPopup
        var checkoutInvoked = false
        BillingPresentationPolicy.performPrimaryAction(
          for: availability,
          onCheckout: { checkoutInvoked = true },
          onDismiss: { appState.dismissUsageLimitPopup() })
        return [
          "popup_was_visible": wasVisible ? "true" : "false",
          "popup_visible": appState.showUsageLimitPopup ? "true" : "false",
          "primary_action": BillingPresentationPolicy.primaryLabel(for: availability),
          "checkout_invoked": checkoutInvoked ? "true" : "false",
          "billing_availability_unchanged": appState.billingAvailability == availability ? "true" : "false",
          "paywall_unchanged": appState.isPaywalled == paywall ? "true" : "false",
          "quota_unchanged":
            limiter.remainingQueries == remainingQueries && limiter.isLimitReached == limitReached ? "true" : "false",
        ]
      }
    }

    register(
      name: "billing_reconciliation_probe",
      summary: "Exercise the production billing reconciliation read budget without provider I/O. Non-prod only."
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "billing_reconciliation_probe is disabled on production bundles"]
      }
      var reads = 0
      var sleeps = 0
      let outcome = await BillingReconciler.poll(
        read: {
          reads += 1
          return reads
        },
        matches: { $0 == BillingReconciler.maximumReads },
        sleep: { sleeps += 1 })
      let outcomeName: String
      switch outcome {
      case .matched: outcomeName = "matched"
      case .timedOut: outcomeName = "timed_out"
      case .failed: outcomeName = "failed"
      }
      return [
        "outcome": outcomeName,
        "reads": "\(reads)",
        "sleeps": "\(sleeps)",
      ]
    }

    register(
      name: "billing_web_completion_policy_probe",
      summary: "Exercise exact hosted-billing completion URL matching without loading a web page. Non-prod only."
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "billing_web_completion_policy_probe is disabled on production bundles"]
      }
      guard let success = URL(string: "https://billing.invalid/v1/payments/success"),
        let cancel = URL(string: "https://billing.invalid/v1/payments/cancel"),
        let forgedQuery = URL(string: "https://billing.invalid/v1/payments/success?forged=1"),
        let foreignHost = URL(string: "https://attacker.invalid/v1/payments/success")
      else {
        return ["error": "billing completion probe URLs are invalid"]
      }
      return [
        "success_matches": BillingWebView.Coordinator.urlsMatchCompletion(success, completionURL: success)
          ? "true" : "false",
        "cancel_matches": BillingWebView.Coordinator.urlsMatchCompletion(cancel, completionURL: cancel)
          ? "true" : "false",
        "forged_query_matches": BillingWebView.Coordinator.urlsMatchCompletion(forgedQuery, completionURL: success)
          ? "true" : "false",
        "foreign_host_matches": BillingWebView.Coordinator.urlsMatchCompletion(foreignHost, completionURL: success)
          ? "true" : "false",
      ]
    }
  }
}
