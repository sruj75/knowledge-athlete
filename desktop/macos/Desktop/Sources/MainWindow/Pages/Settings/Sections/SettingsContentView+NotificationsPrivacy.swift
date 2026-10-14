import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var notificationsSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(destination: .supervisor) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          settingRow(
            title: "Supervisor", subtitle: "Use permitted screen, webcam and transcript context to guide conversation"
          ) {
            Toggle("Supervisor", isOn: $supervisor.enabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
          }
          Text(supervisorStatusText)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(supervisor.state == .paused ? OmiColors.warning : OmiColors.textTertiary)
          Text(
            "Screen and audio recording permissions remain in your capture settings. Proactive speech follows the notification controls below."
          )
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
          Divider()
          settingRow(title: "Webcam", subtitle: "Use current camera images while this Mac is awake and unlocked") {
            Toggle("Webcam", isOn: $supervisorWebcam.enabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
          }
          if supervisorWebcam.enabled {
            Picker("Camera", selection: $supervisorWebcam.selectedDeviceID) {
              Text("Built-in camera").tag(Optional<String>.none)
              ForEach(supervisorWebcam.devices.filter { !$0.builtIn }) { device in
                Text(device.name).tag(Optional(device.id))
              }
            }
            Text(webcamStatusText)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
          }
          Text(
            "Only the latest camera image is held in memory. Camera images are not recorded or included in evaluation sharing."
          )
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
        }
        .task { await supervisorWebcam.refreshDevices() }
      }
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

          Text("Allow Intentive to speak proactively and control how often it interrupts")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)

          Divider()
            .background(OmiColors.backgroundQuaternary)

          Group {
            notificationFrequencySlider(destination: .notificationFrequency)
          }
          .disabled(!notificationsEnabled)
          .opacity(notificationsEnabled ? 1 : 0.55)
        }
      }
    }
  }

  private var supervisorStatusText: String {
    switch supervisor.state {
    case .idle: return "Ready for new context"
    case .observing: return "Observing permitted context"
    case .evaluating: return "Considering the latest context"
    case .paused:
      return "Monitoring is waiting for a service limit or temporary failure to clear. Conversation remains available."
    case .suspended: return "Monitoring is paused while this Mac is asleep or locked"
    case .disabled: return "Supervisor is off"
    }
  }

  private var webcamStatusText: String {
    switch supervisorWebcam.availability {
    case .available: return "Camera context is available"
    case .denied: return "Allow camera access for Intentive in System Settings → Privacy & Security → Camera"
    case .disabled: return "Webcam is off"
    case .suspended: return "Camera is paused while monitoring is unavailable"
    case .stale, .unavailable: return "The selected camera is unavailable. Other permitted inputs continue working."
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

      settingsCard(destination: .evaluationSharing) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          settingRow(
            title: "Share this evaluation session",
            subtitle: "Include bounded conversation and transcript text to help evaluate Intentive"
          ) {
            Toggle("Share this evaluation session", isOn: $supervisor.evaluationSharing)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
          }
          Text(
            "Off by default. Screenshots, audio, saved memories and profile contents are never included. Sharing ends when monitoring ends, you sign out, or you turn this off."
          )
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
