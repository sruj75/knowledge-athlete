import Cocoa
import Combine

/// The existing configurable voice shortcut now toggles a whole conversation.
/// Key release never commits an utterance: speech detection owns that boundary.
@MainActor
final class PushToTalkManager: ObservableObject {
  static let shared = PushToTalkManager()
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var modifierPressed = false
  private var modifierUsedInChord = false

  private init() {}

  func setup(barState: FloatingControlBarState) {
    ConversationVoiceController.shared.setup(barState: barState)
    removeMonitors()
    let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      Task { @MainActor in self?.handle(event) }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      Task { @MainActor in self?.handle(event) }
      return event
    }
  }

  func cleanup() {
    ConversationVoiceController.shared.close()
    removeMonitors()
  }

  func cancelListening() { ConversationVoiceController.shared.close(dismissUI: false) }

  func quiesceForEffectiveOwnerTransition(
    previousOwnerID: String?, cleanupCapability: RuntimeOwnerTransitionCleanupCapability
  ) async {
    guard
      RuntimeOwnerIdentity.authorizesTransitionCleanup(
        cleanupCapability, previousOwnerID: previousOwnerID)
    else { return }
    await ConversationVoiceController.shared.quiesce()
  }

  private func removeMonitors() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    globalMonitor = nil
    localMonitor = nil
    modifierPressed = false
    modifierUsedInChord = false
  }

  private func handle(_ event: NSEvent) {
    guard ShortcutSettings.shared.pttEnabled else { return }
    let shortcut = ShortcutSettings.shared.pttShortcut
    if shortcut.modifierOnly {
      if event.type == .keyDown, modifierPressed { modifierUsedInChord = true }
      guard event.type == .flagsChanged else { return }
      let pressed = shortcut.matchesFlagsChanged(event)
      if pressed, !modifierPressed {
        modifierPressed = true
        modifierUsedInChord = false
      } else if !pressed, modifierPressed {
        modifierPressed = false
        if !modifierUsedInChord { toggle() }
      }
    } else if event.type == .keyDown, !event.isARepeat, shortcut.matchesKeyDown(event) {
      toggle()
    }
  }

  private func toggle() {
    ConversationVoiceController.shared.toggle()
  }
}
