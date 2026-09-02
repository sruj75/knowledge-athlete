import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var notificationsSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Notifications
      settingsCard(destination: .notificationSettings) {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack {
            settingsCardHeader(icon: "bell.badge.fill", title: "Notifications")

            Spacer()

            Toggle("", isOn: $notificationsEnabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
              .onChange(of: notificationsEnabled) { _, newValue in
                updateNotificationSettings(enabled: newValue)
              }
          }

          Text("Control how often you receive notifications")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)

          Divider()
            .background(OmiColors.backgroundQuaternary)

          Group {
            notificationFrequencySlider(destination: .notificationFrequency)

            // Sits under the master toggle and the frequency slider because both gate it:
            // frequency caps how often any proactive card is delivered, and this decides
            // whether live suggestions are generated at all.
            settingRow(
              title: "Live Suggestions",
              subtitle: "Suggest things in the notch using available local context",
              settingId: "notifications.livesuggestions"
            ) {
              Toggle("", isOn: $liveSuggestionsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: liveSuggestionsEnabled) { _, newValue in
                  SuggestionAssistantSettings.shared.applyUserEnabledChange(newValue)
                }
            }

            settingRow(
              title: "Focus Notifications", subtitle: "Show notification on focus changes",
              destination: .focusNotifications
            ) {
              Toggle("", isOn: $focusNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: focusNotificationsEnabled) { _, newValue in
                  FocusAssistantSettings.shared.notificationsEnabled = newValue
                }
            }

            settingRow(
              title: "Task Notifications",
              subtitle: "Allow interruptions when a task needs attention",
              destination: .taskNotifications
            ) {
              Toggle("", isOn: $taskNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: taskNotificationsEnabled) { _, newValue in
                  TaskAssistantSettings.shared.notificationsEnabled = newValue
                }
            }

            settingRow(
              title: "Insight Notifications",
              subtitle: "Show notification when an insight is generated",
              destination: .insightNotifications
            ) {
              Toggle("", isOn: $insightNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: insightNotificationsEnabled) { _, newValue in
                  InsightAssistantSettings.shared.notificationsEnabled = newValue
                }
            }

            settingRow(
              title: "Memory Notifications",
              subtitle: "Show notification when a memory is extracted",
              destination: .memoryNotifications
            ) {
              Toggle("", isOn: $memoryNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: memoryNotificationsEnabled) { _, newValue in
                  MemoryAssistantSettings.shared.applyUserSettingChange(.notificationsEnabled, value: newValue)
                }
            }
          }
          .disabled(!notificationsEnabled)
          .opacity(notificationsEnabled ? 1 : 0.55)
        }
      }
    }
  }

  // MARK: - Privacy Section

  var privacySection: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Local data authority
      settingsCard(destination: .localData) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          settingsCardHeader(icon: "internaldrive", title: PrivacyTruthPresentation.dataLocationTitle)

          Text(PrivacyTruthPresentation.dataLocationDetail)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
        }
      }

      // What We Track
      settingsCard(destination: .tracking) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "chart.bar.xaxis")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
              .frame(width: 20)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text(PrivacyTruthPresentation.analyticsControlTitle)
                .scaledFont(size: OmiType.body, weight: .medium)
                .foregroundColor(OmiColors.textPrimary)
              Text(PrivacyTruthPresentation.analyticsControlDetail)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
              Text(productAnalyticsConsent.status.detail)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(
                  productAnalyticsConsent.status == .configurationUnavailable
                    ? OmiColors.warning : OmiColors.textTertiary)
            }

            Spacer()

            Toggle(
              "",
              isOn: Binding(
                get: { productAnalyticsConsent.isSharingEnabled },
                set: { productAnalyticsConsent.setSharingEnabled($0) }
              )
            )
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          Button(action: {
            OmiMotion.withGated(.easeInOut(duration: 0.2)) {
              isTrackingExpanded.toggle()
            }
          }) {
            HStack(spacing: OmiSpacing.sm) {
              Image(systemName: "list.bullet")
                .scaledFont(size: OmiType.body)
                .foregroundColor(OmiColors.textSecondary)
                .frame(width: 20)

              Text("What We Track")
                .scaledFont(size: OmiType.body, weight: .medium)
                .foregroundColor(OmiColors.textPrimary)

              Spacer()

              Image(systemName: "chevron.right")
                .scaledFont(size: OmiType.caption, weight: .semibold)
                .foregroundColor(OmiColors.textTertiary)
                .rotationEffect(.degrees(isTrackingExpanded ? 90 : 0))
            }
          }
          .buttonStyle(.plain)

          if isTrackingExpanded {
            VStack(alignment: .leading, spacing: OmiSpacing.xs) {
              ForEach(PrivacyTruthPresentation.trackingCategories, id: \.self) { category in
                trackingItem(category)
              }

              Text(PrivacyTruthPresentation.trackingBoundary)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
                .padding(.top, OmiSpacing.xxs)
            }
            .transition(.opacity)
          }
        }
      }

      settingsCard(settingId: "privacy.managedservices") {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "network")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
              .frame(width: 20)

            Text("Managed services")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)
          }

          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            ForEach(PrivacyTruthPresentation.managedServices, id: \.name) { service in
              trackingItem("\(service.name) — \(service.purpose)")
            }
            Text(PrivacyTruthPresentation.billingStatus)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
              .padding(.top, OmiSpacing.xxs)
          }
        }
      }
    }
  }

  // MARK: - Account Section

}
