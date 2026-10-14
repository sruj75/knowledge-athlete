import Foundation

enum NotchChromeLayout {
  /// Chat already has loading UI; keep its voice identity mark available for
  /// the whole open conversation without changing the fixed header geometry.
  static func showsThinking(
    isThinking: Bool, isResponseWaiting: Bool, isListening: Bool,
    showingAIConversation: Bool, conversationOpen: Bool
  ) -> Bool {
    (isThinking || isResponseWaiting)
      && (!showingAIConversation || conversationOpen)
      && !isListening
  }

  /// A chat can be restoring or transitioning while the rendered conversation
  /// is already visible. Both states must keep the notch controls pinned;
  /// otherwise the notch controls jump out to the surface edges for
  /// a frame during expansion.
  static func isChatPinned(
    showingAIConversation: Bool,
    hasVisibleConversation: Bool
  ) -> Bool {
    showingAIConversation || hasVisibleConversation
  }

  /// The hover menu and chat surface can grow much wider than the physical
  /// notch. Keep the controls in the notch-width header for the entire
  /// lifecycle so expansion never moves either control away from its
  /// collapsed position.
  static func width(
    chromeWidth: CGFloat,
    expandedWidth: CGFloat,
    switcherProgress: CGFloat,
    isChatPresented: Bool
  ) -> CGFloat {
    // The expanded surface owns the extra width. The header must remain a
    // stable physical-notch anchor whether the row is opening, closing, or
    // transitioning into/restoring chat. Keep the parameters at this seam
    // so tests cover every caller state without duplicating layout policy.
    _ = expandedWidth
    _ = switcherProgress
    _ = isChatPresented
    return chromeWidth
  }
}
