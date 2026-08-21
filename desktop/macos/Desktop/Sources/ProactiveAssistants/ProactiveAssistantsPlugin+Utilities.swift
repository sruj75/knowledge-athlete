import Cocoa

extension ProactiveAssistantsPlugin {
  func resetOwnerBoundDistributionState() {
    analysisDelayTimer?.invalidate()
    analysisDelayTimer = nil
    distributionDebounceTimer?.invalidate()
    distributionDebounceTimer = nil
    isInDelayPeriod = false
    isProcessingRewindFrame = false
    rewindFrameAuthorization = nil
    FocusStorage.shared.updateDelayEndTime(nil)
    distributionGate.reset()
    latestCapturedFrame = nil
  }

  func beginAnalysisDelay(
    seconds: Int,
    reason: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    isInDelayPeriod = true
    AssistantCoordinator.shared.clearAllPendingWork(
      authorizationSnapshot: authorizationSnapshot)
    log("\(reason), starting \(seconds)s analysis delay")

    analysisDelayTimer?.invalidate()
    let delayEndTime = Date().addingTimeInterval(TimeInterval(seconds))
    FocusStorage.shared.updateDelayEndTime(delayEndTime)
    analysisDelayTimer = Timer.scheduledTimer(
      withTimeInterval: TimeInterval(seconds),
      repeats: false
    ) { [weak self] _ in
      Task { @MainActor in
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        self?.isInDelayPeriod = false
        self?.analysisDelayTimer = nil
        FocusStorage.shared.updateDelayEndTime(nil)
        log("Analysis delay ended, resuming frame processing")
      }
    }
  }

  var pendingDistributionAuthorizationForTests: RuntimeOwnerAuthorizationSnapshot? {
    latestCapturedFrame?.authorizationSnapshot
  }

  func stageDistributionForTests(_ frame: OwnerBoundCapturedFrame) {
    latestCapturedFrame = frame
  }

  var hasAnalysisDelayTimerForTests: Bool { analysisDelayTimer != nil }

  func stageAnalysisDelayForTests(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    beginAnalysisDelay(
      seconds: 3_600,
      reason: "Test owner boundary",
      authorizationSnapshot: authorizationSnapshot)
  }

  /// Repair LaunchServices registration when notification authorization fails with "not allowed".
  static func repairNotificationRegistration() {
    NotificationRegistrationRepair.repair(reason: "legacy_call_site", includeUnregister: true) { _ in
      NotificationRegistrationRepair.requestAuthorizationRepairingLaunchServices(
        reason: "legacy_call_site_retry",
        previousStatus: "post_repair"
      ) { _ in }
    }
  }

  func systemIdleSeconds() -> TimeInterval {
    TimeInterval(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null))
  }

  func sendEvent(type: String, data: [String: Any]) {
    var event = data
    event["type"] = type
    event["timestamp"] = ISO8601DateFormatter().string(from: Date())
    NotificationCenter.default.post(
      name: .assistantEvent,
      object: nil,
      userInfo: event)
  }

  public func openScreenRecordingPreferences() {
    ScreenCaptureService.openScreenRecordingPreferences()
  }

  func triggerGlow(colorMode: GlowColorMode = .focused) {
    OverlayService.shared.showGlowAroundActiveWindow(colorMode: colorMode)
  }
}
