extension DesktopAutomationActionRegistry {
  func registerConversationPresentationPreviewActions() {
    register(
      name: "debug_bar_state",
      summary:
        "Preview conversation visuals: idle|opening|listening|thinking|answering|speaking|reconnecting (synthetic levels)",
      params: ["state", "microphone_level", "playback_level"]
    ) { parameters in
      ConversationPresentationPreview.live.apply(parameters)
    }
  }
}

extension ConversationPresentationPreview {
  fileprivate static let live = ConversationPresentationPreview(
    surface: FloatingConversationPreviewSurface(), monitor: .shared,
    isNonProduction: { AppBuild.isNonProduction })
}

/// This adapter borrows only empty UI chrome. Setup is allowed before onboarding
/// finishes; it binds the existing window without completing onboarding or
/// invoking the conversation controller, capture services, or providers.
@MainActor
private final class FloatingConversationPreviewSurface: ConversationPresentationPreviewSurface {
  private var previousVisibility = false
  private var manager: FloatingControlBarManager { .shared }

  var presentation: ConversationPresentation {
    get { manager.barState?.conversationPresentation ?? .closed }
    set { manager.barState?.setConversationPresentation(newValue) }
  }

  var conversationIsActive: Bool {
    ConversationVoiceController.shared.conversationState != .closed
  }

  var hasProtectedContent: Bool {
    // Typed work and a legacy voice projection do not own the new logical
    // presentation. They must release a stale synthetic snapshot, not keep it.
    guard VoiceTurnCoordinator.shared.activeTurn == nil, ChatProvider.mainInstance?.isSending != true else {
      return true
    }
    let notifications = manager.notificationProjectionSnapshot
    guard notifications.queuedCount == 0, notifications.pendingJournalCount == 0 else { return true }
    guard let state = manager.barState else { return false }
    return state.hasMainConversation || !state.aiInputText.isEmpty || state.currentNotification != nil
  }

  var usesNotchIsland: Bool { manager.barState?.usesNotchIsland ?? false }

  func prepare() -> Bool {
    guard !conversationIsActive, !hasProtectedContent else { return false }
    if manager.window == nil {
      // setup() restores a saved snooze timer. A preview must not start one.
      guard !manager.isSnoozed, let appState = AppState.current, let provider = ChatProvider.mainInstance else {
        return false
      }
      manager.setup(appState: appState, chatProvider: provider)
    }
    guard let state = manager.barState,
      !state.hasVisibleConversation, !state.isVoicePresentationActive,
      !hasProtectedContent
    else { return false }
    // A transient onboarding surface may be visible while the saved bar is
    // disabled. Its owner, not this preview's close animation, must hide it.
    guard !manager.isVisible || manager.isEnabled else { return false }
    previousVisibility = manager.isVisible
    return manager.presentConversationOpening(request: .explicitUserAction)
  }

  func restore() {
    // The preview owns an empty surface; this intent avoids cancelling Chat or
    // the voice controller. Durable visibility/snooze preferences stay untouched.
    manager.window?.closeAIConversation(intent: .voiceHandoff)
    if !previousVisibility { manager.retract(preferenceMutation: .preserve) }
  }
}
