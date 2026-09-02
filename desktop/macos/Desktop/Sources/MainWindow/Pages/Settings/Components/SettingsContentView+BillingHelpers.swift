import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum SubscriptionPlanPresentation {
  static let loadingDetail = "Fetching subscription details..."

  static func selectionLabel(planTitle: String, startingPrice: String?) -> String {
    guard let startingPrice, !startingPrice.isEmpty else {
      return "Select \(planTitle)"
    }
    return "Select \(planTitle) · \(startingPrice)"
  }
}

extension SettingsContentView {
  var hasPaidSubscription: Bool {
    guard let subscription = userSubscription?.subscription else { return false }
    return subscription.plan != .free && subscription.status == .active
  }

  var shouldShowPlanPurchaseOptions: Bool {
    userSubscription?.billingAvailability.checkoutEnabled == true
      && !hasPaidSubscription
      && !subscriptionPlansForDisplay.isEmpty
  }

  var subscriptionPlansForDisplay: [SubscriptionPlanOption] {
    (userSubscription?.availablePlans ?? [])
      .filter { !isCurrentSubscriptionPlan($0) }
      .sorted { $0.title < $1.title }
  }

  var currentPlanTitle: String {
    guard let subscription = userSubscription?.subscription else {
      return isLoadingSubscription ? "Loading plan..." : "Free"
    }
    return subscription.planName
  }

  var currentPlanSubtitle: String {
    if isLoadingSubscription {
      return SubscriptionPlanPresentation.loadingDetail
    }
    if let detail = currentPlanBillingDetail {
      return detail
    }
    if hasPaidSubscription {
      return "Your paid plan is active."
    }
    return "You are currently on the free tier."
  }

  var currentPlanBillingDetail: String? {
    guard hasPaidSubscription, let subscription = userSubscription?.subscription else {
      return nil
    }
    guard let price = subscription.priceString else { return nil }
    let interval = subscription.billingInterval.map { " · \($0.capitalized)" } ?? ""
    return "\(subscription.planName) · \(price)\(interval)"
  }

  var currentPlanPeriodText: String? {
    guard let subscription = userSubscription?.subscription else { return nil }
    guard hasPaidSubscription, let periodEnd = subscription.currentPeriodEnd else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(periodEnd))
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    let prefix = subscription.cancelAtNextBillingDate ? "Access ends" : "Renews"
    return "\(prefix) on \(formatter.string(from: date))"
  }

  func planAccentColor(for planId: String) -> Color {
    _ = planId
    return OmiColors.accent
  }

  func planSummaryText(for plan: SubscriptionPlanOption) -> String {
    preferredStartingPrice(for: plan)?.priceString ?? ""
  }

  func planSelectionLabel(for plan: SubscriptionPlanOption) -> String {
    SubscriptionPlanPresentation.selectionLabel(
      planTitle: plan.title,
      startingPrice: preferredStartingPrice(for: plan)?.priceString
    )
  }

  func preferredStartingPrice(for plan: SubscriptionPlanOption) -> SubscriptionPriceOption? {
    let prices = sortedPrices(for: plan)
    if let monthly = prices.first(where: { price in
      let title = price.title.lowercased()
      return title.contains("month")
    }) {
      return monthly
    }
    return prices.first
  }

  func sortedPrices(for plan: SubscriptionPlanOption) -> [SubscriptionPriceOption] {
    plan.prices.sorted { lhs, rhs in
      let lhsIsMonthly = lhs.title.lowercased().contains("month")
      let rhsIsMonthly = rhs.title.lowercased().contains("month")
      if lhsIsMonthly != rhsIsMonthly {
        return lhsIsMonthly && !rhsIsMonthly
      }
      return lhs.title < rhs.title
    }
  }

  func isCurrentSubscriptionPlan(_ plan: SubscriptionPlanOption) -> Bool {
    guard hasPaidSubscription, let subscription = userSubscription?.subscription else {
      return false
    }
    return plan.title == subscription.planName
  }

  @ViewBuilder
  func subscriptionPlanCard(_ plan: SubscriptionPlanOption) -> some View {
    let isSelected = selectedPlanIdForCheckout == plan.id
    let accent = planAccentColor(for: plan.id)
    let isCurrentPlan = isCurrentSubscriptionPlan(plan)
    let canPurchase = !isCurrentPlan && userSubscription?.billingAvailability.checkoutEnabled == true

    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      HStack(alignment: .top, spacing: OmiSpacing.md) {
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          Text((plan.eyebrow ?? "Plan").uppercased())
            .scaledFont(size: OmiType.micro, weight: .bold)
            .foregroundColor(accent)
            .tracking(0.8)

          Text(plan.title)
            .scaledFont(size: OmiType.heading, weight: .bold)
            .foregroundColor(OmiColors.textPrimary)

          if let subtitle = plan.subtitle {
            Text(subtitle)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
          }
        }

        Spacer()

        VStack(alignment: .trailing, spacing: OmiSpacing.hairline) {
          Text(planSummaryText(for: plan))
            .scaledFont(size: OmiType.subheading, weight: .bold)
            .foregroundColor(isSelected ? accent : OmiColors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

          Text("starting price")
            .scaledFont(size: OmiType.micro, weight: .medium)
            .foregroundColor(isSelected ? accent.opacity(0.8) : OmiColors.textTertiary)
        }
        .fixedSize(horizontal: true, vertical: false)
      }

      Text(plan.description ?? "")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textSecondary)

      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        ForEach(plan.features.prefix(4), id: \.self) { feature in
          HStack(spacing: OmiSpacing.sm) {
            ZStack {
              Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 18, height: 18)
              Image(systemName: "checkmark")
                .scaledFont(size: OmiType.micro, weight: .bold)
                .foregroundColor(accent)
            }
            Text(feature)
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(OmiColors.textSecondary)
          }
        }
      }

      if isSelected && canPurchase {
        Divider()
          .overlay(OmiColors.backgroundQuaternary)

        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          Text("Choose billing")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(OmiColors.textTertiary)

          HStack(spacing: OmiSpacing.sm) {
            ForEach(sortedPrices(for: plan)) { price in
              Button(action: {
                startCheckout(for: price.id)
              }) {
                Group {
                  if activeCheckoutOfferId == price.id {
                    ProgressView()
                      .controlSize(.small)
                      .frame(maxWidth: .infinity)
                  } else {
                    VStack(spacing: OmiSpacing.hairline) {
                      Text(price.title)
                        .scaledFont(size: OmiType.caption, weight: .bold)
                      Text(price.priceString)
                        .scaledFont(size: OmiType.caption)
                        .foregroundColor(OmiColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                  }
                }
              }
              .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
              .disabled(activeCheckoutOfferId != nil)
            }
          }
        }
      } else if isCurrentPlan {
        HStack {
          Text("Current Plan")
            .scaledFont(size: OmiType.caption, weight: .bold)
          Spacer()
          Image(systemName: "checkmark.circle.fill")
            .scaledFont(size: OmiType.caption)
        }
        .foregroundColor(accent)
        .padding(.vertical, OmiSpacing.sm)
      } else {
        Button(action: {
          selectedPlanIdForCheckout = plan.id
        }) {
          HStack {
            Text(planSelectionLabel(for: plan))
              .scaledFont(size: OmiType.caption, weight: .bold)
            Spacer()
            Image(systemName: "arrow.right")
              .scaledFont(size: OmiType.caption, weight: .bold)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
      }
    }
    .padding(OmiSpacing.xxl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.controlRadius)
        .fill(isSelected ? accent.opacity(0.12) : OmiColors.backgroundPrimary.opacity(0.68))
        .overlay(
          RoundedRectangle(cornerRadius: OmiChrome.controlRadius)
            .stroke(
              isSelected ? accent.opacity(0.85) : OmiColors.backgroundQuaternary,
              lineWidth: isSelected ? 1.5 : 1)
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: OmiChrome.controlRadius))
    .onTapGesture {
      guard canPurchase else { return }
      selectedPlanIdForCheckout = plan.id
    }
  }

  // MARK: - Language Helpers

  /// Whether the selected language supports auto-detect mode
  var autoDetectSupported: Bool {
    AssistantSettings.supportsAutoDetect(transcriptionLanguage)
  }

  /// Subtitle text for auto-detect toggle
  var autoDetectSubtitle: String {
    if autoDetectSupported {
      return "Automatically detect spoken language"
    } else {
      return "Not available for \(languageName(for: transcriptionLanguage))"
    }
  }

  /// Get display name for a language code
  func languageName(for code: String) -> String {
    AssistantSettings.supportedLanguages.first { $0.code == code }?.name ?? code
  }

  // MARK: - Slider Index Helpers

  var analysisDelaySliderIndex: Int {
    analysisDelayOptions.firstIndex(of: analysisDelay) ?? 0
  }

  var taskIntervalSliderIndex: Int {
    extractionIntervalOptions.firstIndex(of: taskExtractionInterval) ?? 0
  }

  var insightIntervalSliderIndex: Int {
    extractionIntervalOptions.firstIndex(of: insightExtractionInterval) ?? 0
  }

  var memoryIntervalSliderIndex: Int {
    extractionIntervalOptions.firstIndex(of: memoryExtractionInterval) ?? 0
  }

  // MARK: - Helpers

  func toggleMonitoring(enabled: Bool) {
    if enabled && !ProactiveAssistantsPlugin.shared.hasScreenRecordingPermission {
      permissionError = "Screen recording permission required"
      isMonitoring = false
      ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
      return
    }
    if enabled { OnboardingExitPersistence.recordExplicitCapabilityEnablement() }

    permissionError = nil
    isToggling = true

    // Track setting change
    AnalyticsManager.shared.settingToggled(setting: "monitoring", enabled: enabled)

    if enabled {
      ProactiveAssistantsPlugin.shared.startMonitoring { success, error in
        DispatchQueue.main.async {
          isToggling = false
          if !success {
            permissionError = error ?? "Failed to start monitoring"
            isMonitoring = false
          }
        }
      }
    } else {
      ProactiveAssistantsPlugin.shared.stopMonitoring()
      isToggling = false
    }

    // Persist the setting
    AssistantSettings.shared.screenAnalysisEnabled = enabled
  }

  func toggleTranscription(enabled: Bool) {
    // Check microphone permission
    if enabled && !appState.hasMicrophonePermission {
      transcriptionError = "Microphone permission required"
      isTranscribing = false
      return
    }
    if enabled { OnboardingExitPersistence.recordExplicitCapabilityEnablement() }

    transcriptionError = nil
    isTogglingTranscription = true

    // Track setting change
    AnalyticsManager.shared.settingToggled(setting: "transcription", enabled: enabled)

    if enabled {
      appState.startTranscription()
      isTogglingTranscription = false
      isTranscribing = true
    } else {
      appState.stopTranscription()
      isTogglingTranscription = false
      isTranscribing = false
    }

    // Persist the setting
    AssistantSettings.shared.transcriptionEnabled = enabled
  }

  func setSystemAudioCaptureMode(_ mode: AssistantSettings.SystemAudioCaptureMode) {
    AnalyticsManager.shared.settingToggled(
      setting: "system_audio_capture_mode_\(mode.rawValue)", enabled: mode != .never)
    // Persisting posts .systemAudioCaptureModeDidChange; AppState re-applies the gate live for
    // any in-progress recording.
    AssistantSettings.shared.systemAudioCaptureMode = mode
  }

  func startGlowPreview() {
    isPreviewRunning = true

    // Show the demo window and get its frame
    let demoWindow = GlowDemoWindow.show()
    let windowFrame = demoWindow.frame

    // Phase 1: Show focused (green) glow after a small delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      GlowDemoWindow.setPhase(.focused)
      OverlayService.shared.showGlow(around: windowFrame, colorMode: .focused, isPreview: true)
    }

    // Phase 2: Show distracted (red) glow
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
      GlowDemoWindow.setPhase(.distracted)
      OverlayService.shared.showGlow(around: windowFrame, colorMode: .distracted, isPreview: true)
    }

    // End preview and close demo window
    DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
      GlowDemoWindow.close()
      isPreviewRunning = false
    }
  }

  func deleteCurrentAIProfile() {
    guard let id = aiProfileId else { return }
    Task {
      let previous = await AIUserProfileService.shared.deleteProfile(id: id)
      await MainActor.run {
        if let previous {
          aiProfileId = previous.id
          aiProfileText = previous.profileText
          aiProfileGeneratedAt = previous.generatedAt
          aiProfileDataSourcesUsed = previous.dataSourcesUsed
        } else {
          aiProfileId = nil
          aiProfileText = nil
          aiProfileGeneratedAt = nil
          aiProfileDataSourcesUsed = 0
        }
      }
    }
  }

  func regenerateAIProfile() {
    isGeneratingAIProfile = true
    Task {
      do {
        let result = try await AIUserProfileService.shared.generateProfile()
        await MainActor.run {
          aiProfileId = result.id
          aiProfileText = result.profileText
          aiProfileGeneratedAt = result.generatedAt
          aiProfileDataSourcesUsed = result.dataSourcesUsed
          isGeneratingAIProfile = false
        }
      } catch {
        log("Settings: AI profile generation failed: \(error.localizedDescription)")
        await MainActor.run {
          isGeneratingAIProfile = false
        }
      }
    }
  }

  func formatMinutes(_ minutes: Int) -> String {
    if minutes == 1 {
      return "1 minute"
    } else if minutes < 60 {
      return "\(minutes) minutes"
    } else {
      return "1 hour"
    }
  }

  func formatAnalysisDelay(_ seconds: Int) -> String {
    if seconds == 0 {
      return "Instant"
    } else if seconds < 60 {
      return "\(seconds) seconds"
    } else if seconds == 60 {
      return "1 minute"
    } else {
      return "\(seconds / 60) minutes"
    }
  }

  func formatExtractionInterval(_ seconds: Double) -> String {
    if seconds < 60 {
      return "\(Int(seconds)) seconds"
    } else if seconds < 3600 {
      let minutes = Int(seconds / 60)
      return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    } else {
      let hours = Int(seconds / 3600)
      return hours == 1 ? "1 hour" : "\(hours) hours"
    }
  }

  func formatHour(_ hour: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:00 a"
    var components = DateComponents()
    components.hour = hour
    if let date = Calendar.current.date(from: components) {
      return formatter.string(from: date)
    }
    return "\(hour):00"
  }

  // MARK: - Local Settings

  func loadLocalSettings() {
    transcriptionLanguage = AssistantSettings.shared.transcriptionLanguage
    transcriptionAutoDetect = AssistantSettings.shared.transcriptionAutoDetect
    vocabularyList = AssistantSettings.shared.transcriptionVocabulary
    conversationLocationEnabled = AssistantSettings.shared.conversationLocationEnabled
    vadGateEnabled = AssistantSettings.shared.vadGateEnabled
    systemAudioCaptureMode = AssistantSettings.shared.systemAudioCaptureMode
    let notifications = LocalNotificationSettings().snapshot()
    notificationsEnabled = notifications.enabled
    notificationFrequency = notifications.frequency
  }

  func loadSubscriptionInfo() {
    guard !isLoadingSubscription else { return }
    isLoadingSubscription = true
    subscriptionError = nil
    refreshPlanUsageDetails()

    Task {
      do {
        let subscription = try await APIClient.shared.getUserSubscription()
        await MainActor.run {
          userSubscription = subscription
          appState.billingAvailability = subscription.billingAvailability
          subscriptionError = nil
          // Clear the sticky paywall flag whenever the subscription endpoint
          // reports a paid active plan. Catches the case where a paid user
          // hit the paywall once (e.g. WS connected before payment cleared
          // the trial cache) — without this they'd stay paywalled until the
          // next app restart even after their normalized entitlement is active.
          if subscription.subscription.plan != .free,
            subscription.subscription.status == .active,
            AppState.current?.isPaywalled == true
          {
            AppState.current?.isPaywalled = false
            log("Paywall: cleared sticky flag — subscription \(subscription.subscription.plan.rawValue) is active")
          }
          isLoadingSubscription = false
          viewModel.markBillingRefreshed()
        }
      } catch {
        logError("Failed to load subscription", error: error)
        await MainActor.run {
          subscriptionError = "Failed to load plan information."
          isLoadingSubscription = false
        }
      }
    }
  }

  func refreshPlanUsageDetails() {
    planUsageDetailsRequestID += 1
    let requestID = planUsageDetailsRequestID
    isLoadingChatUsage = true
    chatUsageQuota = nil

    Task {
      let quotaValue = await APIClient.shared.fetchChatUsageQuota()
      applyPlanUsageDetails(
        requestID: requestID,
        quota: quotaValue
      )
    }
  }

  @MainActor
  func applyPlanUsageDetails(
    requestID: Int,
    quota: APIClient.ChatUsageQuota?
  ) {
    guard requestID == planUsageDetailsRequestID else { return }
    chatUsageQuota = quota
    if let quota {
      FloatingBarUsageLimiter.shared.applyQuota(quota)
    }
    isLoadingChatUsage = false
  }

  func applySuccessfulSubscriptionRefresh(_ subscription: UserSubscriptionResponse) {
    userSubscription = subscription
    subscriptionError = nil
    pendingSubscriptionOfferId = nil
    selectedPlanIdForCheckout = nil

    FloatingBarUsageLimiter.shared.applyPlan(
      plan: subscription.subscription.plan,
      status: subscription.subscription.status
    )

    if subscription.subscription.plan != .free,
      subscription.subscription.status == .active,
      AppState.current?.isPaywalled == true
    {
      AppState.current?.isPaywalled = false
      log("Paywall: cleared sticky flag — subscription \(subscription.subscription.plan.rawValue) is active")
    }

    refreshPlanUsageDetails()
  }

  func startCheckout(for offerId: String) {
    guard activeCheckoutOfferId == nil else { return }
    guard userSubscription?.billingAvailability.checkoutEnabled == true else {
      subscriptionError = "Billing is not available in this build."
      return
    }
    guard !hasPaidSubscription else {
      openCustomerPortal()
      return
    }
    activeCheckoutOfferId = offerId
    pendingSubscriptionOfferId = offerId
    subscriptionError = nil

    Task {
      do {
        let response = try await APIClient.shared.createCheckoutSession(offerId: offerId)
        let apiBaseURL = await APIClient.shared.baseURL
        await MainActor.run {
          activeCheckoutOfferId = nil
        }

        let normalizedBaseURL = apiBaseURL.hasSuffix("/") ? apiBaseURL : apiBaseURL + "/"
        guard let checkoutURL = URL(string: response.url),
          let successURL = URL(string: normalizedBaseURL + "v1/payments/success"),
          let cancelURL = URL(string: normalizedBaseURL + "v1/payments/cancel")
        else {
          await MainActor.run {
            pendingSubscriptionOfferId = nil
            subscriptionError = "Could not start checkout."
          }
          return
        }
        await MainActor.run {
          activeBillingWebFlow = BillingWebFlow(
            title: "Complete Checkout",
            url: checkoutURL,
            successURL: successURL,
            cancelURL: cancelURL
          )
        }
      } catch let apiError as APIError {
        logError("Failed to create checkout session", error: apiError)
        await MainActor.run {
          activeCheckoutOfferId = nil
          pendingSubscriptionOfferId = nil
          subscriptionError = apiError.detail ?? "Failed to open checkout."
        }
      } catch {
        logError("Failed to create checkout session", error: error)
        await MainActor.run {
          activeCheckoutOfferId = nil
          pendingSubscriptionOfferId = nil
          subscriptionError = "Failed to open checkout."
        }
      }
    }
  }

  func openCustomerPortal() {
    guard !isOpeningCustomerPortal else { return }
    guard userSubscription?.billingAvailability.portalEnabled == true else {
      subscriptionError = "Billing management is not available in this build."
      return
    }
    isOpeningCustomerPortal = true
    subscriptionError = nil

    Task {
      do {
        let response = try await APIClient.shared.createCustomerPortalSession()
        await MainActor.run {
          isOpeningCustomerPortal = false
        }

        if let url = URL(string: response.url) {
          await MainActor.run {
            openURLInDefaultBrowser(url)
            subscriptionError = "Billing portal opened in your browser."
          }
        } else {
          await MainActor.run {
            subscriptionError = "Could not open billing portal."
          }
        }
      } catch {
        logError("Failed to open customer portal", error: error)
        await MainActor.run {
          isOpeningCustomerPortal = false
          subscriptionError = "Failed to open billing portal."
        }
      }
    }
  }

  func handleBillingFlowCompletion(_ outcome: BillingWebFlowOutcome) {
    switch outcome {
    case .completed:
      pollForUpdatedSubscription()
    case .cancelled, .dismissed:
      pendingSubscriptionOfferId = nil
      loadSubscriptionInfo()
    }
  }

  func pollForUpdatedSubscription() {
    let expectedOfferId = pendingSubscriptionOfferId

    Task {
      let outcome = await BillingReconciler.poll(
        read: { try await APIClient.shared.getUserSubscription() },
        matches: { subscription in
          let matchedOffer = expectedOfferId == nil || subscription.subscription.offerId == expectedOfferId
          return matchedOffer
            && subscription.subscription.plan != .free
            && subscription.subscription.status == .active
        },
        sleep: { try? await Task.sleep(nanoseconds: 1_000_000_000) }
      )
      await MainActor.run {
        switch outcome {
        case .matched(let subscription):
          applySuccessfulSubscriptionRefresh(subscription)
        case .timedOut(let subscription):
          if let subscription { userSubscription = subscription }
          subscriptionError =
            "Payment completed, but plan refresh is still catching up. Please try reloading this page in a moment."
          pendingSubscriptionOfferId = nil
        case .failed:
          subscriptionError = "Payment completed, but subscription refresh failed."
          pendingSubscriptionOfferId = nil
        }
      }
    }
  }

}
