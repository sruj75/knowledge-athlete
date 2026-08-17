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

@MainActor
private final class OnboardingSignOutCaptureSnapshot {
  var transcriptionWasRunning = false
  var monitoringWasRunning = false
}

@MainActor
struct OnboardingSignOutCaptureRuntime {
  struct Effects {
    let quiesce: () async -> Void
    let restore: () async -> Void
  }

  let effects: Effects

  func quiesce() async { await effects.quiesce() }
  func restore() async { await effects.restore() }

  static func live(appState: AppState?) -> Self {
    let plugin = ProactiveAssistantsPlugin.shared
    let snapshot = OnboardingSignOutCaptureSnapshot()
    return Self(
      effects: .init(
        quiesce: {
          snapshot.transcriptionWasRunning = appState?.isTranscribing == true
          snapshot.monitoringWasRunning = plugin.isMonitoring
          plugin.stopMonitoring()
          if appState?.isTranscribing == true || appState?.transcriptionStopTask != nil {
            await appState?.stopTranscriptionAndWait()
          }
        },
        restore: {
          if snapshot.transcriptionWasRunning, AssistantSettings.shared.transcriptionEnabled {
            if appState?.isTranscribing == false {
              appState?.startTranscription()
              await appState?.reconcileCapture()
            }
          }
          plugin.refreshScreenRecordingPermission()
          if snapshot.monitoringWasRunning,
            OnboardingScreenMonitoringStartPolicy.shouldStart(
              intentEnabled: AssistantSettings.shared.screenAnalysisEnabled,
              isPaywalled: AppState.isPaywalledEffective,
              keysAvailable: APIKeyService.keysAvailable,
              permissionGranted: plugin.hasScreenRecordingPermission,
              isMonitoring: plugin.isMonitoring)
          {
            plugin.startMonitoring { _, _ in }
          }
        }))
  }

}

/// Sign-out deletes the setup journal and quiesces capture while the current
/// owner is still authoritative. Persisted state changes only after auth
/// commits; failed commits restore runtime capture from unchanged user intent.
@MainActor
struct OnboardingSignOutTransaction {
  let preparation: OnboardingReplayPreparation
  let captureRuntime: OnboardingSignOutCaptureRuntime
  let commitAuthentication: () async throws -> Bool
  let isAuthenticationAuthoritative: () -> Bool

  func execute() async throws -> Bool {
    await preparation.clearCurrentOwnerJournal()
    await captureRuntime.quiesce()
    let committed: Bool
    do {
      committed = try await commitAuthentication()
    } catch {
      if isAuthenticationAuthoritative() { await captureRuntime.restore() }
      throw error
    }
    guard committed else {
      if isAuthenticationAuthoritative() { await captureRuntime.restore() }
      return false
    }
    guard isAuthenticationAuthoritative() else { return false }
    _ = preparation.executeAfterJournalCleared(source: .signOut)
    return true
  }
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
    let resetOnboardingProjection: () -> Void
  }

  let effects: Effects

  func execute(
    source: OnboardingReplaySource,
    journalAlreadyCleared: Bool = false
  ) async -> OnboardingReplayPlan {
    applyCaptureAndPersistedStateCleanup()
    if !journalAlreadyCleared { await clearCurrentOwnerJournal() }
    return finishCleanup(source: source)
  }

  func executeAfterJournalCleared(source: OnboardingReplaySource) -> OnboardingReplayPlan {
    applyCaptureAndPersistedStateCleanup()
    return finishCleanup(source: source)
  }

  private func applyCaptureAndPersistedStateCleanup() {
    effects.setTranscriptionIntent(false)
    effects.stopTranscription()
    effects.setScreenAnalysisIntent(false)
    effects.stopScreenMonitoring()
    effects.resetCompletion()
    effects.clearPersistedState()
  }

  private func finishCleanup(source: OnboardingReplaySource) -> OnboardingReplayPlan {
    effects.resetOnboardingProjection()
    return OnboardingReplayPolicy.plan(for: source)
  }

  func clearCurrentOwnerJournal() async {
    await effects.clearOnboardingJournal()
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
        },
        resetOnboardingProjection: { chatProvider?.resetOnboardingProjectionForReplay() }))
  }
}

enum OnboardingResetAutomationPolicy {
  static func isAvailable(isProductionBundle: Bool) -> Bool {
    !isProductionBundle
  }
}
