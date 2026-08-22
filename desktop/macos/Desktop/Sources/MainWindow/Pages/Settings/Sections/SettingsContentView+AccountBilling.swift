import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var accountSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(destination: .account) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "person.circle.fill")
              .scaledFont(size: OmiType.hero)
              .foregroundColor(OmiColors.textTertiary)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text(AuthService.shared.displayName.isEmpty ? "User" : AuthService.shared.displayName)
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)

              if let email = AuthState.shared.userEmail {
                Text(email)
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(OmiColors.textTertiary)
              }
            }

            Spacer()

            Button("Sign Out") {
              ExplicitSignOutAction().perform()
            }
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            .disabled(isDeletingAccount)
          }

          Divider()
            .overlay(OmiColors.backgroundQuaternary)

          HStack(alignment: .center, spacing: OmiSpacing.lg) {
            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Export My Data")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)

              Text(
                "Save your conversations, memories, tasks, goals, chats, focus data, and settings as JSON. The export stays on this Mac."
              )
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
            }

            Spacer()

            Button(action: exportMyData) {
              if isExportingUserData {
                ProgressView()
                  .controlSize(.small)
              } else {
                Text("Export")
                  .scaledFont(size: OmiType.body, weight: .semibold)
              }
            }
            .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
            .disabled(isDeletingAccount || isExportingUserData)
            .accessibilityIdentifier("export-my-data-button")
          }

          if let userDataExportStatus {
            Text(userDataExportStatus)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(
                userDataExportStatus.hasPrefix("Saved") ? OmiColors.textSecondary : OmiColors.warning)
          }

          Divider()
            .overlay(OmiColors.backgroundQuaternary)

          HStack(alignment: .center, spacing: OmiSpacing.lg) {
            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Delete Account & Data")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.error)

              Text(
                "Permanently deletes server data, clears local data for this account, resets onboarding, and signs you out."
              )
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
            }

            Spacer()

            Button(action: {
              AnalyticsManager.shared.deleteAccountClicked()
              showDeleteAccountAlert = true
            }) {
              if isDeletingAccount {
                ProgressView()
                  .controlSize(.small)
              } else {
                Text("Delete")
                  .scaledFont(size: OmiType.body, weight: .semibold)
              }
            }
            .buttonStyle(OmiButtonStyle(.destructive, size: .compact))
            .disabled(isDeletingAccount)
          }

          if let deleteAccountError {
            Text(deleteAccountError)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.warning)
          }
        }
      }
      .alert("Delete Account and Data?", isPresented: $showDeleteAccountAlert) {
        Button("Cancel", role: .cancel) {
          AnalyticsManager.shared.deleteAccountCancelled()
        }
        Button("Delete Permanently", role: .destructive) {
          deleteAccountAndData()
        }
      } message: {
        Text(
          "This cannot be undone. Your account, chat history, and all server data will be permanently deleted. Local data for this account will be cleared and you'll return to onboarding."
        )
      }
    }
  }

  @MainActor
  private func exportMyData() {
    guard let ownerID = RuntimeOwnerIdentity.currentOwnerId() else {
      userDataExportStatus = LocalUserDataExportError.notAuthenticated.localizedDescription
      return
    }
    userDataExportStatus = nil
    isExportingUserData = true
    Task { @MainActor in
      defer { isExportingUserData = false }
      do {
        switch try await LocalUserDataExportAction.live.perform(ownerID: ownerID) {
        case .cancelled:
          break
        case .saved(let destination):
          userDataExportStatus = "Saved \(destination.lastPathComponent)"
        }
      } catch {
        userDataExportStatus = error.localizedDescription
      }
    }
  }

  // MARK: - Trial Countdown Card

  @ViewBuilder
  var trialCountdownCard: some View {
    if let trial = appState.trialMetadata, trial.trialStartedAt != nil, !trial.trialExpired {
      settingsCard(settingId: "planusage.trial") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "clock.fill")
              .scaledFont(size: OmiType.title)
              .foregroundColor(trialTimeColor(remaining: trial.trialRemainingSeconds))

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Premium Trial Active")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)

              Text(trialCountdownText(remaining: trial.trialRemainingSeconds))
                .scaledFont(size: OmiType.body)
                .foregroundColor(trialTimeColor(remaining: trial.trialRemainingSeconds))
            }

            Spacer()

            // Progress ring
            ZStack {
              Circle()
                .stroke(OmiColors.backgroundQuaternary, lineWidth: 3)
              Circle()
                .trim(from: 0, to: trialProgress(trial))
                .stroke(
                  trialTimeColor(remaining: trial.trialRemainingSeconds),
                  style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
          }

          Divider().overlay(OmiColors.backgroundQuaternary)

          VStack(alignment: .leading, spacing: OmiSpacing.sm) {
            Text("Included in your trial")
              .scaledFont(size: OmiType.caption, weight: .semibold)
              .foregroundColor(OmiColors.textTertiary)

            trialFeatureRow(text: "Unlimited listening & transcription")
            trialFeatureRow(text: "Unlimited memories & insights")
            trialFeatureRow(text: "Chat questions")
          }
        }
      }
    } else if let trial = appState.trialMetadata,
      trial.trialExpired
    {
      settingsCard(settingId: "planusage.trial-expired") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "exclamationmark.circle.fill")
              .scaledFont(size: OmiType.title)
              .foregroundColor(OmiColors.warning)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Trial Ended")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)

              Text("Your trial access has ended")
                .scaledFont(size: OmiType.body)
                .foregroundColor(OmiColors.textSecondary)
            }

            Spacer()
          }

          Divider().overlay(OmiColors.backgroundQuaternary)

          if userSubscription?.billingAvailability.checkoutEnabled == true,
            let firstPlan = subscriptionPlansForDisplay.first
          {
            Button(action: {
              selectedPlanIdForCheckout = firstPlan.id
            }) {
              Text("View Plans")
                .scaledFont(size: OmiType.body, weight: .semibold)
            }
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))
          }
        }
      }
    }
  }

  func trialFeatureRow(text: String) -> some View {
    HStack(spacing: OmiSpacing.sm) {
      ZStack {
        Circle()
          .fill(OmiColors.backgroundTertiary)
          .frame(width: 18, height: 18)
        Image(systemName: "checkmark")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(OmiColors.textSecondary)
      }
      Text(text)
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)
    }
  }

  func trialCountdownText(remaining: Int) -> String {
    if remaining <= 0 { return "Expired" }
    let hours = remaining / 3600
    let minutes = (remaining % 3600) / 60
    if hours >= 24 {
      let days = hours / 24
      let leftoverHours = hours % 24
      return "\(days)d \(leftoverHours)h remaining"
    }
    if hours > 0 {
      return "\(hours)h \(minutes)m remaining"
    }
    return "\(minutes)m remaining"
  }

  func trialTimeColor(remaining: Int) -> Color {
    if remaining <= 3600 { return OmiColors.warning }  // < 1 hour: warning orange
    if remaining <= 24 * 3600 { return .yellow }  // < 24 hours: yellow
    return OmiColors.success  // plenty of time: green
  }

  func trialProgress(_ trial: TrialMetadataResponse) -> CGFloat {
    guard trial.trialDurationSeconds > 0 else { return 0 }
    return CGFloat(trial.trialRemainingSeconds) / CGFloat(trial.trialDurationSeconds)
  }

  // MARK: - Plan and Usage Section

  var planUsageSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      trialCountdownCard

      settingsCard(settingId: PlanUsageCardIdentity.currentPlan.rawValue) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "creditcard.fill")
              .scaledFont(size: OmiType.title)
              .foregroundColor(OmiColors.textSecondary)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text(currentPlanTitle)
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)

              Text(currentPlanSubtitle)
                .scaledFont(size: OmiType.body)
                .foregroundColor(OmiColors.textTertiary)
            }

            Spacer()

            if isLoadingSubscription {
              ProgressView()
                .controlSize(.small)
            } else if hasPaidSubscription,
              userSubscription?.billingAvailability.portalEnabled == true
            {
              Button(action: openCustomerPortal) {
                if isOpeningCustomerPortal {
                  ProgressView()
                    .controlSize(.small)
                } else {
                  Text("Manage")
                    .scaledFont(size: OmiType.body, weight: .semibold)
                }
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
              .disabled(isOpeningCustomerPortal)
            } else {
              Button("Refresh") {
                loadSubscriptionInfo()
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
              .disabled(isLoadingSubscription)
            }
          }

          if let periodText = currentPlanPeriodText {
            Divider()
              .overlay(OmiColors.backgroundQuaternary)

            Text(periodText)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textSecondary)
          }

          if let error = subscriptionError {
            Text(error)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.warning)
          }
        }
      }

      if shouldShowPlanPurchaseOptions {
        settingsCard(settingId: PlanUsageCardIdentity.purchase.rawValue) {
          VStack(alignment: .leading, spacing: OmiSpacing.lg) {
            // All plan cards share the row width — no horizontal scrolling.
            HStack(alignment: .top, spacing: OmiSpacing.lg) {
              ForEach(subscriptionPlansForDisplay) { plan in
                subscriptionPlanCard(plan)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
            }
          }
        }
      }

      chatUsageQuotaCard
    }
  }

  // MARK: - Chat Usage Quota Card

  @ViewBuilder
  var chatUsageQuotaCard: some View {
    if let quota = chatUsageQuota {
      settingsCard(settingId: PlanUsageCardIdentity.quota.rawValue) {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Text("Usage this month")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
            Spacer()
            Text(chatUsageQuotaValueText(quota))
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(chatUsageBarColor(quota))
              .monospacedDigit()
          }

          ProgressView(value: min(quota.percent / 100.0, 1.0))
            .progressViewStyle(LinearProgressViewStyle(tint: chatUsageBarColor(quota)))
            .frame(height: 6)

          HStack {
            Text(chatUsageQuotaDescription(quota))
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
            Spacer()
            if let resetText = chatUsageQuotaResetText(quota) {
              Text(resetText)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
            }
          }

          if !quota.allowed {
            Text("You've reached this month's included limit. Wait until the next reset.")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.warning)
          } else if quota.percent >= 80.0 {
            Text("You're close to your monthly limit.")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.warning)
          }
        }
      }
    } else if isLoadingChatUsage {
      settingsCard(settingId: PlanUsageCardIdentity.quotaLoading.rawValue) {
        HStack {
          ProgressView().controlSize(.small)
          Text("Loading usage…")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
        }
      }
    }
  }

  func chatUsageQuotaValueText(_ q: APIClient.ChatUsageQuota) -> String {
    if q.unit == "cost_usd" {
      let limit = q.limit.map { String(format: "$%.0f", $0) } ?? "—"
      return String(format: "$%.2f / %@", q.used, limit)
    }
    let used = Int(q.used)
    let limit = q.limit.map { "\(Int($0))" } ?? "∞"
    return "\(used) / \(limit)"
  }

  func chatUsageQuotaDescription(_ q: APIClient.ChatUsageQuota) -> String {
    if q.unit == "cost_usd" {
      return "Chat spend on \(q.plan) plan"
    }
    return "Chat questions on \(q.plan) plan"
  }

  func chatUsageQuotaResetText(_ q: APIClient.ChatUsageQuota) -> String? {
    guard let resetAt = q.resetAt else { return nil }
    let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
    let now = Date()
    let days = max(0, Int(resetDate.timeIntervalSince(now) / 86400))
    if days <= 0 {
      return "Resets today"
    }
    if days == 1 {
      return "Resets tomorrow"
    }
    return "Resets in \(days) days"
  }

  func chatUsageBarColor(_ q: APIClient.ChatUsageQuota) -> Color {
    if !q.allowed || q.percent >= 100.0 { return OmiColors.warning }
    if q.percent >= 80.0 { return OmiColors.warning }
    return OmiColors.accent
  }

  // MARK: - AI Chat Section

}
