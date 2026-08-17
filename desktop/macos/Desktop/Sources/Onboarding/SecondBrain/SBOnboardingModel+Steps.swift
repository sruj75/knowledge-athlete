import AppKit
import Combine
import CoreGraphics
import Foundation

// MARK: - Permissions (one at a time)

extension SBOnboardingModel {
  func requestPerm(_ key: String) {
    // The user may have changed a grant in System Settings while this step was
    // onscreen. Re-check it before opening another pane or asking macOS again.
    refreshPermCheck(key)
    if isGranted(key) {
      setPermOn(key)
      autoAdvanceIfCurrent(key)
      return
    }

    switch key {
    case "microphone":
      micState = .waiting
      appState.requestMicrophonePermission()
      pollPermission(key)
    case "system_audio":
      // A Core Audio process tap has its own consent in addition to Screen
      // Recording TCC. Wait for Screen Recording, then reconcile a real tap
      // attempt before marking this permission granted.
      sysState = .waiting
      if !appState.hasScreenRecordingPermission {
        ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
      }
      pollPermission(key)
    case "screen_recording":
      scrState = .waiting
      ScreenCaptureService.requestScreenRecordingAccessAndOpenSettings()
      pollPermission(key)
    case "accessibility":
      accState = .waiting
      appState.triggerAccessibilityPermission()
      pollPermission(key)
    default: break
    }
  }

  func pollPermission(_ key: String) {
    // Cancel only this key's prior poll — never a sibling permission's, so the
    // "both" mic+system-audio step can poll two grants at once.
    pollTasks[key]?.cancel()

    if key == "system_audio" {
      pollSystemAudioPermission()
      return
    }

    pollTasks[key] = Task { [weak self] in
      for _ in 0..<40 {  // ~20s
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let self, !Task.isCancelled else { return }
        self.refreshPermCheck(key)
        if self.isGranted(key) {
          self.setPermOn(key)
          // Auto-advance once the grant lands — the user shouldn't have to click
          // Continue after granting. Brief pause so the ✓ is visible, then only
          // advance if they're still on this permission's step (a late poll for a
          // step already left must never yank the flow forward).
          try? await Task.sleep(nanoseconds: 600_000_000)
          guard !Task.isCancelled else { return }
          self.autoAdvanceIfCurrent(key)
          return
        }
      }
      // Timed out without a grant. Accessibility routinely exceeds 20s (open
      // System Settings → authenticate → toggle), so re-arm the Allow button
      // instead of stranding the row on "macOS…" forever.
      guard let self, !Task.isCancelled else { return }
      self.resetPermToAsk(key)
    }
  }

  /// Screen Recording TCC is only a prerequisite for system audio. The
  /// authoritative grant is a successful Core Audio tap attempt.
  private func pollSystemAudioPermission() {
    // A precheck and an Allow click can race to start this poll. Preserve one
    // authoritative consent attempt so an older task cannot advance the flow
    // after the replacement has already reconciled a newer result.
    pollTasks["system_audio"]?.cancel()
    pollTasks["system_audio"] = Task { [weak self] in
      for _ in 0..<40 {  // ~20s
        guard let self, !Task.isCancelled else { return }
        // Skipping this step is an explicit choice not to surface its consent.
        // Never let a late Screen Recording grant trigger the modal elsewhere.
        guard self.step == .systemAudio else { return }
        self.appState.checkScreenRecordingPermission()
        if self.appState.hasScreenRecordingPermission {
          // A real process-tap attempt is the only truthful preflight for
          // system audio. It completes without another prompt when consent was
          // already granted, so reconcile it before asking the user again.
          let granted = await self.appState.primeSystemAudioPermission()
          guard !Task.isCancelled else { return }
          guard granted else {
            self.resetPermToAsk("system_audio")
            return
          }

          self.setPermOn("system_audio")
          try? await Task.sleep(nanoseconds: 600_000_000)
          guard !Task.isCancelled else { return }
          self.autoAdvanceIfCurrent("system_audio")
          return
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
      }

      guard let self, !Task.isCancelled else { return }
      self.resetPermToAsk("system_audio")
    }
  }

  /// Re-probe a single permission (each check writes the matching AppState flag).
  private func refreshPermCheck(_ key: String) {
    switch key {
    case "microphone": appState.checkMicrophonePermission()
    case "system_audio":
      appState.checkScreenRecordingPermission()
      appState.checkSystemAudioPermission()
    case "screen_recording": appState.checkScreenRecordingPermission()
    case "accessibility": appState.checkAccessibilityPermission()
    default: appState.checkAllPermissions()
    }
  }

  /// When a permission step appears, reflect a grant the user already has so it
  /// shows ✓ instead of an Allow button they'd tap for nothing.
  func precheckPerm(_ key: String) {
    refreshPermCheck(key)
    if isGranted(key) {
      setPermOn(key)
    } else if key == "system_audio", appState.hasScreenRecordingPermission,
      appState.systemAudioPermissionStatus == .unknown
    {
      // Already holding Screen Recording must not skip this separate consent.
      // Prime while its own onboarding step is visible and reconcile the result.
      sysState = .waiting
      pollSystemAudioPermission()
    }
  }

  /// Fire a single throwaway ScreenCaptureKit capture the first time Screen
  /// Recording is confirmed granted during onboarding, so macOS surfaces the
  /// "bypass the private window picker" consent here — while the user is already
  /// granting screen access — instead of mid-question during the live screen demo
  /// (the exact spot users hit it). See `ScreenCaptureService.primeCaptureConsent`.
  func primeScreenCaptureConsentIfNeeded() {
    guard !didPrimeScreenCapture else { return }
    didPrimeScreenCapture = true
    if #available(macOS 14.0, *) {
      Task.detached { await ScreenCaptureService.primeCaptureConsent() }
    }
  }

  func isGranted(_ key: String) -> Bool {
    switch key {
    case "microphone": return appState.hasMicrophonePermission
    case "system_audio":
      return appState.hasSystemAudioPermission || appState.systemAudioPermissionStatus == .unsupported
    case "screen_recording": return appState.hasScreenRecordingPermission
    case "accessibility": return appState.hasAccessibilityPermission && !appState.isAccessibilityBroken
    default: return false
    }
  }

  func setPermOn(_ key: String) {
    switch key {
    case "microphone": micState = .on
    case "system_audio":
      sysState = .on
      // System audio shares Screen Recording TCC; once it's on, the ScreenCaptureKit
      // capture consent can be primed so the demo doesn't surface it later.
      primeScreenCaptureConsentIfNeeded()
    case "screen_recording":
      scrState = .on
      primeScreenCaptureConsentIfNeeded()
    case "accessibility": accState = .on
    default: break
    }
  }

  /// Return a still-`.waiting` row to `.ask` so its Allow button reappears after
  /// the poll times out without a grant (a later grant re-triggers the poll).
  func resetPermToAsk(_ key: String) {
    switch key {
    case "microphone": micState = .ask
    case "system_audio": sysState = .ask
    case "screen_recording": scrState = .ask
    case "accessibility": accState = .ask
    default: break
    }
  }

  func permState(_ key: String) -> PermState {
    switch key {
    case "microphone": return micState
    case "system_audio": return sysState
    case "screen_recording": return scrState
    case "accessibility": return accState
    default: return .ask
    }
  }

  func answerMic() { advance(userAnswer: micState == .on ? "Allowed" : "Skip", to: .systemAudio) }
  func answerSystemAudio() { advance(userAnswer: sysState == .on ? "Allowed" : "Skip", to: .screen) }
  func answerScreen() { advance(userAnswer: scrState == .on ? "Allowed" : "Skip", to: .accessibility) }
  func answerAccessibility() { advance(userAnswer: accState == .on ? "Allowed" : "Skip", to: .shortcutOpen) }

  /// Advance past a permission step automatically once its grant lands — but only
  /// when the user is still ON that step, so a late poll never skips a step they've
  /// already moved past.
  func autoAdvanceIfCurrent(_ key: String) {
    guard permissionKey(for: step) == key, permState(key) == .on else { return }
    switch step {
    case .mic: answerMic()
    case .systemAudio: answerSystemAudio()
    case .screen: answerScreen()
    case .accessibility: answerAccessibility()
    default: break
    }
  }

  /// The permission key a step gates on, or nil for non-permission steps.
  func permissionKey(for step: Step) -> String? {
    switch step {
    case .mic: return "microphone"
    case .systemAudio: return "system_audio"
    case .screen: return "screen_recording"
    case .accessibility: return "accessibility"
    default: return nil
    }
  }

  /// Starting at `target`, skip past any permission step whose permission is
  /// already granted — so the user is never asked for something they've already
  /// given (matches the legacy onboarding's live permission detection). Refreshes
  /// each permission's TCC state before deciding, and reflects the grant so the
  /// row is already ✓ if we ever land on it. Returns the first step to actually ask.
  func firstUnaskedStep(from target: Step) -> Step {
    var step = target
    while let key = permissionKey(for: step) {
      refreshPermCheck(key)
      guard isGranted(key), let next = step.next else { break }
      setPermOn(key)
      step = next
    }
    return step
  }
}

// MARK: - Summon shortcut (pick → press → notch)

extension SBOnboardingModel {
  /// Open-Omi options (tap to open the window).
  var openShortcutOptions: [(id: String, shortcut: ShortcutSettings.KeyboardShortcut, sub: String)] {
    [
      // ⌘O is registered as its own always-on Carbon hotkey (GlobalShortcutManager
      // .registerCommandO), so it reliably summons Omi globally — the natural,
      // expected "open" chord. Offer it first. (⌘J was dropped: onboarding testers
      // read it as arbitrary/random with no mnemonic, unlike ⌘O = "open".)
      ("cmdO", ShortcutSettings.askOmiCommandOShortcut, "tap to open"),
      ("cmdReturn", ShortcutSettings.askOmiCommandReturnShortcut, "tap to open"),
    ]
  }

  /// Push-to-talk options (hold to talk, hands-free).
  var talkShortcutOptions: [(id: String, shortcut: ShortcutSettings.KeyboardShortcut, sub: String)] {
    [
      ("fn", ShortcutSettings.KeyboardShortcut(modifierOnly: .function), "hold to talk"),
      ("opt", ShortcutSettings.KeyboardShortcut(modifierOnly: .option), "hold to talk"),
      ("ctrl", ShortcutSettings.KeyboardShortcut(modifierOnly: .control), "hold to talk"),
    ]
  }

  /// Arm key detection exactly like the legacy OnboardingFloatingBarShortcutStepView:
  /// suspend the live Ask-Omi Carbon hotkey (so pressing it doesn't steal focus or
  /// get swallowed before our monitor sees it) and null the main menu (⌘O/⌘↩ are
  /// NSMenu key equivalents that AppKit dispatches before local monitors). Both are
  /// restored on leave. This is why the earlier attempt's monitor never fired.
  func armShortcutSummon() {
    // Preserve a choice when the user returns with Back. A fresh stage still
    // starts empty, while an already-confirmed shortcut stays visible/editable.
    let rememberedSelection: ShortcutSettings.KeyboardShortcut?
    switch step {
    case .shortcutOpen: rememberedSelection = openShortcutSelection
    case .shortcutTalk: rememberedSelection = talkShortcutSelection
    default: rememberedSelection = nil
    }
    shortcutPicked = rememberedSelection != nil
    shortcutPressed = false
    shortcutTokens = rememberedSelection?.displayTokens ?? []
    chosenShortcut = rememberedSelection
    GlobalShortcutManager.shared.setRegistrationSuspended(true)
    if savedMainMenu == nil { savedMainMenu = NSApp.mainMenu }
    NSApp.mainMenu = nil
    installShortcutMonitors()
  }

  func disarmShortcutSummon() {
    for m in shortcutMonitors { NSEvent.removeMonitor(m) }
    shortcutMonitors.removeAll()
    if let saved = savedMainMenu {
      NSApp.mainMenu = saved
      savedMainMenu = nil
    }
    GlobalShortcutManager.shared.setRegistrationSuspended(false)
  }

  private func installShortcutMonitors() {
    for m in shortcutMonitors { NSEvent.removeMonitor(m) }
    shortcutMonitors.removeAll()
    let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
    // Local monitor fires when the app is key and can consume the event; global
    // monitor fires when another app is focused (it can only observe).
    if let l = NSEvent.addLocalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        let matched = self?.handleShortcutEvent(event) ?? false
        return matched ? nil : event
      })
    {
      shortcutMonitors.append(l)
    }
    if let g = NSEvent.addGlobalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        _ = self?.handleShortcutEvent(event)
      })
    {
      shortcutMonitors.append(g)
    }
  }

  /// The shortcuts offered on the current step — used so the user can just PRESS
  /// any offered combo to auto-select it (no need to click the row first).
  private var currentShortcutCandidates: [ShortcutSettings.KeyboardShortcut] {
    switch step {
    case .shortcutOpen: return openShortcutOptions.map { $0.shortcut }
    case .shortcutTalk: return talkShortcutOptions.map { $0.shortcut }
    default: return []
    }
  }

  private func handleShortcutEvent(_ event: NSEvent) -> Bool {
    guard !shortcutPressed else { return false }
    // If the user already tapped a row, honor that exact pick; otherwise let ANY
    // offered combo select itself on press, so "just press the key" works and the
    // Continue button appears without a separate pick-then-test step.
    let candidates = chosenShortcut.map { [$0] } ?? currentShortcutCandidates
    let isTalk = step == .shortcutTalk
    for sc in candidates {
      let matched: Bool
      switch event.type {
      case .flagsChanged: matched = sc.matchesFlagsChanged(event)  // modifier-only chords (fn, ⌥…)
      case .keyDown: matched = !event.isARepeat && sc.matchesKeyDown(event)  // ⌘O / ⌘↩ / ⌘J
      default: matched = false
      }
      if matched {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if self.chosenShortcut != sc { self.pickShortcut(sc, isTalk: isTalk) }
          self.shortcutPressed = true
        }
        return true
      }
    }
    return false
  }

  /// Pick + persist a shortcut. `isTalk` → push-to-talk chord (held, drives the
  /// voice demo); otherwise the Ask-Omi open hotkey (tapped to open the window).
  func pickShortcut(_ shortcut: ShortcutSettings.KeyboardShortcut, isTalk: Bool) {
    chosenShortcut = shortcut
    chosenShortcutIsPTT = isTalk
    shortcutTokens = shortcut.displayTokens
    shortcutPicked = true
    shortcutPressed = false
    if isTalk {
      talkShortcutSelection = shortcut
      ShortcutSettings.shared.pttShortcut = shortcut
      ShortcutSettings.shared.pttEnabled = true
    } else {
      openShortcutSelection = shortcut
      ShortcutSettings.shared.askOmiShortcut = shortcut
      ShortcutSettings.shared.askOmiEnabled = true
    }
  }

  func answerShortcutOpen() {
    advance(userAnswer: shortcutPressed ? "Works" : (shortcutPicked ? "Set" : "Skip"), to: .shortcutTalk)
  }
  func answerShortcutTalk() {
    advance(userAnswer: shortcutPressed ? "Works" : (shortcutPicked ? "Set" : "Skip"), to: .screenDemo)
  }
}

// MARK: - Screen + voice demo (live: notch visible, screen-aware answer)

extension SBOnboardingModel {
  /// Wire the real floating bar + push-to-talk exactly like the legacy
  /// OnboardingVoiceDemoView: isolate the demo conversation (onboardingFloating
  /// draft + the `.onboarding()` journal surface via `isOnboarding`), force live
  /// transcription, warm the bridge, and SHOW the notch so it stays visible while
  /// the user holds their key and asks about the screen. Screen capture is
  /// attached automatically for screen-aware questions; the answer streams into
  /// the notch, which spins while Omi is thinking.
  func startScreenDemo() {
    screenDemoDone = false
    screenDemoPTTReady = false
    screenDemoPTTUnavailable = false
    FloatingControlBarManager.shared.setup(appState: appState, chatProvider: chatProvider)
    FloatingControlBarManager.shared.barState?.switchAIDraft(to: .onboardingFloating)
    resetFloatingBarConversation()
    ShortcutSettings.shared.pttTranscriptionModeDemoOverride = .live
    screenDemoSetupTask?.cancel()
    screenDemoSetupTask = Task { [weak self] in
      guard let self else { return }
      // Unlike the normal app, onboarding did not have an earlier home-screen
      // warmup. The old order set up PTT first, which made the hub request its
      // kernel context before the bridge existed; the user's first hold then
      // raced that cold start and could end without an answer. Establish the
      // bridge before arming PTT so its first turn has a real response route.
      await self.activateScreenDemoPTTAfterBridgeWarmup(
        warmup: { await self.chatProvider.warmupBridge() },
        activate: { self.activateScreenDemoPTT() }
      )
    }
  }

  /// The screen demo owns PTT only while its stage is still mounted. Keep this
  /// lifecycle fence outside the unstructured task so the same production
  /// boundary can be regression-tested: leaving the stage during a cold bridge
  /// start must not attach fresh event monitors to the next onboarding page.
  func activateScreenDemoPTTAfterBridgeWarmup(
    warmup: @escaping @MainActor () async -> Bool,
    activate: @escaping @MainActor () -> Void
  ) async {
    let bridgeReady = await warmup()
    guard !Task.isCancelled, step == .screenDemo else { return }
    guard bridgeReady else {
      screenDemoPTTUnavailable = true
      return
    }
    activate()
  }

  private func activateScreenDemoPTT() {
    guard step == .screenDemo,
      let bar = FloatingControlBarManager.shared.barState
    else { return }
    PushToTalkManager.shared.setup(barState: bar)
    // Mark the demo done the first time Omi actually answers. Voice answers
    // surface through `voiceProjection`; typed answers use `showingAIResponse`.
    // Drop the current voice projection so re-entering the demo cannot inherit a
    // stale response from a prior turn.
    voiceCancellable = Publishers.Merge(
      bar.$showingAIResponse.filter { $0 }.map { _ in () },
      bar.$voiceProjection.dropFirst().filter { $0.isResponseActive }.map { _ in () }
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.screenDemoDone = true }
    screenDemoPTTReady = true
    FloatingControlBarManager.shared.showForOnboardingDemo()
  }

  private func resetFloatingBarConversation() {
    guard let bar = FloatingControlBarManager.shared.barState else { return }
    bar.showingAIConversation = false
    bar.showingAIResponse = false
    bar.aiInputText = ""
    bar.clearViewport()
  }

  func teardownVoiceDemo() {
    screenDemoSetupTask?.cancel()
    screenDemoSetupTask = nil
    voiceTimeout?.cancel()
    voiceTimeout = nil
    voiceCancellable = nil
    screenDemoDone = false
    screenDemoPTTReady = false
    screenDemoPTTUnavailable = false
    ShortcutSettings.shared.pttTranscriptionModeDemoOverride = nil
    resetFloatingBarConversation()
    PushToTalkManager.shared.cleanup()
    FloatingControlBarManager.shared.hideForOnboardingDemo()
  }

  /// The push-to-talk chord to prompt for the voice demo.
  var voiceChordTokens: [String] {
    let tokens = ShortcutSettings.shared.pttShortcut.displayTokens
    return tokens.isEmpty ? ["fn"] : tokens
  }

  func answerScreenDemo() { advance(userAnswer: "Continue", to: .capture) }
}
