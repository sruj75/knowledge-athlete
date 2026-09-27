import AppKit
import OmiTheme
import SwiftUI

/// Message-local feedback, copy, context and timestamp controls share one reveal/focus boundary.
struct ChatMessageMetadataRow: View {
  let message: ChatMessage
  let actions: [ChatMessageAction]
  let isRowHovering: Bool
  @State private var isTimestampHovering = false
  @State private var showCopied = false
  @State private var showInfoPopover = false
  @FocusState private var isMetadataControlFocused: Bool

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      AIEvaluationFeedbackView(message: message, metadataFocus: $isMetadataControlFocused)
      if actions.contains(.copy) {
        copyButton
      }

      if actions.contains(.info) {
        infoButton
      }

      if actions.contains(.timestamp) {
        Text(message.createdAt, format: .dateTime.hour().minute())
          .scaledFont(size: OmiType.micro, weight: .medium)
          .foregroundColor(OmiColors.textTertiary)
          .onHover { isTimestampHovering = $0 }

        if isTimestampHovering {
          Text(message.createdAt, format: .dateTime.month(.abbreviated).day())
            .scaledFont(size: OmiType.micro, weight: .medium)
            .foregroundColor(OmiColors.textSecondary)
            .transition(.opacity)
        }
      }
    }
    // Quiet timeline: actions and timestamps only surface while the reader
    // is on the message — by pointer hover or keyboard focus — or
    // mid-interaction with them.
    .opacity(
      ChatBubbleMetadataReveal.isVisible(
        hovering: isRowHovering,
        controlFocused: isMetadataControlFocused,
        transientFeedback: showCopied || showInfoPopover
      ) ? 1 : 0
    )
    .omiAnimation(.easeInOut(duration: 0.12), value: isTimestampHovering)
    .omiAnimation(.easeInOut(duration: 0.15), value: isRowHovering)
    .omiAnimation(.easeInOut(duration: 0.15), value: isMetadataControlFocused)
  }

  @ViewBuilder
  private var copyButton: some View {
    Button(action: {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(message.copyableText, forType: .string)
      showCopied = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        showCopied = false
      }
    }) {
      Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(showCopied ? .green : OmiColors.textTertiary)
    }
    .buttonStyle(.plain)
    .focused($isMetadataControlFocused)
    .help("Copy message")
  }

  /// Response Context popover — same developer info the floating bar shows
  /// (model, screenshot, prompt context counts, tools). Only fresh responses
  /// carry metadata; it is in-memory only and not persisted across restarts.
  @ViewBuilder
  private var infoButton: some View {
    Button(action: { showInfoPopover.toggle() }) {
      Image(systemName: "info.circle")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(showInfoPopover ? OmiColors.textPrimary : OmiColors.textTertiary)
    }
    .buttonStyle(.plain)
    .focused($isMetadataControlFocused)
    .help("View response context")
    .popover(isPresented: $showInfoPopover, arrowEdge: .bottom) {
      if let metadata = message.metadata {
        MessageMetadataPopover(metadata: metadata)
      }
    }
  }
}

/// Visibility rule for the quiet timeline's per-message metadata row
/// (copy / info / timestamp). Keyboard parity is part of the
/// contract: focus on any metadata control must reveal the row, otherwise
/// Tab / Full Keyboard Access ends up on an invisible button.
enum ChatBubbleMetadataReveal {
  static func isVisible(hovering: Bool, controlFocused: Bool, transientFeedback: Bool) -> Bool {
    hovering || controlFocused || transientFeedback
  }
}
