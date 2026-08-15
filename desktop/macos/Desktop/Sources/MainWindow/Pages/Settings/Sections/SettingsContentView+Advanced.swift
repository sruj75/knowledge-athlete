import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  func advancedCategoryHeader(title: String, icon: String) -> some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.subheading)
        .foregroundColor(OmiColors.textSecondary)
      Text(title)
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)
      Spacer()
    }
    .padding(.top, OmiSpacing.lg)
  }

  var advancedSection: some View {
    VStack(spacing: OmiSpacing.xxl) {
      advancedCategoryHeader(title: "Advanced AI Setup", icon: "cpu")
      advancedAISetupSubsection
      advancedCategoryHeader(title: "Profile & Stats", icon: "brain")
      profileAndStatsSubsection
      advancedCategoryHeader(title: "Reset Onboarding", icon: "arrow.counterclockwise")
      resetOnboardingSubsection
      advancedCategoryHeader(title: "Goals", icon: "target")
      goalsSubsection
      advancedCategoryHeader(title: "Preferences", icon: "slider.horizontal.3")
      preferencesSubsection
      advancedCategoryHeader(title: "Troubleshooting", icon: "wrench.and.screwdriver")
      troubleshootingSubsection
      if AppBuild.isBetaProductionBundle {
        advancedCategoryHeader(title: "Beta Diagnostics", icon: "waveform.path.ecg")
        betaDiagnosticsSubsection
      }
      advancedCategoryHeader(title: "Model API Keys", icon: "key")
      developerKeysSubsection

    }
  }

  // MARK: - Beta Diagnostics

  var betaDiagnosticsSubsection: some View {
    settingsCard(settingId: "advanced.beta.enhanced_diagnostics") {
      HStack(spacing: OmiSpacing.lg) {
        Image(systemName: "waveform.path.ecg")
          .scaledFont(size: OmiType.subheading)
          .foregroundColor(OmiColors.textSecondary)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text("Enhanced Diagnostics")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
          Text(
            "Share additional technical failure context to improve this beta. No prompts, transcripts, or raw log files are included."
          )
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textTertiary)
        }

        Spacer()

        Toggle("Enhanced Diagnostics", isOn: $betaEnhancedDiagnosticsEnabled)
          .toggleStyle(OmiToggleStyle())
          .labelsHidden()
      }
    }
  }

  // MARK: - Advanced Subsections

  var advancedAISetupSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.ai.voice") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "waveform")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(OmiColors.textTertiary)

            Text("Voice Model")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            SettingsMenuPicker(selection: $realtimeOmniProvider) {
              ForEach(RealtimeOmniProvider.allCases, id: \.rawValue) { provider in
                Text(provider.displayName).tag(provider.rawValue)
              }
            }
            .onChange(of: realtimeOmniProvider) { _, newValue in
              if newValue == RealtimeOmniProvider.auto.rawValue {
                AutoModelSelector.shared.refreshIfStale()
              }
              NotificationCenter.default.post(name: .realtimeOmniSettingsDidChange, object: nil)
            }
          }

          if let provider = RealtimeOmniProvider(rawValue: realtimeOmniProvider), provider == .auto {
            Text(
              "\(provider.subtitle) · currently \(RealtimeOmniSettings.shared.effectiveProvider.displayName)"
            )
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
          } else if let provider = RealtimeOmniProvider(rawValue: realtimeOmniProvider) {
            Text(provider.subtitle)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
          }
        }
      }

      settingsCard(settingId: "advanced.ai.askmode") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "bubble.left.and.bubble.right")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(OmiColors.textTertiary)

            Text("Ask Mode")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            Toggle("", isOn: $askModeEnabled)
              .toggleStyle(OmiToggleStyle())
              .controlSize(.small)
              .labelsHidden()
          }

          Text(
            "When enabled, shows an Ask/Act toggle in chat. Ask mode keeps each selected turn read-only; when disabled, chat stays in Act mode."
          )
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
        }
      }
    }
  }

  var profileAndStatsSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.profileandstats") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.md) {
            Image(systemName: showProfileAndStats ? "eye.slash" : "eye")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(OmiColors.textSecondary)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Profile and Stats")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)
              Text("Keep the generated profile and usage stats hidden until you need them.")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
            }

            Spacer()

            Button(showProfileAndStats ? "Hide" : "Show") {
              OmiMotion.withGated(.easeInOut(duration: 0.2)) {
                showProfileAndStats.toggle()
              }
            }
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))
          }
        }
      }

      if showProfileAndStats {
        aiUserProfileSubsection
        statsSubsection
      }
    }
  }

  var aiUserProfileSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.aiuserprofile") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "brain")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(OmiColors.textSecondary)

            Text("AI User Profile")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            if isGeneratingAIProfile {
              ProgressView()
                .controlSize(.small)
            } else {
              Button(action: {
                regenerateAIProfile()
              }) {
                Text(aiProfileText == nil ? "Generate Now" : "Regenerate")
                  .scaledFont(size: OmiType.caption)
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            }
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          if let text = aiProfileText {
            if isEditingAIProfile {
              TextEditor(text: $aiProfileEditText)
                .scaledFont(size: OmiType.body, design: .monospaced)
                .foregroundColor(OmiColors.textSecondary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 300)

              HStack {
                Button("Cancel") {
                  isEditingAIProfile = false
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))

                Button("Save") {
                  if let id = aiProfileId {
                    Task {
                      let success = await AIUserProfileService.shared.updateProfileText(
                        id: id, newText: aiProfileEditText
                      )
                      if success {
                        aiProfileText = aiProfileEditText
                      }
                      isEditingAIProfile = false
                    }
                  }
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))

                Spacer()
              }
            } else {
              ScrollView {
                Text(text)
                  .scaledFont(size: OmiType.body, design: .monospaced)
                  .foregroundColor(OmiColors.textSecondary)
                  .textSelection(.enabled)
                  .if_available_writingToolsNone()
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 200)

              HStack {
                if let date = aiProfileGeneratedAt {
                  Text("Last updated: \(date.formatted(.relative(presentation: .named)))")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(OmiColors.textTertiary)
                }

                Spacer()

                if aiProfileDataSourcesUsed > 0 {
                  Text("Data sources: \(aiProfileDataSourcesUsed) items")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(OmiColors.textTertiary)
                }

                Button(action: {
                  aiProfileEditText = text
                  isEditingAIProfile = true
                }) {
                  Image(systemName: "pencil")
                    .scaledFont(size: OmiType.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit profile")

                Button(action: {
                  deleteCurrentAIProfile()
                }) {
                  Image(systemName: "trash")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("Delete this profile")
              }
            }
          } else if !isGeneratingAIProfile {
            Text(
              "Your AI user profile will be generated automatically on next launch, or click \"Generate Now\" to create it now."
            )
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
          } else {
            HStack {
              Spacer()
              VStack(spacing: OmiSpacing.sm) {
                ProgressView()
                Text("Generating profile...")
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(OmiColors.textTertiary)
              }
              Spacer()
            }
            .padding(.vertical, OmiSpacing.xl)
          }
        }
      }
    }
    .task {
      // Try loading immediately (covers all restarts after first generation)
      if let profile = await AIUserProfileService.shared.getLatestProfile() {
        aiProfileId = profile.id
        aiProfileText = profile.profileText
        aiProfileGeneratedAt = profile.generatedAt
        aiProfileDataSourcesUsed = profile.dataSourcesUsed
        return
      }
      // No profile yet — first-ever generation may be in progress, poll briefly
      for _ in 0..<6 {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if let profile = await AIUserProfileService.shared.getLatestProfile() {
          aiProfileId = profile.id
          aiProfileText = profile.profileText
          aiProfileGeneratedAt = profile.generatedAt
          aiProfileDataSourcesUsed = profile.dataSourcesUsed
          return
        }
      }
    }
  }

  var statsSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.stats") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "chart.bar")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(OmiColors.textSecondary)

            Text("Your Stats")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          if let stats = advancedStats {
            statRow(label: "Conversations", value: stats.conversations)
            if isLoadingChatMessages {
              HStack {
                Text("AI Chat Messages")
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(OmiColors.textSecondary)
                Spacer()
                ProgressView()
                  .controlSize(.mini)
              }
            } else if let count = chatMessageCount {
              statRow(label: "AI Chat Messages", value: count)
            }
            statRow(label: "Screenshots", value: stats.screenshotsTotal)
            statRow(label: "Focus Sessions", value: stats.focusSessions)
            statRow(label: "Tasks (To Do)", value: stats.tasksTodo)
            statRow(label: "Tasks (Done)", value: stats.tasksDone)
            statRow(label: "Tasks (Removed)", value: stats.tasksDeleted)
            statRow(label: "Goals", value: stats.goalsCount)
            statRow(label: "Memories", value: stats.memoriesTotal)
          } else if isLoadingStats {
            statRowLoading(label: "Conversations")
            statRowLoading(label: "Apps Installed")
            statRowLoading(label: "AI Chat Messages")
            statRowLoading(label: "Screenshots")
            statRowLoading(label: "Focus Sessions")
            statRowLoading(label: "Tasks (To Do)")
            statRowLoading(label: "Tasks (Done)")
            statRowLoading(label: "Tasks (Removed)")
            statRowLoading(label: "Goals")
            statRowLoading(label: "Memories")
          } else {
            Text("Unable to load stats")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
          }
        }
      }
    }
    .task {
      await loadAdvancedStats()
    }
    .task {
      await loadChatMessageCount()
    }
  }

  var featureTiersSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.featuretiers") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "lock.shield")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(OmiColors.textSecondary)

            Text("Feature Tiers")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          // Tier picker — radio-style selector
          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            tierPickerRow(tier: 0, label: "Show All Features", subtitle: "Unlock everything")
            tierPickerRow(tier: 1, label: "Tier 1", subtitle: "Conversations + Rewind")
            tierPickerRow(tier: 2, label: "Tier 2", subtitle: "+ Memories (100 memories)")
            tierPickerRow(tier: 3, label: "Tier 3", subtitle: "+ Tasks (100 tasks)")
            tierPickerRow(tier: 4, label: "Tier 4", subtitle: "+ AI Chat (100 conversations)")
            tierPickerRow(
              tier: 5, label: "Tier 5", subtitle: "+ Home (200 convos + 2K screenshots)")
            tierPickerRow(tier: 6, label: "Tier 6", subtitle: "+ Apps (300 conversations)")
          }

          if currentTierLevel > 0 {
            Divider()
              .background(OmiColors.backgroundQuaternary)

            Text("Progress")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(OmiColors.textSecondary)

            // Tier 1 — always unlocked
            tierFeatureRow(
              tier: 1, name: "Conversations + Rewind",
              requirement: "Always unlocked",
              progress: nil, unlocked: true
            )

            // Tier 2 — 100 memories
            tierFeatureRow(
              tier: 2, name: "Memories",
              requirement: "100 memories",
              progress: advancedStats.map { "\($0.memoriesTotal) / 100" },
              unlocked: currentTierLevel >= 2
            )

            // Tier 3 — 100 tasks
            tierFeatureRow(
              tier: 3, name: "Tasks",
              requirement: "100 tasks (todo + done)",
              progress: advancedStats.map { "\($0.tasksTodo + $0.tasksDone) / 100" },
              unlocked: currentTierLevel >= 3
            )

            // Tier 4 — 100 conversations
            tierFeatureRow(
              tier: 4, name: "AI Chat",
              requirement: "100 conversations",
              progress: advancedStats.map { "\($0.conversations) / 100" },
              unlocked: currentTierLevel >= 4
            )

            // Tier 5 — 200 conversations + 2,000 screenshots
            tierFeatureRow(
              tier: 5, name: "Home",
              requirement: "200 conversations + 2K screenshots",
              progress: advancedStats.map {
                "\($0.conversations) / 200 convos, \($0.screenshotsTotal) / 2,000 screenshots"
              },
              unlocked: currentTierLevel >= 5
            )

            // Tier 6 — 300 conversations
            tierFeatureRow(
              tier: 6, name: "Apps",
              requirement: "300 conversations",
              progress: advancedStats.map { "\($0.conversations) / 300" },
              unlocked: currentTierLevel >= 6
            )
          }
        }
      }
    }
  }

}
