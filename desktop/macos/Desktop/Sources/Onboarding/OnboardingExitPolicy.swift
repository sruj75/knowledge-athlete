import Foundation

enum SBOnboardingCompletionCopy {
  static let disclosure =
    "Finish setup requests Launch at Login, starts listening in your chosen mode, and turns on screen analysis when permission and account access allow."
}

enum OnboardingScreenMonitoringStartPolicy {
  static func shouldStart(
    intentEnabled: Bool,
    isPaywalled: Bool,
    keysAvailable: Bool,
    permissionGranted: Bool,
    isMonitoring: Bool
  ) -> Bool {
    intentEnabled && !isPaywalled && keysAvailable && permissionGranted && !isMonitoring
  }
}

enum OnboardingExitOutcome: Equatable {
  case skipped
  case completed(SBOnboardingModel.CaptureSelection)
}

enum OnboardingExitAnalyticsOutcome: Equatable {
  case skipped
  case completed

  var eventName: String {
    switch self {
    case .skipped: "Onboarding Skipped"
    case .completed: "Onboarding Completed"
    }
  }
}

enum OnboardingPersistedExitOutcome: String, Equatable {
  case skipped
  case completed
}

enum OnboardingExitPersistence {
  static func persist(
    _ outcome: OnboardingPersistedExitOutcome,
    in defaults: UserDefaults = .standard
  ) {
    defaults.set(outcome.rawValue, forKey: .onboardingExitOutcome)
  }

  static func outcome(in defaults: UserDefaults = .standard) -> OnboardingPersistedExitOutcome? {
    defaults.string(forKey: .onboardingExitOutcome).flatMap(OnboardingPersistedExitOutcome.init(rawValue:))
  }

  /// Skip is a restoration fence, not a permanent capability ban. Retire it
  /// only when the user explicitly enables capture from a product control;
  /// remote settings and launch restoration must continue to respect it.
  static func recordExplicitCapabilityEnablement(in defaults: UserDefaults = .standard) {
    guard outcome(in: defaults) == .skipped else { return }
    defaults.removeObject(forKey: .onboardingExitOutcome)
  }
}

struct OnboardingExitPlan: Equatable {
  let analyticsOutcome: OnboardingExitAnalyticsOutcome
  let persistedOutcome: OnboardingPersistedExitOutcome
  let systemAudioCaptureMode: AssistantSettings.SystemAudioCaptureMode?
  let transcriptionIntentEnabled: Bool
  let shouldStartTranscriptionSession: Bool
  let shouldStopTranscriptionSession: Bool
  let shouldCaptureWithoutActiveMeeting: Bool
  let screenAnalysisIntentEnabled: Bool
  let shouldStartScreenMonitoring: Bool
  let shouldStopScreenMonitoring: Bool
  let launchAtLoginRequested: Bool
  let shouldPresentOpener: Bool
  let shouldMarkJustCompleted: Bool
}

enum OnboardingExitPolicy {
  static func plan(for outcome: OnboardingExitOutcome) -> OnboardingExitPlan {
    switch outcome {
    case .skipped:
      return OnboardingExitPlan(
        analyticsOutcome: .skipped,
        persistedOutcome: .skipped,
        systemAudioCaptureMode: nil,
        transcriptionIntentEnabled: false,
        shouldStartTranscriptionSession: false,
        shouldStopTranscriptionSession: true,
        shouldCaptureWithoutActiveMeeting: false,
        screenAnalysisIntentEnabled: false,
        shouldStartScreenMonitoring: false,
        shouldStopScreenMonitoring: true,
        launchAtLoginRequested: false,
        shouldPresentOpener: false,
        shouldMarkJustCompleted: false)
    case .completed(let selection):
      return OnboardingExitPlan(
        analyticsOutcome: .completed,
        persistedOutcome: .completed,
        systemAudioCaptureMode: selection.systemAudioCaptureMode,
        transcriptionIntentEnabled: true,
        shouldStartTranscriptionSession: true,
        shouldStopTranscriptionSession: false,
        shouldCaptureWithoutActiveMeeting: selection.capturesWithoutActiveMeeting,
        screenAnalysisIntentEnabled: true,
        shouldStartScreenMonitoring: true,
        shouldStopScreenMonitoring: false,
        launchAtLoginRequested: true,
        shouldPresentOpener: true,
        shouldMarkJustCompleted: true)
    }
  }
}

@MainActor
struct OnboardingExitExecutor {
  struct Effects {
    let recordAnalytics: @MainActor (OnboardingExitAnalyticsOutcome) -> Void
    let persistOutcome: @MainActor (OnboardingPersistedExitOutcome) -> Void
    let setTranscriptionIntent: @MainActor (Bool) -> Void
    let startTranscriptionSession: @MainActor () async -> Void
    let stopTranscriptionSession: @MainActor () -> Void
    let setScreenAnalysisIntent: @MainActor (Bool) -> Void
    let startScreenMonitoring: @MainActor () -> Void
    let stopScreenMonitoring: @MainActor () -> Void
    let requestLaunchAtLogin: @MainActor (Bool) -> Void
    let setJustCompleted: @MainActor (Bool) -> Void
    let prepareMainChat: @MainActor () -> Void
    let presentOpener: @MainActor () -> Void
    let clearResumeState: @MainActor () -> Void
    let finishJournal: @MainActor () async -> Void
    let publishCompletion: @MainActor () -> Void
    let setSystemAudioCaptureMode: @MainActor (AssistantSettings.SystemAudioCaptureMode) -> Void

    init(
      recordAnalytics: @escaping @MainActor (OnboardingExitAnalyticsOutcome) -> Void,
      persistOutcome: @escaping @MainActor (OnboardingPersistedExitOutcome) -> Void,
      setTranscriptionIntent: @escaping @MainActor (Bool) -> Void,
      startTranscriptionSession: @escaping @MainActor () async -> Void,
      stopTranscriptionSession: @escaping @MainActor () -> Void,
      setScreenAnalysisIntent: @escaping @MainActor (Bool) -> Void,
      startScreenMonitoring: @escaping @MainActor () -> Void,
      stopScreenMonitoring: @escaping @MainActor () -> Void,
      requestLaunchAtLogin: @escaping @MainActor (Bool) -> Void,
      setJustCompleted: @escaping @MainActor (Bool) -> Void,
      prepareMainChat: @escaping @MainActor () -> Void,
      presentOpener: @escaping @MainActor () -> Void,
      clearResumeState: @escaping @MainActor () -> Void,
      finishJournal: @escaping @MainActor () async -> Void,
      publishCompletion: @escaping @MainActor () -> Void,
      setSystemAudioCaptureMode: @escaping @MainActor (AssistantSettings.SystemAudioCaptureMode) -> Void = { _ in }
    ) {
      self.recordAnalytics = recordAnalytics
      self.persistOutcome = persistOutcome
      self.setTranscriptionIntent = setTranscriptionIntent
      self.startTranscriptionSession = startTranscriptionSession
      self.stopTranscriptionSession = stopTranscriptionSession
      self.setScreenAnalysisIntent = setScreenAnalysisIntent
      self.startScreenMonitoring = startScreenMonitoring
      self.stopScreenMonitoring = stopScreenMonitoring
      self.requestLaunchAtLogin = requestLaunchAtLogin
      self.setJustCompleted = setJustCompleted
      self.prepareMainChat = prepareMainChat
      self.presentOpener = presentOpener
      self.clearResumeState = clearResumeState
      self.finishJournal = finishJournal
      self.publishCompletion = publishCompletion
      self.setSystemAudioCaptureMode = setSystemAudioCaptureMode
    }
  }

  let effects: Effects

  func execute(_ plan: OnboardingExitPlan, onComplete: (@MainActor @Sendable () -> Void)? = nil) {
    Task { @MainActor in
      effects.recordAnalytics(plan.analyticsOutcome)
      effects.persistOutcome(plan.persistedOutcome)
      if let mode = plan.systemAudioCaptureMode {
        effects.setSystemAudioCaptureMode(mode)
      }
      effects.setTranscriptionIntent(plan.transcriptionIntentEnabled)
      effects.setScreenAnalysisIntent(plan.screenAnalysisIntentEnabled)
      effects.requestLaunchAtLogin(plan.launchAtLoginRequested)
      if plan.shouldStopTranscriptionSession {
        effects.stopTranscriptionSession()
      } else if plan.shouldStartTranscriptionSession {
        await effects.startTranscriptionSession()
      }
      if plan.shouldStopScreenMonitoring {
        effects.stopScreenMonitoring()
      } else if plan.shouldStartScreenMonitoring {
        effects.startScreenMonitoring()
      }
      effects.clearResumeState()
      await effects.finishJournal()
      effects.prepareMainChat()
      if plan.shouldPresentOpener {
        effects.presentOpener()
      }
      effects.setJustCompleted(plan.shouldMarkJustCompleted)
      onComplete?()
      effects.publishCompletion()
    }
  }
}
