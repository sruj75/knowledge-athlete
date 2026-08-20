import SwiftUI

/// Capture/Listening control logic used by the persistent shell status bar.
@MainActor
enum CaptureListeningLogic {
  // MARK: Status derivations

  static func captureStatus(appState: AppState, isCaptureMonitoring: Bool) -> HomeStatusState {
    if appState.isScreenCaptureKitBroken || appState.isScreenRecordingStale || !appState.hasScreenRecordingPermission {
      return .blocked
    }
    return isCaptureLive(isCaptureMonitoring: isCaptureMonitoring) ? .active : .inactive
  }

  static func isCaptureLive(isCaptureMonitoring: Bool) -> Bool {
    isCaptureMonitoring || ProactiveAssistantsPlugin.shared.isMonitoring
  }

  static func listeningCaptureMode(raw: String) -> AssistantSettings.SystemAudioCaptureMode {
    AssistantSettings.SystemAudioCaptureMode(rawValue: raw) ?? .onlyDuringMeetings
  }

  static func listeningModeTitle(appState: AppState, raw: String) -> String {
    switch listeningCaptureMode(raw: raw) {
    case .always:
      return "Always"
    case .onlyDuringMeetings:
      return "Meetings Only"
    case .never:
      return "Mic only"
    }
  }

  // MARK: Actions

  static func toggleListening(
    appState: AppState, transcriptionEnabled: Binding<Bool>, isTogglingListening: Binding<Bool>
  ) {
    let enabled = !appState.isTranscribing
    if enabled { OnboardingExitPersistence.recordExplicitCapabilityEnablement() }
    if enabled && !appState.hasMicrophonePermission {
      appState.requestMicrophonePermission()
      return
    }

    isTogglingListening.wrappedValue = true
    transcriptionEnabled.wrappedValue = enabled
    AssistantSettings.shared.transcriptionEnabled = enabled
    AnalyticsManager.shared.settingToggled(setting: "transcription", enabled: enabled)
    NotificationCenter.default.post(
      name: .toggleTranscriptionRequested,
      object: nil,
      userInfo: ["enabled": enabled]
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      isTogglingListening.wrappedValue = false
    }
  }

  static func setListeningMode(_ mode: AssistantSettings.SystemAudioCaptureMode, raw: Binding<String>) {
    raw.wrappedValue = mode.rawValue
    AssistantSettings.shared.systemAudioCaptureMode = mode
    AnalyticsManager.shared.settingToggled(
      setting: "meetings_only_listening",
      enabled: mode == .onlyDuringMeetings
    )
  }

  static func toggleListeningMode(raw: Binding<String>) {
    let nextMode: AssistantSettings.SystemAudioCaptureMode =
      listeningCaptureMode(raw: raw.wrappedValue) == .onlyDuringMeetings ? .always : .onlyDuringMeetings
    setListeningMode(nextMode, raw: raw)
  }

  static func toggleCapture(
    appState: AppState, screenAnalysisEnabled: Binding<Bool>, isCaptureMonitoring: Binding<Bool>,
    isTogglingCapture: Binding<Bool>
  ) {
    syncCaptureState(screenAnalysisEnabled: screenAnalysisEnabled, isCaptureMonitoring: isCaptureMonitoring)
    let enabled = !isCaptureLive(isCaptureMonitoring: isCaptureMonitoring.wrappedValue)
    isTogglingCapture.wrappedValue = true

    if enabled {
      ProactiveAssistantsPlugin.shared.refreshScreenRecordingPermission()
      guard ProactiveAssistantsPlugin.shared.hasScreenRecordingPermission else {
        screenAnalysisEnabled.wrappedValue = false
        isCaptureMonitoring.wrappedValue = false
        isTogglingCapture.wrappedValue = false
        ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
        return
      }
      OnboardingExitPersistence.recordExplicitCapabilityEnablement()
    }

    screenAnalysisEnabled.wrappedValue = enabled
    AssistantSettings.shared.screenAnalysisEnabled = enabled
    AnalyticsManager.shared.settingToggled(setting: "monitoring", enabled: enabled)

    if enabled {
      ProactiveAssistantsPlugin.shared.startMonitoring { success, _ in
        DispatchQueue.main.async {
          isTogglingCapture.wrappedValue = false
          isCaptureMonitoring.wrappedValue = ProactiveAssistantsPlugin.shared.isMonitoring
          if !success {
            screenAnalysisEnabled.wrappedValue = false
            AssistantSettings.shared.screenAnalysisEnabled = false
            isCaptureMonitoring.wrappedValue = false
          }
        }
      }
    } else {
      ProactiveAssistantsPlugin.shared.stopMonitoring()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        isTogglingCapture.wrappedValue = false
        isCaptureMonitoring.wrappedValue = false
      }
    }
  }

  static func syncCaptureState(screenAnalysisEnabled: Binding<Bool>, isCaptureMonitoring: Binding<Bool>) {
    ProactiveAssistantsPlugin.shared.refreshScreenRecordingPermission()
    screenAnalysisEnabled.wrappedValue = AssistantSettings.shared.screenAnalysisEnabled
    isCaptureMonitoring.wrappedValue = ProactiveAssistantsPlugin.shared.isMonitoring
  }
}
