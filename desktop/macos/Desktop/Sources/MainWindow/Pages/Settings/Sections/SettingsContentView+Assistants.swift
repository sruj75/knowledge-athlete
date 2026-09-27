import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var preferencesSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Multiple Chat Sessions toggle
      settingsCard(destination: .multipleChats) {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "bubble.left.and.bubble.right")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(OmiColors.textSecondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Multiple Chat Sessions")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Text(
              multiChatEnabled
                ? "Create separate chat threads"
                : "Single chat synced with mobile app"
            )
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
          }

          Spacer()

          Toggle("", isOn: $multiChatEnabled)
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
        }
      }

      // Launch at Login toggle
      settingsCard(destination: .launchAtLogin) {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "power")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(OmiColors.textSecondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Launch at Login")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Text(launchAtLoginManager.statusDescription)
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
          }

          Spacer()

          Toggle(
            "",
            isOn: Binding(
              get: { launchAtLoginManager.isEnabled },
              set: { newValue in
                LaunchAtLoginIntentPolicy.apply(
                  .settings(newValue),
                  setEnabled: { launchAtLoginManager.setEnabled($0) },
                  report: { enabled, source in
                    AnalyticsManager.shared.launchAtLoginChanged(enabled: enabled, source: source)
                  })
              }
            )
          )
          .toggleStyle(OmiToggleStyle())
          .labelsHidden()
        }
      }
    }
  }

  var troubleshootingSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Report Issue
      settingsCard(destination: .advancedReportIssue) {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "exclamationmark.bubble")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(OmiColors.textSecondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Report Issue")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Text("Send app logs and report a problem")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
          }

          Spacer()

          Button(action: {
            FeedbackWindow.show(userEmail: AuthState.shared.userEmail)
          }) {
            Text("Report")
          }
          .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      }

    }
  }

  // MARK: - Reset Onboarding Subsection

  var resetOnboardingSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(destination: .resetOnboarding) {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "arrow.counterclockwise")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(OmiColors.textSecondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Reset Onboarding")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Text("Restart setup wizard for this app build only")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
          }

          Spacer()

          Button(action: { showResetOnboardingAlert = true }) {
            Text("Reset")
          }
          .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      }
      .alert("Reset Onboarding?", isPresented: $showResetOnboardingAlert) {
        Button("Cancel", role: .cancel) {}
        Button("Reset & Restart", role: .destructive) {
          appState.resetOnboardingAndRestart(source: .settings)
        }
      } message: {
        Text(
          "This will reset onboarding for this app build only, clear the setup-only journal, and restart the app without affecting normal app data or the other installed build."
        )
      }
    }
  }
}
