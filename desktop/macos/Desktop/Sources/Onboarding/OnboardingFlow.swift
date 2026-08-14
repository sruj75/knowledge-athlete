import Foundation

/// Account-scoped persistence shared by the active Second Brain onboarding flow.
enum OnboardingFlow {
  /// `hasCompletedOnboarding` is owned by `AppState` and reset through the
  /// mounted-view notifications. Chat-journal persistence has its own owner.
  static let persistedStateKeys: [String] = [
    "onboardingStep",
    "onboardingFurthestStep",
    "onboardingHowDidYouHearSource",
    "sbOnboardingResumeStep",
    "onboardingRole",
    "onboardingGoalDraft",
    "onboardingJustCompleted",
    "hasSeenRewindIntro",
    "hasTriggeredNotification",
    "hasTriggeredScreenRecording",
    "hasTriggeredMicrophone",
    "hasTriggeredSystemAudio",
    "hasTriggeredAccessibility",
    "hasTriggeredBluetooth",
  ]

  static func clearPersistedState(in defaults: UserDefaults = .standard) {
    for key in persistedStateKeys {
      defaults.removeObject(forKey: key)
    }
  }
}
