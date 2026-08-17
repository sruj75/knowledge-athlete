import AppKit
import Combine
import Foundation

enum SBOnboardingLanguageCopy {
  static let question = "What language should Omi listen and reply in?"
  static let detectedLanguageDetail = "· detected from your Mac"
  static let changeSpokenLanguageAction = "Change spoken language"

  static func continueAction(for language: String) -> String {
    "Continue in \(language)"
  }
}

/// Drives the Second Brain conversational onboarding: a real chat with Omi that
/// streams word-by-word, collects answers, and performs the SAME live side-effects
/// as the legacy wizard (name/language, retained permissions, the summon
/// shortcut, a live screen+voice demo, capture,
/// completion). No fake steps — every widget does real work.
///
/// Core state + lifecycle + copy live here. The heavier per-step behavior
/// (permissions, shortcut, screen/voice demo) lives in
/// `SBOnboardingModel+Steps.swift`.
@MainActor
final class SBOnboardingModel: ObservableObject {
  enum CaptureSelection: Equatable {
    case onlyDuringMeetings
    case continuous

    var systemAudioCaptureMode: AssistantSettings.SystemAudioCaptureMode {
      switch self {
      case .onlyDuringMeetings: .onlyDuringMeetings
      case .continuous: .always
      }
    }

    var capturesWithoutActiveMeeting: Bool {
      self == .continuous
    }
  }

  static let defaultCaptureSelection: CaptureSelection = .onlyDuringMeetings

  enum Step: Int, CaseIterable {
    case promise = 0
    case name = 1
    case howHeard = 2
    case language = 3
    // Raw value 4 belonged to the retired role step. Keep every subsequent raw
    // value stable so a persisted in-progress setup does not resume at the wrong
    // stage after upgrading.
    case mic = 5
    case systemAudio = 6
    case screen = 7
    case accessibility = 8
    case shortcutOpen = 9
    case shortcutTalk = 10
    case screenDemo = 11
    case capture = 12

    var next: Step? {
      guard let index = Self.allCases.firstIndex(of: self) else { return nil }
      let nextIndex = Self.allCases.index(after: index)
      return nextIndex < Self.allCases.endIndex ? Self.allCases[nextIndex] : nil
    }

    var previous: Step? {
      guard let index = Self.allCases.firstIndex(of: self), index > Self.allCases.startIndex else { return nil }
      return Self.allCases[Self.allCases.index(before: index)]
    }

    static func resumeTarget(forPersistedRawValue rawValue: Int) -> Step? {
      if rawValue == 4 { return .mic }
      return Step(rawValue: rawValue)
    }
  }

  /// "How did you hear about Omi?" options (mirrors the legacy step).
  static let howHeardSources = [
    "Social media", "YouTube", "Friend", "Search engine", "AI chat", "Podcast", "Colleague", "Product Hunt", "Other",
  ]

  struct Msg: Identifiable {
    let id = UUID()
    let isOmi: Bool
    var text: String
  }

  enum PermState: Equatable { case ask, waiting, on }

  enum PermissionEffect: Equatable {
    case checked(String)
    case requested(String)
    case granted(String)
    case advanced(from: Step, to: Step)
    case primedScreenCapture
  }

  @Published var step: Step = .promise
  @Published var thread: [Msg] = []
  /// The current Omi message streaming in (nil once committed).
  @Published var streamingText: String?
  @Published var typing = false
  @Published var showWidget = false

  // Per-step answers / state
  @Published var nameDraft = ""
  @Published var languageDraft = ""
  @Published private(set) var languageIsDetectedFromMac = false
  @Published var languageName: String?
  @Published var howHeard: String?

  // Permissions
  @Published var micState: PermState = .ask
  @Published var sysState: PermState = .ask
  @Published var scrState: PermState = .ask  // screen recording
  @Published var accState: PermState = .ask  // accessibility

  /// One-shot guard: fire a single throwaway ScreenCaptureKit capture to surface
  /// the "bypass the private window picker" consent in-context once Screen
  /// Recording is granted, so the live screen demo doesn't hit that prompt.
  var didPrimeScreenCapture = false

  // Summon shortcut
  @Published var shortcutTokens: [String] = []
  @Published var shortcutPicked = false
  @Published var shortcutPressed = false
  /// The chosen shortcut + which mechanism it uses (key hotkey vs modifier-hold).
  var chosenShortcut: ShortcutSettings.KeyboardShortcut?
  var chosenShortcutIsPTT = false
  /// Each shortcut stage keeps its own choice so stepping back does not make a
  /// user re-select a key they already confirmed.
  var openShortcutSelection: ShortcutSettings.KeyboardShortcut?
  var talkShortcutSelection: ShortcutSettings.KeyboardShortcut?
  var shortcutMonitors: [Any] = []
  /// Main menu stashed while the shortcut step's key monitor is armed (menu key
  /// equivalents like ⌘O would otherwise swallow the press before we see it).
  var savedMainMenu: NSMenu?

  // Screen + voice demo
  @Published var screenThings: [String] = []
  @Published var screenDemoLoading = false
  @Published var voiceHeard = false
  @Published var voiceAnswer: String?
  /// True once Omi has actually answered the demo question (the notch shows a
  /// response). The screen-demo Continue button stays hidden until then, so the
  /// user can't skip past before seeing the "fun part" work.
  @Published var screenDemoDone = false
  /// The hold-to-talk demo is armed only after the bridge has initialized its
  /// kernel context. Showing the chord sooner invites a first PTT turn while its
  /// only response route is still cold.
  @Published var screenDemoPTTReady = false
  /// Bridge startup can fail before an authenticated response route exists. In
  /// that state, leave PTT unarmed and offer an explicit retry or skip instead
  /// of presenting a shortcut which cannot answer.
  @Published var screenDemoPTTUnavailable = false
  var voiceCancellable: AnyCancellable?
  var voiceTimeout: Task<Void, Never>?
  var screenDemoSetupTask: Task<Void, Never>?

  unowned let appState: AppState
  let chatProvider: ChatProvider
  private let acquisitionSourceRecorder: OnboardingAcquisitionSourceRecorder
  private let nameWriter: @MainActor (String, String?, RuntimeOwnerAuthorizationSnapshot?) async -> Void
  private let languageWriter: @MainActor ([String]) -> Void
  private let stepResolver: (@MainActor (Step) -> Step)?
  let permissionRefresher: (@MainActor (String) -> Void)?
  let permissionRequester: (@MainActor (String) -> Void)?
  let permissionGranted: (@MainActor (String) -> Bool)?
  let systemAudioPrimer: @MainActor (AppState) async -> Bool
  let screenCapturePrimer: @MainActor () -> Void
  let permissionEffectRecorder: @MainActor (PermissionEffect) -> Void
  private let exitExecutorOverride: OnboardingExitExecutor?
  /// Firebase name writes are serialized. Revisiting the question never lets an
  /// earlier request finish after the user's revision.
  private let answerWriteGate = OnboardingAnswerWriteGate()
  private let onComplete: (@MainActor @Sendable () -> Void)?
  private var exitStarted = false
  var streamTask: Task<Void, Never>?
  /// Permission-grant pollers, one per permission key. Keyed so requesting a
  /// second permission (the meetings "both" mic+system-audio step) never cancels
  /// a still-running poll for the first and strands it on "macOS…".
  var pollTasks: [String: Task<Void, Never>] = [:]
  /// Observes late-arriving names (Apple sends the name only on first auth;
  /// otherwise it's fetched from the backend after sign-in). `givenName` is plain
  /// UserDefaults, not observable, so without this a name landing after the name
  /// step already streamed would never fill in.
  /// `nonisolated(unsafe)` so the nonisolated `deinit` can remove it — the token is
  /// only ever written on the main actor and `removeObserver` is thread-safe.
  nonisolated(unsafe) private var nameObserver: NSObjectProtocol?

  init(
    appState: AppState,
    chatProvider: ChatProvider,
    acquisitionSourceRecorder: OnboardingAcquisitionSourceRecorder = OnboardingAcquisitionSourceRecorder(),
    nameWriter: @escaping @MainActor (String, String?, RuntimeOwnerAuthorizationSnapshot?) async -> Void = {
      name, expectedOwnerID, authorizationSnapshot in
      await AuthService.shared.updateGivenName(
        name,
        expectedOwnerID: expectedOwnerID,
        authorizationSnapshot: authorizationSnapshot)
    },
    languageWriter: @escaping @MainActor ([String]) -> Void = {
      AssistantSettings.shared.voiceLanguages = $0
    },
    stepResolver: (@MainActor (Step) -> Step)? = nil,
    permissionRefresher: (@MainActor (String) -> Void)? = nil,
    permissionRequester: (@MainActor (String) -> Void)? = nil,
    permissionGranted: (@MainActor (String) -> Bool)? = nil,
    systemAudioPrimer: @escaping @MainActor (AppState) async -> Bool = {
      await $0.primeSystemAudioPermission()
    },
    screenCapturePrimer: @escaping @MainActor () -> Void = {
      if #available(macOS 14.0, *) {
        Task.detached { await ScreenCaptureService.primeCaptureConsent() }
      }
    },
    permissionEffectRecorder: @escaping @MainActor (PermissionEffect) -> Void = { _ in },
    exitExecutor: OnboardingExitExecutor? = nil,
    onComplete: (@MainActor @Sendable () -> Void)?
  ) {
    self.appState = appState
    self.chatProvider = chatProvider
    self.acquisitionSourceRecorder = acquisitionSourceRecorder
    self.nameWriter = nameWriter
    self.languageWriter = languageWriter
    self.stepResolver = stepResolver
    self.permissionRefresher = permissionRefresher
    self.permissionRequester = permissionRequester
    self.permissionGranted = permissionGranted
    self.systemAudioPrimer = systemAudioPrimer
    self.screenCapturePrimer = screenCapturePrimer
    self.permissionEffectRecorder = permissionEffectRecorder
    self.exitExecutorOverride = exitExecutor
    self.onComplete = onComplete
    // Isolate any onboarding chat/voice turns to the throwaway `.onboarding()`
    // journal surface so they never pollute the real Chat tab. Cleared on
    // complete()/skip(), after which the Chat tab reloads the clean default surface.
    chatProvider.beginOnboardingJournal()
    // Detect the user's real name automatically (mirrors the legacy paged intro):
    // seed the editable field from what we already know, kick a backend fetch if we
    // don't have it yet, and adopt an async arrival — so onboarding greets by name
    // instead of "friend"/blank (regression from the SB redesign; see #9919).
    let known = AuthService.shared.givenName.trimmingCharacters(in: .whitespaces)
    if !known.isEmpty { nameDraft = known }
    AuthService.shared.loadNameFromFirebaseIfNeeded()
    nameObserver = NotificationCenter.default.addObserver(
      forName: .authNameDidUpdate, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.adoptAsyncName() }
    }
  }

  deinit {
    if let nameObserver { NotificationCenter.default.removeObserver(nameObserver) }
  }

  /// Adopt a name that landed after init — but only fill an empty field, never
  /// overwrite what the user has typed.
  private func adoptAsyncName() {
    let resolved = AuthService.shared.givenName.trimmingCharacters(in: .whitespaces)
    guard !resolved.isEmpty, nameDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    nameDraft = resolved
  }

  // MARK: copy

  func message(for step: Step) -> String {
    let name = displayName
    switch step {
    case .promise:
      return
        "Hey, I'm Omi, your second brain. I hear your conversations, remember everything, and handle the follow-ups. Three quick things:"
    case .name: return "What should I call you?"
    case .howHeard: return "Quick one. How did you hear about Omi?"
    case .language:
      return SBOnboardingLanguageCopy.question
    case .mic:
      return "Let's give me senses. First, your microphone, so I hear your side of a conversation."
    case .systemAudio:
      return "Now system audio, so I hear the other side too: Zoom, Meet, calls."
    case .screen:
      return "Let me see your screen, so I can help with whatever you're looking at."
    case .accessibility:
      return
        "Turn on Accessibility so your global push-to-talk shortcut works, and Rewind and Focus can target the exact window you're using."
    case .shortcutOpen:
      return "How do you want to open me? Just press one of these to set it."
    case .shortcutTalk:
      return "And to talk to me, hands-free? Just hold one of these and say something."
    case .screenDemo:
      return "Here's the fun part."
    case .capture:
      return
        "You're all set, \(name). One last thing: should I listen all the time, or only during your meetings?"
    }
  }

  var displayName: String {
    let n = nameDraft.trimmingCharacters(in: .whitespaces)
    let stored = AuthService.shared.givenName.trimmingCharacters(in: .whitespaces)
    if !n.isEmpty { return n.components(separatedBy: " ").first ?? n }
    if !stored.isEmpty { return stored }
    return "friend"
  }

  // MARK: lifecycle

  /// Persisted so quitting mid-onboarding (e.g. stepping away to grant a permission
  /// in System Settings) resumes where you left off instead of restarting.
  static let resumeStepKey = "sbOnboardingResumeStep"

  func begin() {
    guard thread.isEmpty && streamingText == nil else { return }
    // Re-hydrate the editable drafts from what was already saved, so stepping
    // back to (or resuming at) name/language shows the prior answer instead
    // of an empty field.
    rehydrateDrafts()
    // Resume where the user left off. Their earlier answers (name, language, role)
    // were already saved to the backend/settings, so we just re-enter at the saved
    // step; each permission step re-checks its grant on appear, so a permission
    // granted before the quit shows ✓ rather than prompting again.
    let savedRaw = UserDefaults.standard.integer(forKey: Self.resumeStepKey)
    recordSetupStateDisagreementAtRead(savedRaw: savedRaw)
    if savedRaw > Step.promise.rawValue, let resumed = Step.resumeTarget(forPersistedRawValue: savedRaw) {
      // Skip a resumed permission step the user granted while away.
      let target = stepResolver?(resumed) ?? firstUnaskedStep(from: resumed)
      step = target
      streamMessage(for: target)
      return
    }
    streamMessage(for: .promise)
  }

  /// Detection only: the existing completion flag remains the UI gate. These
  /// bounded signals reveal when that gate says setup is complete while the SB
  /// stage, persisted resume state, or setup journal still says it is active.
  private func recordSetupStateDisagreementAtRead(savedRaw: Int) {
    let hasPersistedResume =
      savedRaw > Step.promise.rawValue && Step.resumeTarget(forPersistedRawValue: savedRaw) != nil
    let resolution = OnboardingSetupAuthorityPolicy.resolve(
      hasCompletedOnboarding: appState.hasCompletedOnboarding,
      hasActiveStage: true,
      hasPersistedResume: hasPersistedResume,
      hasActiveJournal: chatProvider.isOnboarding)
    for disagreement in resolution.disagreements {
      DesktopDiagnosticsManager.shared.recordStateAuthoritySignal(
        seam: .onboardingSetupState,
        from: disagreement.source.rawValue,
        to: disagreement.target.rawValue,
        direction: disagreement.direction)
    }
  }

  func streamMessage(for step: Step) {
    streamTask?.cancel()
    showWidget = false
    typing = true
    let full = message(for: step)
    streamTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 700_000_000)
      guard let self, !Task.isCancelled else { return }
      self.typing = false
      self.streamingText = "▍"
      let words = full.split(separator: " ").map(String.init)
      var i = 0
      while i < words.count {
        i += 1 + Int.random(in: 0...1)
        let shown = words.prefix(min(i, words.count)).joined(separator: " ")
        if i < words.count {
          self.streamingText = shown + " ▍"
        } else {
          self.streamingText = full
        }
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: UInt64((55 + Int.random(in: 0...95)) * 1_000_000))
      }
      guard !Task.isCancelled else { return }
      self.thread.append(Msg(isOmi: true, text: full))
      self.streamingText = nil
      self.showWidget = true
      self.onStepShown(step)
    }
  }

  /// Hook fired right after a step's message finishes streaming and its widget
  /// appears — used to kick off per-step live work (screen capture, demo setup).
  private func onStepShown(_ step: Step) {
    switch step {
    case .language: prefillDetectedLanguage()
    case .mic: precheckPerm("microphone")
    case .systemAudio: precheckPerm("system_audio")
    case .screen: precheckPerm("screen_recording")
    case .accessibility: precheckPerm("accessibility")
    case .shortcutOpen, .shortcutTalk: armShortcutSummon()
    case .screenDemo: startScreenDemo()
    default: break
    }
  }

  func advance(userAnswer: String?, to next: Step) {
    if let userAnswer, !userAnswer.isEmpty {
      thread.append(Msg(isOmi: false, text: userAnswer))
    }
    teardownStep(step)
    // Don't ask for a permission the user has already granted — skip straight to
    // the first step that still needs an answer.
    let target = stepResolver?(next) ?? firstUnaskedStep(from: next)
    step = target
    UserDefaults.standard.set(target.rawValue, forKey: Self.resumeStepKey)
    streamMessage(for: target)
  }

  /// Return to the immediately preceding onboarding stage without discarding
  /// any answer the user already supplied. The conversational transcript stays
  /// intact; the re-rendered widget is the editable source of truth for that
  /// stage, so a user can revise (for example) Student to Founder.
  func goBack() {
    guard let previous = step.previous else { return }
    teardownStep(step)
    cancelPermissionPollForCurrentStep()
    rehydrateDrafts()
    step = previous
    UserDefaults.standard.set(previous.rawValue, forKey: Self.resumeStepKey)
    streamMessage(for: previous)
  }

  var canGoBack: Bool {
    step != .promise
  }

  /// Tear down any live monitors/tasks a step installed before leaving it.
  private func teardownStep(_ step: Step) {
    switch step {
    case .shortcutOpen, .shortcutTalk: disarmShortcutSummon()
    case .screenDemo: teardownVoiceDemo()
    default: break
    }
  }

  /// A permission poll is scoped to the page that requested it. If Back leaves
  /// that page while macOS is still open, stop the stale poll so a late grant
  /// cannot overwrite the newly displayed page's state. The system grant itself
  /// is still observed if the user returns to this page.
  private func cancelPermissionPollForCurrentStep() {
    guard let key = permissionKey(for: step) else { return }
    pollTasks[key]?.cancel()
    pollTasks[key] = nil
    if permState(key) == .waiting {
      resetPermToAsk(key)
    }
  }

  /// Re-fill the editable drafts from already-saved answers so revisiting (via
  /// Back) or resuming a name/language step shows the prior value, not an
  /// empty field. Only fills empties — never clobbers in-progress typing.
  private func rehydrateDrafts() {
    if nameDraft.isEmpty {
      let n = AuthService.shared.givenName.trimmingCharacters(in: .whitespaces)
      if !n.isEmpty { nameDraft = n }
    }
    if howHeard == nil {
      let saved = UserDefaults.standard.string(forKey: DefaultsKey.onboardingHowDidYouHearSource)
      if let saved, !saved.isEmpty { howHeard = saved }
    }
    if languageDraft.isEmpty, languageName == nil, let code = AssistantSettings.shared.voiceLanguages.first,
      let match = AssistantSettings.supportedLanguages.first(where: { $0.code == code })
    {
      languageDraft = match.name
    }
  }

  // MARK: promise / name / language

  func answerPromise() { advance(userAnswer: "Set me up", to: .name) }

  func answerName() {
    let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    let expectedOwnerID = RuntimeOwnerIdentity.currentOwnerId()
    let authorizationSnapshot = expectedOwnerID.flatMap {
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: $0)
    }
    answerWriteGate.enqueue { [nameWriter, trimmed] in
      await nameWriter(trimmed, expectedOwnerID, authorizationSnapshot)
    }
    advance(userAnswer: trimmed, to: .howHeard)
  }

  func waitForPendingNameWrite() async {
    await answerWriteGate.waitForIdle()
  }

  /// Record the acquisition source locally and in analytics, then move on.
  func pickHowHeard(_ source: String) {
    howHeard = source
    acquisitionSourceRecorder.record(source)
    advance(userAnswer: source, to: .language)
  }

  /// Set the user's spoken language locally (single-primary) and advance.
  func pickLanguage(code: String, name: String) {
    languageName = name
    languageDraft = name
    languageIsDetectedFromMac = false
    languageWriter([code])
    advance(userAnswer: name, to: .mic)
  }

  /// Auto-detect the Mac's language and pre-fill it so the picker defaults to it
  /// (the user can still type to change). Only fills an empty field once.
  func prefillDetectedLanguage() {
    let raw = Locale.current.language.languageCode?.identifier ?? Locale.preferredLanguages.first ?? "en"
    prefillDetectedLanguage(from: raw)
  }

  /// Records that the draft came from the Mac locale, rather than a saved or
  /// fallback language, so the UI can accurately disclose its source.
  func prefillDetectedLanguage(from raw: String) {
    guard languageDraft.isEmpty, languageName == nil else { return }
    let code = AssistantSettings.normalizeTranscriptionLanguageCode(raw)
    if let match = AssistantSettings.supportedLanguages.first(where: { $0.code == code }) {
      languageDraft = match.name
      languageIsDetectedFromMac = true
    }
  }

  func answerLanguageText() {
    let raw = languageDraft.trimmingCharacters(in: .whitespaces)
    guard !raw.isEmpty else { return }
    let code = AssistantSettings.normalizeTranscriptionLanguageCode(raw)
    let name = AssistantSettings.supportedLanguages.first { $0.code == code }?.name ?? raw
    pickLanguage(code: code, name: name)
  }

  // MARK: capture choice → completes onboarding

  func capture(_ selection: CaptureSelection) {
    guard !exitStarted else { return }
    exitStarted = true
    teardownAll()
    let executor = exitExecutorOverride ?? makeLiveExitExecutor()
    executor.execute(OnboardingExitPolicy.plan(for: .completed(selection)), onComplete: onComplete)
  }

  /// Skip the rest of onboarding and land on a neutral Home. Capture, monitoring,
  /// launch at login, and the completion opener remain off until the user enables
  /// them later.
  func skip() {
    guard !exitStarted else { return }
    exitStarted = true
    teardownAll()
    let executor = exitExecutorOverride ?? makeLiveExitExecutor()
    executor.execute(OnboardingExitPolicy.plan(for: .skipped), onComplete: onComplete)
  }

  private func makeLiveExitExecutor() -> OnboardingExitExecutor {
    OnboardingExitExecutor(
      effects: .init(
        recordAnalytics: { AnalyticsManager.shared.onboardingExit($0) },
        persistOutcome: { OnboardingExitPersistence.persist($0) },
        setTranscriptionIntent: { AssistantSettings.shared.transcriptionEnabled = $0 },
        startTranscriptionSession: { [appState] in
          Task { @MainActor in
            appState.startTranscription()
            await appState.reconcileCapture()
          }
        },
        stopTranscriptionSession: { [appState] in appState.stopTranscription() },
        setScreenAnalysisIntent: { AssistantSettings.shared.screenAnalysisEnabled = $0 },
        startScreenMonitoring: {
          let plugin = ProactiveAssistantsPlugin.shared
          plugin.refreshScreenRecordingPermission()
          guard
            OnboardingScreenMonitoringStartPolicy.shouldStart(
              intentEnabled: AssistantSettings.shared.screenAnalysisEnabled,
              isPaywalled: AppState.isPaywalledEffective,
              keysAvailable: APIKeyService.keysAvailable,
              permissionGranted: plugin.hasScreenRecordingPermission,
              isMonitoring: plugin.isMonitoring)
          else { return }
          plugin.startMonitoring { _, _ in }
        },
        stopScreenMonitoring: { ProactiveAssistantsPlugin.shared.stopMonitoring() },
        requestLaunchAtLogin: { enabled in
          LaunchAtLoginIntentPolicy.apply(
            enabled ? .onboardingCompletion : .onboardingSkip,
            setEnabled: { LaunchAtLoginManager.shared.setEnabled($0) },
            report: { enabled, source in
              AnalyticsManager.shared.launchAtLoginChanged(enabled: enabled, source: source)
            })
        },
        setJustCompleted: { UserDefaults.standard.set($0, forKey: .onboardingJustCompleted) },
        prepareMainChat: { [chatProvider] in
          chatProvider.stopAgent(owner: .mainChat)
          chatProvider.isOnboarding = false
          ChatDraftStore.shared.clear(.onboardingMain)
          ChatDraftStore.shared.clear(.onboardingFloating)
        },
        presentOpener: { [chatProvider] in chatProvider.presentOnboardingOpener() },
        clearResumeState: { UserDefaults.standard.removeObject(forKey: Self.resumeStepKey) },
        finishJournal: { [chatProvider] in await chatProvider.finishOnboardingJournal() },
        publishCompletion: { [appState] in appState.hasCompletedOnboarding = true },
        setSystemAudioCaptureMode: { AssistantSettings.shared.systemAudioCaptureMode = $0 }))
  }

  /// Cancel every live task/monitor this model owns. Safe to call repeatedly.
  private func teardownAll() {
    streamTask?.cancel()
    for pollTask in pollTasks.values {
      pollTask.cancel()
    }
    pollTasks.removeAll()
    disarmShortcutSummon()
    teardownVoiceDemo()
  }
}
