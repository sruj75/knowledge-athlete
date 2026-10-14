import OmiTheme
import SwiftUI

struct ShortcutsSettingsSection: View {
  @ObservedObject private var settings = ShortcutSettings.shared
  @Binding var highlightedSettingId: String?
  @State private var recordingTarget: ShortcutTarget?
  @State private var captureError: String?
  @State private var localShortcutCaptureMonitor: Any?

  init(highlightedSettingId: Binding<String?> = .constant(nil)) {
    self._highlightedSettingId = highlightedSettingId
  }

  private enum ShortcutTarget {
    case askOmi
    case pushToTalk
  }

  var body: some View {
    VStack(spacing: OmiSpacing.xl) {
      askOmiKeyCard
      pttKeyCard
    }
    .onDisappear {
      stopShortcutCapture()
    }
  }

  private var askOmiKeyCard: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Open Intentive Shortcut")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text("Global shortcut to open the Intentive app from anywhere.")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)
      }

      HStack(spacing: OmiSpacing.md) {
        ForEach(ShortcutSettings.askOmiPresets, id: \.self) { shortcut in
          askOmiKeyButton(shortcut)
        }
        customShortcutButton(
          for: .askOmi, isSelected: settings.askOmiEnabled && settings.askOmiUsesCustomShortcut)
        disableShortcutButton(isDisabled: !settings.askOmiEnabled) {
          stopShortcutCapture()
          settings.askOmiEnabled = false
        }
        Spacer()
      }

      if settings.askOmiEnabled
        && (recordingTarget == .askOmi || settings.askOmiUsesCustomShortcut
          || (captureError != nil && recordingTarget == .askOmi))
      {
        shortcutRecorderCard(
          title: recordingTarget == .askOmi
            ? "Press your custom Open Intentive shortcut now" : "Custom Open Intentive shortcut",
          shortcut: settings.askOmiShortcut,
          isRecording: recordingTarget == .askOmi,
          action: { startShortcutCapture(.askOmi) },
          helperText: "Use at least one non-modifier key."
        )
      }
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .fill(OmiColors.backgroundTertiary.opacity(0.5))
    )
    .modifier(
      SettingHighlightModifier(
        destination: .openOmiShortcut, highlightedSettingId: $highlightedSettingId))
  }

  private func askOmiKeyButton(_ shortcut: ShortcutSettings.KeyboardShortcut) -> some View {
    let isSelected =
      settings.askOmiEnabled && settings.askOmiShortcut == shortcut
      && !settings.askOmiUsesCustomShortcut
    return Button {
      stopShortcutCapture()
      settings.updateAskOmiRegistration(enabled: true, shortcut: shortcut)
    } label: {
      shortcutSelectionLabel(tokens: shortcut.displayTokens, isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }

  private var pttKeyCard: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Talk to Intentive")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text(
          "Tap once to start a conversation. Keep talking naturally, or tap again to end. Uses your system microphone."
        )
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textSecondary)
      }

      HStack(spacing: OmiSpacing.md) {
        ForEach(ShortcutSettings.pttPresets, id: \.self) { shortcut in
          pttKeyButton(shortcut)
        }
        customShortcutButton(
          for: .pushToTalk, isSelected: settings.pttEnabled && settings.pttUsesCustomShortcut)
        disableShortcutButton(isDisabled: !settings.pttEnabled) {
          stopShortcutCapture()
          settings.pttEnabled = false
        }
        Spacer()
      }

      if settings.pttEnabled
        && (recordingTarget == .pushToTalk || settings.pttUsesCustomShortcut
          || (captureError != nil && recordingTarget == .pushToTalk))
      {
        shortcutRecorderCard(
          title: recordingTarget == .pushToTalk
            ? "Press your custom conversation shortcut now" : "Custom conversation shortcut",
          shortcut: settings.pttShortcut,
          isRecording: recordingTarget == .pushToTalk,
          action: { startShortcutCapture(.pushToTalk) },
          helperText: "One key or a key combination both work."
        )
      }
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .fill(OmiColors.backgroundTertiary.opacity(0.5))
    )
    .modifier(
      SettingHighlightModifier(
        destination: .pushToTalk, highlightedSettingId: $highlightedSettingId))
  }

  private func pttKeyButton(_ shortcut: ShortcutSettings.KeyboardShortcut) -> some View {
    let isSelected =
      settings.pttEnabled && settings.pttShortcut == shortcut && !settings.pttUsesCustomShortcut
    return Button {
      stopShortcutCapture()
      settings.pttEnabled = true
      settings.pttShortcut = shortcut
    } label: {
      shortcutSelectionLabel(tokens: shortcut.displayTokens, isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }

  private func customShortcutButton(for target: ShortcutTarget, isSelected: Bool) -> some View {
    Button {
      switch target {
      case .askOmi:
        settings.askOmiEnabled = true
      case .pushToTalk:
        settings.pttEnabled = true
      }
      startShortcutCapture(target)
    } label: {
      Text("Custom")
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.textPrimary)
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
            .fill(
              (isSelected || recordingTarget == target)
                ? OmiColors.accent.opacity(0.3)
                : OmiColors.backgroundTertiary.opacity(0.5))
        )
        .overlay(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
            .stroke(
              isSelected || recordingTarget == target ? OmiColors.accent : Color.clear,
              lineWidth: 1.5)
        )
    }
    .buttonStyle(.plain)
  }

  private func disableShortcutButton(isDisabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text("Disable")
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.textPrimary)
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
            .fill(
              isDisabled
                ? OmiColors.accent.opacity(0.3)
                : OmiColors.backgroundTertiary.opacity(0.5))
        )
        .overlay(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
            .stroke(isDisabled ? OmiColors.accent : Color.clear, lineWidth: 1.5)
        )
    }
    .buttonStyle(.plain)
  }

  private func shortcutSelectionLabel(tokens: [String], isSelected: Bool) -> some View {
    HStack(spacing: OmiSpacing.xs) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
        Text(token)
          .scaledFont(size: OmiType.body, weight: .medium)
      }
    }
    .foregroundColor(OmiColors.textPrimary)
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .fill(
          isSelected
            ? OmiColors.accent.opacity(0.3)
            : OmiColors.backgroundTertiary.opacity(0.5))
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .stroke(isSelected ? OmiColors.accent : Color.clear, lineWidth: 1.5)
    )
  }

  private func shortcutRecorderCard(
    title: String,
    shortcut: ShortcutSettings.KeyboardShortcut,
    isRecording: Bool,
    action: @escaping () -> Void,
    helperText: String
  ) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      Text(title)
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)

      HStack(spacing: OmiSpacing.sm) {
        HStack(spacing: OmiSpacing.xs) {
          ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
            Text(token)
              .scaledFont(size: OmiType.body, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
              .padding(.horizontal, token.count > 2 ? 10 : 8)
              .padding(.vertical, OmiSpacing.xs)
              .background(
                RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                  .fill(OmiColors.backgroundPrimary)
              )
          }
        }

        Spacer()

        Button(action: action) {
          Text(isRecording ? "Listening..." : "Save")
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
      }

      Text(helperText)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textSecondary)

      if let captureError, isRecording {
        Text(captureError)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(.red.opacity(0.9))
      }
    }
    .padding(OmiSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .fill(OmiColors.backgroundSecondary.opacity(0.85))
    )
  }

  private func startShortcutCapture(_ target: ShortcutTarget) {
    stopShortcutCapture()
    recordingTarget = target
    captureError = nil

    localShortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .flagsChanged, .keyDown,
    ]) { event in
      handleShortcutCapture(event) ? nil : event
    }
  }

  private func stopShortcutCapture() {
    if let monitor = localShortcutCaptureMonitor {
      NSEvent.removeMonitor(monitor)
      localShortcutCaptureMonitor = nil
    }
    recordingTarget = nil
    captureError = nil
  }

  private func handleShortcutCapture(_ event: NSEvent) -> Bool {
    guard let target = recordingTarget else { return false }

    switch target {
    case .askOmi:
      if event.type == .flagsChanged {
        captureError = "Open Intentive needs a non-modifier key."
        return true
      }
      guard
        let shortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(
          event, allowModifierOnly: false)
      else {
        return false
      }
      settings.updateAskOmiRegistration(enabled: true, shortcut: shortcut)
    case .pushToTalk:
      guard
        let shortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(
          event, allowModifierOnly: true)
      else {
        return false
      }
      settings.pttEnabled = true
      settings.pttShortcut = shortcut
    }

    stopShortcutCapture()
    return true
  }
}
