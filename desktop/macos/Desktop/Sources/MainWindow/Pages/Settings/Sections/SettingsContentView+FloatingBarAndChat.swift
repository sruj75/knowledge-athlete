import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var floatingBarSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(destination: .floatingBar) {
        HStack(spacing: OmiSpacing.lg) {
          Text("Show floating bar")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)

          Spacer()

          Toggle("", isOn: $showAskOmiBar)
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
            .onChange(of: showAskOmiBar) { _, newValue in
              if newValue {
                FloatingControlBarManager.shared.show()
              } else {
                FloatingControlBarManager.shared.hide()
              }
            }
        }
      }

      settingsCard(destination: .floatingBarBackground) {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          Text("Background Style")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)

          HStack(spacing: OmiSpacing.lg) {
            Text("Transparent")
              .scaledFont(size: OmiType.body, weight: shortcutSettings.solidBackground ? .regular : .semibold)
              .foregroundColor(
                shortcutSettings.solidBackground ? OmiColors.textTertiary : OmiColors.textPrimary)

            Toggle("", isOn: $shortcutSettings.solidBackground)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()

            Text("Solid Dark")
              .scaledFont(size: OmiType.body, weight: shortcutSettings.solidBackground ? .semibold : .regular)
              .foregroundColor(
                shortcutSettings.solidBackground ? OmiColors.textPrimary : OmiColors.textTertiary)

            Spacer()
          }
        }
      }

      settingsCard(destination: .floatingBarDraggable) {
        HStack(spacing: OmiSpacing.lg) {
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Draggable Floating Bar")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
            Text("Allow repositioning the floating bar by dragging it.")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
          }
          Spacer()
          Toggle("", isOn: $shortcutSettings.draggableBarEnabled)
            .toggleStyle(OmiToggleStyle())
        }
      }

      settingsCard(destination: .typedVoiceAnswers) {
        HStack(spacing: OmiSpacing.lg) {
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Typed Questions")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
            Text("Speak answers aloud when you submit a typed question from the floating bar.")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
          }
          Spacer()
          Toggle("", isOn: floatingBarTypedVoiceAnswersBinding)
            .toggleStyle(OmiToggleStyle())
        }
      }

      settingsCard(destination: .screenSharing) {
        HStack(spacing: OmiSpacing.lg) {
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Screen Sharing in Chat")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
            Text("Let Ask Omi capture your screen when you ask about what's on it.")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
          }
          Spacer()
          Toggle("", isOn: $chatScreenshotSharingEnabled)
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
        }
      }

      voicePicker(settingId: "floatingbar.voice")
        .opacity(shortcutSettings.hasAnyFloatingBarVoiceAnswersEnabled ? 1 : 0.55)
        .disabled(!shortcutSettings.hasAnyFloatingBarVoiceAnswersEnabled)

      voiceSpeedSlider(destination: .voiceSpeed)
        .opacity(shortcutSettings.hasAnyFloatingBarVoiceAnswersEnabled ? 1 : 0.55)
        .disabled(!shortcutSettings.hasAnyFloatingBarVoiceAnswersEnabled)
    }
  }

  func voicePicker(settingId: String) -> some View {
    settingsCard(settingId: settingId) {
      HStack(spacing: OmiSpacing.lg) {
        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text("Voice")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
          Text(
            ShortcutSettings.voiceOption(for: shortcutSettings.selectedVoiceID).description
          )
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)
        }
        Spacer()
        SettingsMenuPicker(selection: $shortcutSettings.selectedVoiceID) {
          ForEach(ShortcutSettings.availableVoices) { voice in
            Text(voice.name).tag(voice.id)
          }
        }
      }
    }
  }

  var shortcutsSection: some View {
    ShortcutsSettingsSection(highlightedSettingId: $highlightedSettingId)
  }

  // MARK: - About Section

}
