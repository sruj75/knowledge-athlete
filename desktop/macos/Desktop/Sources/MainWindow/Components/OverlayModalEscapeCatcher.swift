import AppKit
import SwiftUI

/// Maps Esc to a dismiss closure for custom overlay modals. These overlays are
/// ZStack layers, not NSWindow sheets, so AppKit gives them no cancel handling,
/// `onExitCommand` needs focus they never receive, and hidden SwiftUI buttons
/// with a cancel key equivalent get culled from key-equivalent dispatch. A
/// local key-down monitor scoped to the hosting window delivers Esc
/// deterministically. Render it only while its overlay is the topmost modal.
struct OverlayModalEscapeCatcher: NSViewRepresentable {
  let action: () -> Void

  func makeNSView(context: Context) -> EscapeCatcherView {
    let view = EscapeCatcherView()
    view.onEscape = action
    return view
  }

  func updateNSView(_ nsView: EscapeCatcherView, context: Context) {
    nsView.onEscape = action
  }

  final class EscapeCatcherView: NSView {
    var onEscape: (() -> Void)?
    private nonisolated(unsafe) var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil {
        installMonitor()
      } else {
        removeMonitor()
      }
    }

    // Never intercept mouse events — this view exists only for the monitor.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func installMonitor() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard
          let self,
          event.keyCode == 53,  // Esc
          let window = self.window,
          event.window === window
        else { return event }
        self.onEscape?()
        // Consume the event — while the overlay is up it owns Esc.
        return nil
      }
    }

    private func removeMonitor() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }

    deinit {
      // Deinitialization is nonisolated. The monitor is main-thread-only,
      // while NSEvent.removeMonitor is safe to invoke from this boundary.
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }
  }
}
