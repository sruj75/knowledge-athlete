/// One reveal sequence serves explicit and authorized proactive conversations.
/// The caller retains account/speech admission; passive requests retain snooze.
enum FloatingConversationOpening {
  @discardableResult
  static func present(
    request: FloatingBarPresentationRequest, isSnoozed: Bool,
    cancelPendingDismiss: () -> Void, reveal: () -> Void, openConversation: () -> Void
  ) -> Bool {
    guard FloatingBarPresentationPolicy.shouldPresent(request: request, isSnoozed: isSnoozed) else {
      return false
    }
    cancelPendingDismiss()
    reveal()
    openConversation()
    return true
  }
}

/// Explicit hide/snooze ends active capture before its visible indicator leaves.
/// Internal temporary retraction and focus loss do not use this boundary.
enum FloatingConversationDismissal {
  static func perform(
    isConversationOpen: Bool, closeConversation: () -> Void, hideSurface: () -> Void
  ) {
    if isConversationOpen { closeConversation() }
    hideSurface()
  }
}

extension FloatingControlBarManager {
  /// Both initiators reveal the existing notch/chat surface without changing
  /// the user's saved visibility preference. Speech/account admission remains
  /// with the conversation controller before this presentation-only operation.
  @discardableResult
  func presentConversationOpening(request: FloatingBarPresentationRequest) -> Bool {
    guard let window else { return false }
    return FloatingConversationOpening.present(
      request: request, isSnoozed: isSnoozed,
      cancelPendingDismiss: { window.cancelPendingDismiss() },
      reveal: { self.present(request, preferenceMutation: .preserve) },
      openConversation: { window.showAIConversation() })
  }
}

extension FloatingControlBarManager {
  /// Explicitly hiding the bar also ends its active microphone conversation.
  /// Internal temporary retraction keeps its separate presentation-only path.
  func hide() {
    FloatingConversationDismissal.perform(
      isConversationOpen: ConversationVoiceController.shared.isOpen,
      closeConversation: { ConversationVoiceController.shared.close() },
      hideSurface: { self.retract(preferenceMutation: .setEnabled(false)) })
  }
}
