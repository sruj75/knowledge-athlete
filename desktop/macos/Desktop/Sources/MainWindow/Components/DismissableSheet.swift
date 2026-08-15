import AppKit
import OmiTheme
import SwiftUI

// MARK: - Safe Dismiss Button
/// A dismiss button that prevents click-through to underlying views on macOS.
/// Uses onTapGesture with async delay to ensure the click is fully consumed before dismissing.
/// The key is to wait for the full mouse event cycle to complete before triggering dismiss.
struct SafeDismissButton: View {
  let dismiss: DismissAction
  var icon: String = "xmark"
  var showBackground: Bool = true

  @State private var isPressed = false

  var body: some View {
    Image(systemName: icon)
      .scaledFont(size: OmiType.body, weight: .medium)
      .foregroundColor(isPressed ? OmiColors.textTertiary : OmiColors.textSecondary)
      .frame(width: 28, height: 28)
      .background(showBackground ? OmiColors.backgroundSecondary : Color.clear)
      .clipShape(Circle())
      .contentShape(Circle())
      .opacity(isPressed ? 0.7 : 1.0)
      .onTapGesture {
        guard !isPressed else { return }  // Prevent double-tap
        isPressed = true

        let mouseLocation = NSEvent.mouseLocation
        log("DISMISS: Tap gesture fired at mouse position: \(mouseLocation)")

        // Consume the click by resigning first responder
        NSApp.keyWindow?.makeFirstResponder(nil)

        // Post a mouse-up event to ensure any pending click is consumed
        if let window = NSApp.keyWindow {
          let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: window.mouseLocationOutsideOfEventStream,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
          )
          if let event = event {
            window.sendEvent(event)
            log("DISMISS: Sent synthetic mouse-up event")
          }
        }

        // Use async with longer delay to ensure mouse event fully completes
        Task { @MainActor in
          log("DISMISS: Starting 250ms delay before dismiss")
          // Longer delay to ensure mouse-up event is fully processed
          try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
          log("DISMISS: Delay complete, calling dismiss()")
          log("DISMISS: Mouse position before dismiss: \(NSEvent.mouseLocation)")
          dismiss()
          log("DISMISS: dismiss() called")
        }
      }
  }
}

// MARK: - Dismiss Button (Action-based)
/// A dismiss button that takes a closure instead of a DismissAction.
/// Used for overlay-based sheets where the dismiss is controlled externally.
/// A real Button (not a tap gesture) so accessibility exposes it as a labeled
/// "Close" control and keyboard users can reach it.
struct DismissButton: View {
  let action: () -> Void
  var icon: String = "xmark"
  var showBackground: Bool = true
  var accessibilityLabel: String = "Close"

  var body: some View {
    Button {
      log("DISMISS_BUTTON: Activated")

      // Commit any in-progress field editing before tearing the sheet down.
      NSApp.keyWindow?.makeFirstResponder(nil)

      OmiMotion.withGated(.easeOut(duration: 0.2)) {
        action()
      }
    } label: {
      Image(systemName: icon)
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)
        .frame(width: 28, height: 28)
        .background(showBackground ? OmiColors.backgroundSecondary : Color.clear)
        .clipShape(Circle())
        .contentShape(Circle())
    }
    .buttonStyle(DismissButtonPressStyle())
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct DismissButtonPressStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1.0)
  }
}

struct DismissableSheetModifier<SheetContent: View>: ViewModifier {
  @Binding var isPresented: Bool
  let sheetContent: () -> SheetContent

  func body(content: Content) -> some View {
    content
      // The overlay is modal: while it is up, the content underneath must
      // not be reachable by VoiceOver / Full Keyboard Access.
      .accessibilityHidden(isPresented)
      .overlay {
        ZStack {
          if isPresented {
            // Dimmed background that dismisses on tap.
            Color.black.opacity(0.3)
              .ignoresSafeArea()
              .contentShape(Rectangle())
              .onTapGesture {
                log("DISMISSABLE_SHEET: Background tapped, dismissing")
                OmiMotion.withGated(.easeOut(duration: 0.2)) {
                  isPresented = false
                }
              }
              .transition(.opacity)
              .zIndex(0)

            // Force the sheet into a centered full-size overlay so it
            // does not end up clipped or visually hidden behind the scrim.
            sheetContent()
              .background(OmiColors.backgroundPrimary)
              .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius))
              .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
              .transition(.scale(scale: 0.95).combined(with: .opacity))
              .accessibilityAddTraits(.isModal)
              .zIndex(1)

            OverlayModalEscapeCatcher {
              log("DISMISSABLE_SHEET: Escape pressed, dismissing")
              OmiMotion.withGated(.easeOut(duration: 0.2)) {
                isPresented = false
              }
            }
            .zIndex(2)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .omiAnimation(.easeOut(duration: 0.2), value: isPresented)
  }
}

extension View {
  /// Presents a sheet that can be dismissed by clicking outside the content area.
  func dismissableSheet<Content: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    self.modifier(DismissableSheetModifier(isPresented: isPresented, sheetContent: content))
  }

  /// Presents an item-based sheet that can be dismissed by clicking outside the content area.
  func dismissableSheet<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    self.modifier(DismissableSheetItemModifier(item: item, sheetContent: content))
  }
}

/// Item-based version of DismissableSheetModifier for optional item bindings.
struct DismissableSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
  @Binding var item: Item?
  let sheetContent: (Item) -> SheetContent

  func body(content: Content) -> some View {
    content
      // The overlay is modal: while it is up, the content underneath must
      // not be reachable by VoiceOver / Full Keyboard Access.
      .accessibilityHidden(item != nil)
      .overlay {
        ZStack {
          if let presentedItem = item {
            // Dimmed background that dismisses on tap.
            Color.black.opacity(0.3)
              .ignoresSafeArea()
              .contentShape(Rectangle())
              .onTapGesture {
                log("DISMISSABLE_SHEET: Background tapped, dismissing item")
                OmiMotion.withGated(.easeOut(duration: 0.2)) {
                  item = nil
                }
              }
              .transition(.opacity)
              .zIndex(0)

            // Force the sheet into a centered full-size overlay so it
            // does not end up clipped or visually hidden behind the scrim.
            sheetContent(presentedItem)
              .background(OmiColors.backgroundPrimary)
              .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius))
              .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
              .transition(.scale(scale: 0.95).combined(with: .opacity))
              .accessibilityAddTraits(.isModal)
              .zIndex(1)

            OverlayModalEscapeCatcher {
              log("DISMISSABLE_SHEET: Escape pressed, dismissing item")
              OmiMotion.withGated(.easeOut(duration: 0.2)) {
                item = nil
              }
            }
            .zIndex(2)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .omiAnimation(.easeOut(duration: 0.2), value: item?.id != nil)
  }
}
