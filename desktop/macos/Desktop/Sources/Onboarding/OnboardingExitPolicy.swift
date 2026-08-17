import Foundation

enum OnboardingExitOutcome: Equatable {
  case skipped
  case completed(SBOnboardingModel.CaptureSelection)
}

struct OnboardingExitPlan: Equatable {
  let systemAudioCaptureMode: AssistantSettings.SystemAudioCaptureMode?
  let transcriptionIntentEnabled: Bool
  let shouldStartTranscriptionSession: Bool
  let shouldCaptureWithoutActiveMeeting: Bool
}

enum OnboardingExitPolicy {
  static func plan(for outcome: OnboardingExitOutcome) -> OnboardingExitPlan {
    switch outcome {
    case .skipped:
      return OnboardingExitPlan(
        systemAudioCaptureMode: nil,
        transcriptionIntentEnabled: false,
        shouldStartTranscriptionSession: false,
        shouldCaptureWithoutActiveMeeting: false)
    case .completed(let selection):
      return OnboardingExitPlan(
        systemAudioCaptureMode: selection.systemAudioCaptureMode,
        transcriptionIntentEnabled: true,
        shouldStartTranscriptionSession: true,
        shouldCaptureWithoutActiveMeeting: selection.capturesWithoutActiveMeeting)
    }
  }
}
