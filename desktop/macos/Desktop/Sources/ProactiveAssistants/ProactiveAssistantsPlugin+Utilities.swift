import Cocoa

extension ProactiveAssistantsPlugin {
  func resetOwnerBoundCaptureState() {
    isProcessingRewindFrame = false
    rewindFrameAuthorization = nil
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
    SystemInputIdleClock.seconds()
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

}
