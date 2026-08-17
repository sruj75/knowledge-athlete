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
    let transcriptionWasRunning = appState?.isTranscribing == true
    let monitoringWasRunning = plugin.isMonitoring
    return Self(
      effects: .init(
        quiesce: {
          if plugin.isMonitoring { plugin.stopMonitoring() }
          if appState?.isTranscribing == true {
            appState?.stopTranscription()
            await waitForTranscriptionIdle(appState)
          }
        },
        restore: {
          if transcriptionWasRunning, AssistantSettings.shared.transcriptionEnabled {
            await waitForTranscriptionIdle(appState)
            if appState?.isTranscribing == false {
              appState?.startTranscription()
              await appState?.reconcileCapture()
            }
          }
          plugin.refreshScreenRecordingPermission()
          if monitoringWasRunning,
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

  private static func waitForTranscriptionIdle(_ appState: AppState?) async {
    for _ in 0..<100 where appState?.isTranscribing == true {
      try? await Task.sleep(for: .milliseconds(50))
    }
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

  func execute() async throws -> Bool {
    await preparation.clearCurrentOwnerJournal()
    await captureRuntime.quiesce()
    do {
      guard try await commitAuthentication() else {
        await captureRuntime.restore()
        return false
      }
    } catch {
      await captureRuntime.restore()
      throw error
    }
    _ = await preparation.execute(source: .signOut, journalAlreadyCleared: true)
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
    let clearLocalNameProjection: () -> Void
  }

  let effects: Effects

  func execute(
    source: OnboardingReplaySource,
    journalAlreadyCleared: Bool = false
  ) async -> OnboardingReplayPlan {
    effects.setTranscriptionIntent(false)
    effects.stopTranscription()
    effects.setScreenAnalysisIntent(false)
    effects.stopScreenMonitoring()
    effects.resetCompletion()
    effects.clearPersistedState()
    if !journalAlreadyCleared { await clearCurrentOwnerJournal() }
    effects.resetOnboardingProjection()
    if source == .signOut { effects.clearLocalNameProjection() }
    return OnboardingReplayPolicy.plan(for: source)
  }

  func clearCurrentOwnerJournal() async {
    await effects.clearOnboardingJournal()
  }

  static func live(
    appState: AppState?,
    chatProvider: ChatProvider?,
    clearLocalNameProjection: @escaping () -> Void = {
      AuthService.shared.givenName = ""
      AuthService.shared.familyName = ""
    }
  ) -> Self {
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
        resetOnboardingProjection: { chatProvider?.resetOnboardingProjectionForReplay() },
        clearLocalNameProjection: clearLocalNameProjection))
  }
}

enum OnboardingResetAutomationPolicy {
  static func isAvailable(isProductionBundle: Bool) -> Bool {
    !isProductionBundle
  }
}
