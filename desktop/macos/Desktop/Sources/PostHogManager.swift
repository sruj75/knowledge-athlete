import FirebaseAuth
import FirebaseCore
import Foundation
import PostHog

struct ProductAnalyticsConfiguration: Equatable {
  let projectToken: String
  let host: URL

  static func resolve(
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> ProductAnalyticsConfiguration? {
    let token =
      nonempty(environment["POSTHOG_PROJECT_API_KEY"])
      ?? nonempty(infoDictionary["IntentivePostHogProjectToken"] as? String)
    let hostValue =
      nonempty(environment["POSTHOG_HOST"])
      ?? nonempty(infoDictionary["IntentivePostHogHost"] as? String)

    guard let token, let hostValue, let host = URL(string: hostValue),
      host.scheme?.lowercased() == "https", host.host?.isEmpty == false,
      host.user == nil, host.password == nil, host.query == nil, host.fragment == nil
    else { return nil }

    return ProductAnalyticsConfiguration(projectToken: token, host: host)
  }

  private static func nonempty(_ value: String?) -> String? {
    let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }
}

/// Singleton manager for optional PostHog product analytics.
@MainActor
class PostHogManager {
  static let shared = PostHogManager()

  private var isInitialized = false

  private init() {}

  // MARK: - Initialization

  /// Initialize PostHog with analytics
  @discardableResult
  func initialize() -> Bool {
    guard !isInitialized else { return true }
    guard let analyticsConfiguration = ProductAnalyticsConfiguration.resolve() else {
      log("PostHog: Disabled because owned project configuration is unavailable")
      return false
    }

    let config = PostHogConfig(
      projectToken: analyticsConfiguration.projectToken,
      host: analyticsConfiguration.host.absoluteString)

    // Disable automatic lifecycle events — PostHog's observer calls setResourceValues(isExcludedFromBackupKey:)
    // synchronously on the main thread (via NSApplicationDidFinishLaunchingNotification), which XPCs to the
    // mds (Spotlight) daemon and can hang for 2000ms+ when the daemon is slow. We track the meaningful
    // lifecycle event (App Launched / First Launch) manually via AnalyticsManager.shared.
    config.captureApplicationLifecycleEvents = false
    config.captureScreenViews = true
    config.preloadFeatureFlags = true

    PostHogSDK.shared.setup(config)

    // Release-identity super-properties (#10425): every captured event carries the
    // app version + build + release channel so it can be sliced by release cohort
    // without per-event plumbing. These persist across sessions.
    PostHogSDK.shared.register([
      "platform": "macos",
      "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
      "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      "update_channel": AppBuild.currentUpdateChannel,
    ])

    isInitialized = true
    log("PostHog: Initialized successfully")
    return true
  }

  // MARK: - User Identification

  /// Identify the current user after sign-in
  func identify() {
    guard isInitialized else { return }

    var userId: String?
    var email: String?
    var name: String?

    // Try Firebase Auth first, but only after Firebase has been configured.
    if FirebaseApp.app() != nil, let user = Auth.auth().currentUser {
      userId = user.uid
      email = user.email
      name = user.displayName
    } else if AuthState.shared.isSignedIn, let storedUserId = AuthState.shared.userId {
      // Fall back to stored auth state (when Firebase SDK auth failed but REST API auth succeeded)
      userId = storedUserId
      email = AuthState.shared.userEmail
      name = AuthService.shared.displayName.isEmpty ? nil : AuthService.shared.displayName
      log("PostHog: Using stored auth state (Firebase SDK auth not available)")
    }

    guard let uid = userId else {
      log("PostHog: Cannot identify - no user signed in")
      return
    }

    var properties: [String: Any] = [
      "platform": "macos",
      "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
      "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      "update_channel": AppBuild.currentUpdateChannel,
    ]

    if let email = email {
      properties["email"] = email
    }

    if let name = name {
      properties["name"] = name
    }

    PostHogSDK.shared.identify(uid, userProperties: properties)
    log("PostHog: Identified user \(uid)")
  }

  /// Set person properties in one identify call.
  func setUserProperties(_ properties: [String: Any]) {
    guard isInitialized else { return }
    PostHogSDK.shared.identify(PostHogSDK.shared.getDistinctId(), userProperties: properties)
  }

  // MARK: - Event Tracking

  /// Track an event with optional properties
  func track(_ eventName: String, properties: [String: Any]? = nil) {
    guard isInitialized else { return }
    PostHogSDK.shared.capture(eventName, properties: properties)
    log("PostHog: Tracked event '\(eventName)'")
  }

  nonisolated static func diagnosticErrorClass(_ value: String) -> String {
    let normalized = value.lowercased()
    if normalized.contains("timeout") || normalized.contains("timed out") {
      return "timeout"
    }
    if normalized.contains("cancel") || normalized.contains("stopped") {
      return "cancelled"
    }
    if normalized.contains("429") || normalized.contains("rate limit")
      || normalized.contains("quota")
    {
      return "rate_limit"
    }
    if normalized.contains("403") || normalized.contains("forbidden")
      || normalized.contains("permission") || normalized.contains("denied")
    {
      return "permission"
    }
    if normalized.contains("401") || normalized.contains("unauthorized")
      || normalized.contains("auth") || normalized.contains("sign in")
    {
      return "authentication"
    }
    if normalized.contains("offline") || normalized.contains("network")
      || normalized.contains("connection") || normalized.contains("socket")
    {
      return "network"
    }
    if normalized.contains("409") || normalized.contains("conflict")
      || normalized.contains("aborted")
    {
      return "conflict"
    }
    if normalized.contains("decode") || normalized.contains("encoding")
      || normalized.contains("invalid json") || normalized.contains("invalid response")
    {
      return "invalid_response"
    }
    if normalized.contains("memory") && normalized.contains("available") {
      return "resource_exhausted"
    }
    return "unknown"
  }

  // MARK: - Screen Tracking

  /// Track a screen view
  func screen(_ screenName: String, properties: [String: Any]? = nil) {
    guard isInitialized else { return }
    PostHogSDK.shared.screen(screenName, properties: properties)
  }

  // MARK: - Opt In/Out

  /// Opt in to tracking
  func optIn() {
    guard isInitialized else { return }
    PostHogSDK.shared.optIn()
  }

  /// Opt out of tracking
  func optOut() {
    guard isInitialized else { return }
    PostHogSDK.shared.optOut()
  }

  // MARK: - Reset

  /// Reset the user (call on sign out)
  func reset() {
    guard isInitialized else { return }
    PostHogSDK.shared.reset()
    log("PostHog: Reset user")
  }

  // MARK: - Feature Flags

  /// Check if a feature flag is enabled
  func isFeatureEnabled(_ flag: String) -> Bool {
    guard isInitialized else { return false }
    return PostHogSDK.shared.isFeatureEnabled(flag)
  }

  /// Get feature flag value
  func getFeatureFlag(_ flag: String) -> Any? {
    guard isInitialized else { return nil }
    return PostHogSDK.shared.getFeatureFlag(flag)
  }

  /// Reload feature flags
  func reloadFeatureFlags() {
    guard isInitialized else { return }
    PostHogSDK.shared.reloadFeatureFlags()
  }
}

extension PostHogManager: ProductAnalyticsConsentAdapter {
  func start() -> Bool {
    initialize()
  }

  func resume() {
    optIn()
  }

  func resetIdentity() {
    reset()
  }

  func stopSharing() {
    optOut()
  }
}

// MARK: - Analytics Events

extension PostHogManager {

  // MARK: - Onboarding Events

  // MARK: - Authentication Events

  func signInStarted(provider: String) {
    track(
      "Sign In Started",
      properties: [
        "provider": provider
      ])
  }

  func signInCompleted(provider: String) {
    track(
      "Sign In Completed",
      properties: [
        "provider": provider
      ])
  }

  func signInFailed(provider: String, error: String, errorClass: String? = nil) {
    let errorClass =
      errorClass.map { String($0.prefix(80)) }
      ?? Self.diagnosticErrorClass(error)
    track(
      "Sign In Failed",
      properties: [
        "provider": provider,
        "error": errorClass,
        "error_class": errorClass,
      ])
  }

  func authFlowEvent(_ eventName: String, properties: [String: Any]) {
    track(eventName, properties: properties)
  }

  func signedOut() {
    track("Signed Out")
  }

  // MARK: - Monitoring Events

  func monitoringStarted() {
    track("Monitoring Started")
  }

  func monitoringStopped() {
    track("Monitoring Stopped")
  }

  func distractionDetected(app: String, windowTitle: String?) {
    track(
      "Distraction Detected",
      properties: [
        "app": app,
        "has_window_title": !(windowTitle?.isEmpty ?? true),
      ])
  }

  func focusRestored(app: String) {
    track(
      "Focus Restored",
      properties: [
        "app": app
      ])
  }

  // MARK: - Recording Events

  func transcriptionStarted() {
    track(
      "Desktop Recording Started",
      properties: [
        "platform": "macos"
      ])
  }

  func transcriptionStopped(wordCount: Int) {
    track(
      "Desktop Recording Stopped",
      properties: [
        "platform": "macos",
        "word_count": wordCount,
      ])
  }

  func recordingError(
    error: String,
    reason: String? = nil,
    source: String? = nil,
    stage: String? = nil,
    retryCount: Int? = nil
  ) {
    let errorClass = Self.diagnosticErrorClass(error)
    var properties: [String: Any] = [
      "platform": "macos",
      "error": errorClass,
      "error_class": errorClass,
    ]
    if let reason {
      properties["recording_error_reason"] = reason
    }
    if let source {
      properties["recording_source"] = source
    }
    if let stage {
      properties["recording_stage"] = stage
    }
    if let retryCount {
      properties["retry_count"] = retryCount
    }
    track("Desktop Recording Error", properties: properties)
  }

  // MARK: - Permission Events

  func permissionRequested(permission: String, extraProperties: [String: Any] = [:]) {
    var props: [String: Any] = ["permission": permission]
    for (key, value) in extraProperties {
      props[key] = value
    }
    track("Permission Requested", properties: props)
  }

  func permissionGranted(permission: String, extraProperties: [String: Any] = [:]) {
    var props: [String: Any] = ["permission": permission]
    for (key, value) in extraProperties {
      props[key] = value
    }
    track("Permission Granted", properties: props)
  }

  func permissionDenied(permission: String, extraProperties: [String: Any] = [:]) {
    var props: [String: Any] = ["permission": permission]
    for (key, value) in extraProperties {
      props[key] = value
    }
    track("Permission Denied", properties: props)
  }

  func permissionSkipped(permission: String, extraProperties: [String: Any] = [:]) {
    var props: [String: Any] = ["permission": permission]
    for (key, value) in extraProperties {
      props[key] = value
    }
    track("Permission Skipped", properties: props)
  }

  /// Track when ScreenCaptureKit broken state is detected
  func screenCaptureBrokenDetected() {
    track("Screen Capture Broken Detected", properties: [:])
  }

  /// Track when user clicks reset button or notification
  func screenCaptureResetClicked(source: String) {
    track(
      "Screen Capture Reset Clicked",
      properties: [
        "source": source
      ])
  }

  /// Track when screen capture reset completes
  func screenCaptureResetCompleted(success: Bool) {
    track(
      "Screen Capture Reset Completed",
      properties: [
        "success": success
      ])
  }

  func notificationRepairTriggered(reason: String, previousStatus: String, currentStatus: String) {
    track(
      "Notification Repair Triggered",
      properties: [
        "reason": reason,
        "previous_status": previousStatus,
        "current_status": currentStatus,
      ])
  }

  func notificationSettingsChecked(
    authStatus: String,
    alertStyle: String,
    soundEnabled: Bool,
    badgeEnabled: Bool,
    bannersDisabled: Bool
  ) {
    track(
      "Notification Settings Checked",
      properties: [
        "auth_status": authStatus,
        "alert_style": alertStyle,
        "sound_enabled": soundEnabled,
        "badge_enabled": badgeEnabled,
        "banners_disabled": bannersDisabled,
      ])
  }

  // MARK: - App Lifecycle Events

  func appLaunched() {
    track(
      "App Launched",
      properties: [
        "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
  }

  /// Track first launch with comprehensive system diagnostics
  func firstLaunch(diagnostics: [String: Any]) {
    track("First Launch", properties: diagnostics)
  }

  // MARK: - Page/Screen Views (PostHog specific)

  func pageViewed(_ pageName: String) {
    screen(pageName)
    track("Page Viewed", properties: ["page": pageName])
  }

  // MARK: - Conversation Events
  // Note: The event is named "Memory Created" in analytics for historical reasons,
  // but it actually tracks when a conversation/recording is created, not a "memory".
  // This matches Flutter's naming for analytics consistency.

  func conversationCreated(conversationId: String, source: String, durationSeconds: Int? = nil) {
    var properties: [String: Any] = [
      "conversation_id": conversationId,
      "source": source,
    ]
    if let duration = durationSeconds {
      properties["duration_seconds"] = duration
    }
    track("Memory Created", properties: properties)
  }

  func memoryDeleted(conversationId: String) {
    track(
      "Memory Deleted",
      properties: [
        "conversation_id": conversationId
      ])
  }

  // MARK: - Chat Events

  func chatMessageSent(messageLength: Int, source: String) {
    track(
      "Chat Message Sent",
      properties: [
        "message_length": messageLength,
        "source": source,
      ])
  }

  // MARK: - Search Events

  func searchQueryEntered(query: String) {
    track(
      "Search Query Entered",
      properties: [
        "query_length": query.count
      ])
  }

  func searchBarFocused() {
    track("Search Bar Focused")
  }

  // MARK: - Settings Events

  func settingsPageOpened() {
    track("Settings Page Opened")
  }

  // MARK: - Account Events

  func deleteAccountClicked() {
    track("Delete Account Clicked")
  }

  func deleteAccountConfirmed() {
    track("Delete Account Confirmed")
  }

  func deleteAccountCancelled() {
    track("Delete Account Cancelled")
  }

  // MARK: - Navigation Events

  func tabChanged(tabName: String) {
    track(
      "Tab Changed",
      properties: [
        "tab_name": tabName
      ])
  }

  func conversationDetailOpened() {
    track("Conversation Detail Opened")
  }

  // MARK: - Chat Events (Additional)

  func chatCleared() {
    track("Chat Cleared")
  }

  // MARK: - Settings Events (Additional)

  func settingToggled(setting: String, enabled: Bool) {
    track(
      "Setting Toggled",
      properties: [
        "setting": setting,
        "enabled": enabled,
      ])
  }

  func languageChanged(language: String) {
    track(
      "Language Changed",
      properties: [
        "language": language
      ])
  }

  // MARK: - Launch At Login Events

  func launchAtLoginChanged(enabled: Bool, source: String) {
    track(
      "Launch At Login Changed",
      properties: [
        "enabled": enabled,
        "source": source,
      ])
  }

  // MARK: - Feedback Events

  func feedbackOpened() {
    track("Feedback Opened")
  }

  func feedbackSubmitted(feedbackLength: Int) {
    track(
      "Feedback Submitted",
      properties: [
        "feedback_length": feedbackLength
      ])
  }

  // MARK: - Rewind Events (Desktop-specific)

  func rewindSearchPerformed(queryLength: Int) {
    track(
      "Rewind Search Performed",
      properties: [
        "query_length": queryLength
      ])
  }

  func rewindScreenshotViewed(timestamp: Date) {
    track(
      "Rewind Screenshot Viewed",
      properties: [
        "timestamp": ISO8601DateFormatter().string(from: timestamp)
      ])
  }

  func ffmpegResolved(source: String, path: String) {
    track(
      "FFmpeg Resolved",
      properties: [
        "source": source,
        "path_kind": path.contains(".app/Contents/") ? "bundled" : "external",
      ])
  }

  func rewindTimelineNavigated(direction: String) {
    track(
      "Rewind Timeline Navigated",
      properties: [
        "direction": direction
      ])
  }

  // MARK: - Proactive Assistant Events (Desktop-specific)

  func focusAlertShown(app: String) {
    track(
      "Focus Alert Shown",
      properties: [
        "app": app
      ])
  }

  func focusAlertDismissed(app: String, action: String) {
    track(
      "Focus Alert Dismissed",
      properties: [
        "app": app,
        "action": action,
      ])
  }

  func taskExtracted(taskCount: Int) {
    track(
      "Task Extracted",
      properties: [
        "task_count": taskCount
      ])
  }

  func taskCompleted(source: String?) {
    track(
      "Task Completed",
      properties: [
        "source": source ?? "unknown"
      ])
  }

  func taskDeleted(source: String?) {
    track(
      "Task Deleted",
      properties: [
        "source": source ?? "unknown"
      ])
  }

  func taskAdded() {
    track("Task Added")
  }

  func memoryExtracted(memoryCount: Int) {
    track(
      "Memory Extracted",
      properties: [
        "memory_count": memoryCount
      ])
  }

  // MARK: - Memory Assistant Telemetry (proactive screen-context assistant)

  /// Emitted on a user-initiated persisted change to one of the two MemoryAssistant
  /// settings that gate analysis (`enabled`, `notifications_enabled`). Makes the true
  /// activation denominator (monitoring users who also enabled memory notifications)
  /// measurable. Closed schema only — bounded `setting` + boolean `value`.
  func memoryAssistantSettingChanged(setting: MemoryAssistantTelemetry.Setting, value: Bool) {
    track(
      MemoryAssistantTelemetry.settingChangedEventName,
      properties: MemoryAssistantTelemetry.settingChangedPayload(setting: setting, value: value)
    )
  }

  /// Emitted once per actual Gemini analysis attempt (not per captured frame, and not
  /// on disabled/gated paths) with a closed terminal `outcome`. Supplements — does not
  /// replace — the existing `Memory Extracted` success terminal. Confidence is bucketed
  /// to a coarse decile range; raw model material is never sent.
  func memoryAssistantAnalysisRun(
    outcome: MemoryAssistantTelemetry.AnalysisOutcome,
    confidence: Double? = nil
  ) {
    track(
      MemoryAssistantTelemetry.analysisRunEventName,
      properties: MemoryAssistantTelemetry.analysisRunPayload(outcome: outcome, confidence: confidence)
    )
  }

  // MARK: - Suggestion Assistant Telemetry

  func suggestionAssistantSettingChanged(setting: SuggestionAssistantTelemetry.Setting, value: Bool) {
    track(
      SuggestionAssistantTelemetry.settingChangedEventName,
      properties: SuggestionAssistantTelemetry.settingChangedPayload(setting: setting, value: value)
    )
  }

  func suggestionAssistantGateOutcome(_ outcome: SuggestionAssistantTelemetry.GateOutcome) {
    track(
      SuggestionAssistantTelemetry.gateOutcomeEventName,
      properties: SuggestionAssistantTelemetry.gateOutcomePayload(outcome)
    )
  }

  func suggestionAssistantEvaluationStarted(
    identity: SuggestionAssistantTelemetry.Identity,
    shape: SuggestionAssistantTelemetry.EvaluationShape
  ) {
    track(
      SuggestionAssistantTelemetry.evaluationStartedEventName,
      properties: SuggestionAssistantTelemetry.evaluationStartedPayload(identity: identity, shape: shape)
    )
  }

  func suggestionAssistantEvaluationCompleted(
    identity: SuggestionAssistantTelemetry.Identity,
    shape: SuggestionAssistantTelemetry.EvaluationShape,
    latency: TimeInterval,
    producedSuggestion: Bool
  ) {
    track(
      SuggestionAssistantTelemetry.evaluationCompletedEventName,
      properties: SuggestionAssistantTelemetry.evaluationCompletedPayload(
        identity: identity,
        shape: shape,
        latency: latency,
        producedSuggestion: producedSuggestion
      )
    )
  }

  func suggestionAssistantEvaluationFailed(
    identity: SuggestionAssistantTelemetry.Identity,
    shape: SuggestionAssistantTelemetry.EvaluationShape,
    latency: TimeInterval
  ) {
    track(
      SuggestionAssistantTelemetry.evaluationFailedEventName,
      properties: SuggestionAssistantTelemetry.evaluationFailedPayload(
        identity: identity,
        shape: shape,
        latency: latency
      )
    )
  }

  func suggestionAssistantDeliveryOutcome(
    _ outcome: SuggestionAssistantTelemetry.DeliveryOutcome,
    identity: SuggestionAssistantTelemetry.NotificationIdentity
  ) {
    track(
      SuggestionAssistantTelemetry.deliveryOutcomeEventName,
      properties: SuggestionAssistantTelemetry.deliveryOutcomePayload(outcome, identity: identity)
    )
  }

  func insightGenerated(category: String?) {
    var properties: [String: Any] = [:]
    if let cat = category { properties["category"] = cat }
    track("Advice Generated", properties: properties.isEmpty ? nil : properties)
  }

  // MARK: - Update Events

  func updateAvailable(version: String, context: UpdateAnalyticsContext, item: UpdateItemAnalytics) {
    track("Update Available", properties: updateProperties(version: version, context: context, item: item))
  }

  func updateInstallStarted(attempt: UpdateInstallAttempt) {
    track("Update Install Started", properties: attempt.analyticsProperties)
  }

  func updateInstalled(
    attempt: UpdateInstallAttempt,
    installedVersion: String,
    installedBuild: String
  ) {
    var properties = attempt.analyticsProperties
    properties["installed_version"] = installedVersion
    properties["installed_build"] = installedBuild
    properties["update_duration_seconds"] = max(0, Date().timeIntervalSince(attempt.startedAt))
    properties["verified_after_relaunch"] = true
    track("Update Installed", properties: properties)
  }

  func updateInstallVerificationFailed(
    attempt: UpdateInstallAttempt,
    installedVersion: String,
    installedBuild: String
  ) {
    var properties = attempt.analyticsProperties
    properties["installed_version"] = installedVersion
    properties["installed_build"] = installedBuild
    properties["update_duration_seconds"] = max(0, Date().timeIntervalSince(attempt.startedAt))
    properties["verified_after_relaunch"] = false
    properties["error"] = "post_relaunch_build_mismatch"
    properties["error_class"] = "post_relaunch_build_mismatch"
    properties["phase"] = "post_relaunch_verification"
    track("Update Install Verification Failed", properties: properties)
  }

  func updateCheckFailed(diagnostics: UpdateFailureDiagnostics) {
    track("Update Check Failed", properties: diagnostics.analyticsProperties)
  }

  private func updateProperties(
    version: String,
    context: UpdateAnalyticsContext,
    item: UpdateItemAnalytics
  ) -> [String: Any] {
    var properties = context.properties
    properties.merge(item.properties) { _, new in new }
    properties["version"] = version
    return properties
  }

  // MARK: - Notification Events

  func notificationSent(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String,
    suggestionIdentity: SuggestionAssistantTelemetry.NotificationIdentity? = nil
  ) {
    var properties = notificationProperties(
      notificationId: notificationId,
      title: title,
      assistantId: assistantId,
      surface: surface
    )
    appendSuggestionNotificationIdentity(suggestionIdentity, to: &properties)
    track(
      "Notification Sent",
      properties: properties)
  }

  func notificationClicked(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String,
    suggestionIdentity: SuggestionAssistantTelemetry.NotificationIdentity? = nil
  ) {
    var properties = notificationProperties(
      notificationId: notificationId,
      title: title,
      assistantId: assistantId,
      surface: surface
    )
    appendSuggestionNotificationIdentity(suggestionIdentity, to: &properties)
    track(
      "Notification Clicked",
      properties: properties)
  }

  func notificationDismissed(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String,
    suggestionIdentity: SuggestionAssistantTelemetry.NotificationIdentity? = nil
  ) {
    var properties = notificationProperties(
      notificationId: notificationId,
      title: title,
      assistantId: assistantId,
      surface: surface
    )
    appendSuggestionNotificationIdentity(suggestionIdentity, to: &properties)
    track(
      "Notification Dismissed",
      properties: properties)
  }

  private func notificationProperties(
    notificationId: String,
    title: String,
    assistantId: String,
    surface: String
  ) -> [String: Any] {
    [
      "notification_id": notificationId,
      "title_length": title.count,
      "has_title": !title.isEmpty,
      "assistant_id": assistantId,
      "notification_surface": surface,
    ]
  }

  private func appendSuggestionNotificationIdentity(
    _ identity: SuggestionAssistantTelemetry.NotificationIdentity?,
    to properties: inout [String: Any]
  ) {
    guard let identity else { return }
    properties.merge(SuggestionAssistantTelemetry.notificationPayload(identity)) { _, new in new }
  }

  func notificationWillPresent(notificationId: String, title: String) {
    track(
      "Notification Will Present",
      properties: [
        "notification_id": notificationId,
        "title_length": title.count,
        "has_title": !title.isEmpty,
      ])
  }

  func notificationDelegateReady() {
    track("Notification Delegate Ready")
  }

  // MARK: - Menu Bar Events

  func menuBarOpened() {
    track("Menu Bar Opened")
  }

  func menuBarActionClicked(action: String) {
    track(
      "Menu Bar Action Clicked",
      properties: [
        "action": action
      ])
  }

  // MARK: - Settings State

  /// Comprehensive all-settings snapshot (fired on app launch, at most once per day)
  func allSettingsStateTracked(properties: [String: Any]) {
    track("All Settings State", properties: properties)
  }
}
