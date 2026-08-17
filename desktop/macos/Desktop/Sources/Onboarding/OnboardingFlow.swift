import Foundation

/// Setup-owned persistence shared by the active Second Brain onboarding flow.
enum OnboardingFlow {
  /// Completion is owned by `AppState`; language is an intentional device
  /// preference; and the user's name is owned by the authenticated Firebase
  /// profile. This list contains only replayable setup state.
  static let persistedStateKeys: [String] = [
    DefaultsKey.onboardingHowDidYouHearSource.rawValue,
    DefaultsKey.onboardingResumeStep.rawValue,
    DefaultsKey.onboardingJustCompleted.rawValue,
    DefaultsKey.onboardingExitOutcome.rawValue,
  ]

  static func clearPersistedState(in defaults: UserDefaults = .standard) {
    for key in persistedStateKeys {
      defaults.removeObject(forKey: key)
    }
  }
}

enum OnboardingReplaySource: String, CaseIterable, Sendable {
  case settings
  case statusMenu
  case automation
  case signOut
}

struct OnboardingReplayPlan: Equatable, Sendable {
  let shouldRestart: Bool
}

enum OnboardingReplayPolicy {
  static func plan(for source: OnboardingReplaySource) -> OnboardingReplayPlan {
    OnboardingReplayPlan(shouldRestart: source != .signOut)
  }
}

/// The single destructive boundary shared by onboarding replay and sign-out.
/// Capture is disabled before completion state or the setup journal changes.
@MainActor
struct OnboardingReplayPreparation {
  struct Effects {
    let setTranscriptionIntent: (Bool) -> Void
    let stopTranscription: () -> Void
    let setScreenAnalysisIntent: (Bool) -> Void
    let stopScreenMonitoring: () -> Void
    let resetCompletion: () -> Void
    let clearPersistedState: () -> Void
    let clearOnboardingJournal: () async -> Void
  }

  let effects: Effects

  func execute(source: OnboardingReplaySource) async -> OnboardingReplayPlan {
    effects.setTranscriptionIntent(false)
    effects.stopTranscription()
    effects.setScreenAnalysisIntent(false)
    effects.stopScreenMonitoring()
    effects.resetCompletion()
    effects.clearPersistedState()
    await effects.clearOnboardingJournal()
    return OnboardingReplayPolicy.plan(for: source)
  }

  static func live(appState: AppState?, chatProvider: ChatProvider?) -> Self {
    Self(
      effects: .init(
        setTranscriptionIntent: { AssistantSettings.shared.transcriptionEnabled = $0 },
        stopTranscription: { appState?.stopTranscription() },
        setScreenAnalysisIntent: { AssistantSettings.shared.screenAnalysisEnabled = $0 },
        stopScreenMonitoring: { ProactiveAssistantsPlugin.shared.stopMonitoring() },
        resetCompletion: {
          appState?.hasCompletedOnboarding = false
          UserDefaults.standard.set(false, forKey: .hasCompletedOnboarding)
        },
        clearPersistedState: { OnboardingFlow.clearPersistedState() },
        clearOnboardingJournal: {
          guard let chatProvider else {
            log("Onboarding journal reset deferred: main chat provider unavailable")
            return
          }
          if await chatProvider.clearOnboardingJournal() {
            log("Cleared onboarding journal")
          } else {
            log("Failed to clear onboarding journal")
          }
        }))
  }
}

enum OnboardingResetAutomationPolicy {
  static func isAvailable(isProductionBundle: Bool) -> Bool {
    !isProductionBundle
  }
}
