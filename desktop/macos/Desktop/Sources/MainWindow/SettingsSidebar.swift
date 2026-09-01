import OmiTheme
import SwiftUI

// MARK: - Search Data Model

enum SettingsDestination: String, CaseIterable, Hashable, Sendable {
  case systemAudio = "general.systemaudio"
  case generalNotifications = "general.notifications"
  case fontSize = "general.fontsize"
  case rewindStorage = "rewind.storage"
  case rewindExcludedApps = "rewind.excludedapps"
  case rewindBattery = "rewind.battery"
  case rewindRetention = "rewind.retention"
  case languageMode = "transcription.languagemode"
  case voiceLanguages = "transcription.voicelanguages"
  case vocabulary = "transcription.vocabulary"
  case conversationLocation = "transcription.location"
  case vadGate = "transcription.vadgate"
  case notificationSettings = "notifications.settings"
  case notificationFrequency = "notifications.frequency"
  case focusNotifications = "notifications.focus"
  case taskNotifications = "notifications.task"
  case insightNotifications = "notifications.insight"
  case memoryNotifications = "notifications.memory"
  case localData = "privacy.encryption"
  case tracking = "privacy.tracking"
  case account = "account.account"
  case currentPlan = "planusage.current"
  case softwareUpdates = "about.updates"
  case automaticUpdates = "about.autoupdates"
  case autoInstallUpdates = "about.autoinstall"
  case updateChannel = "about.channel"
  case version = "about.version"
  case aboutReportIssue = "about.reportissue"
  case resetOnboarding = "advanced.resetonboarding"
  case aiUserProfile = "advanced.aiuserprofile"
  case stats = "advanced.stats"
  case askMode = "advanced.ai.askmode"
  case multipleChats = "advanced.preferences.multichat"
  case launchAtLogin = "advanced.preferences.launchatlogin"
  case advancedReportIssue = "advanced.troubleshooting.reportissue"
  case floatingBar = "floatingbar.show"
  case floatingBarBackground = "floatingbar.background"
  case floatingBarDraggable = "floatingbar.draggable"
  case typedVoiceAnswers = "floatingbar.typedvoiceanswers"
  case screenSharing = "floatingbar.screenshare"
  case voiceSpeed = "floatingbar.voicespeed"
  case openOmiShortcut = "floatingbar.shortcut"
  case pushToTalk = "floatingbar.ptt"
  case pushToTalkDoubleTap = "floatingbar.doubletap"
  case pushToTalkSounds = "floatingbar.pttsounds"

  var section: SettingsContentView.SettingsSection {
    switch self {
    case .systemAudio, .generalNotifications, .fontSize: return .general
    case .rewindStorage, .rewindExcludedApps, .rewindBattery, .rewindRetention: return .rewind
    case .languageMode, .voiceLanguages, .vocabulary, .conversationLocation, .vadGate:
      return .transcription
    case .notificationSettings, .notificationFrequency, .focusNotifications, .taskNotifications,
      .insightNotifications, .memoryNotifications:
      return .notifications
    case .localData, .tracking: return .privacy
    case .account: return .account
    case .currentPlan: return .planUsage
    case .softwareUpdates, .automaticUpdates, .autoInstallUpdates, .updateChannel, .version,
      .aboutReportIssue:
      return .about
    case .resetOnboarding, .aiUserProfile, .stats, .askMode, .multipleChats,
      .launchAtLogin, .advancedReportIssue:
      return .advanced
    case .floatingBar, .floatingBarBackground, .floatingBarDraggable, .typedVoiceAnswers,
      .screenSharing, .voiceSpeed:
      return .floatingBar
    case .openOmiShortcut, .pushToTalk, .pushToTalkDoubleTap, .pushToTalkSounds:
      return .shortcuts
    }
  }

  var revealsProfileAndStats: Bool {
    self == .aiUserProfile || self == .stats
  }

  func isMountedForSearch(systemAudioSupported: Bool) -> Bool {
    self != .systemAudio || systemAudioSupported
  }
}

struct SettingsDeepLinkPresentation: Equatable {
  let settingId: String
  let revealsProfileAndStats: Bool

  init(settingId: String, revealsProfileAndStats: Bool) {
    self.settingId = settingId
    self.revealsProfileAndStats = revealsProfileAndStats
  }

  init?(rawValue: String?) {
    guard let rawValue, !rawValue.isEmpty else { return nil }
    settingId = rawValue
    revealsProfileAndStats =
      SettingsDestination(rawValue: rawValue)?.revealsProfileAndStats == true
  }
}

struct SettingsStatsRefreshState: Equatable {
  private(set) var ownerGeneration: UInt64 = 0

  mutating func ownerDidChange() {
    ownerGeneration &+= 1
  }
}

enum PlanUsageCardIdentity: String, CaseIterable {
  case currentPlan = "planusage.current"
  case purchase = "planusage.purchase"
  case quota = "planusage.quota"
  case quotaLoading = "planusage.quota.loading"
}

struct SettingsSearchItem: Identifiable {
  let id = UUID()
  let name: String
  let subtitle: String
  let keywords: [String]
  let icon: String
  let destination: SettingsDestination

  var section: SettingsContentView.SettingsSection { destination.section }
  var settingId: String { destination.rawValue }

  init(
    name: String,
    subtitle: String,
    keywords: [String],
    section: SettingsContentView.SettingsSection,
    icon: String,
    destination: SettingsDestination
  ) {
    precondition(section == destination.section)
    self.name = name
    self.subtitle = subtitle
    self.keywords = keywords
    self.icon = icon
    self.destination = destination
  }

  var breadcrumb: String {
    return section.rawValue
  }

  static func availableSearchItems(systemAudioSupported: Bool) -> [SettingsSearchItem] {
    allSearchableItems.filter {
      $0.destination.isMountedForSearch(systemAudioSupported: systemAudioSupported)
    }
  }

  static var availableSearchItemsForCurrentOS: [SettingsSearchItem] {
    if #available(macOS 14.4, *) {
      return availableSearchItems(systemAudioSupported: true)
    }
    return availableSearchItems(systemAudioSupported: false)
  }

  static let allSearchableItems: [SettingsSearchItem] = [
    // General
    SettingsSearchItem(
      name: "System Audio", subtitle: "When to record audio from other apps",
      keywords: [
        "system audio", "meeting", "zoom", "google meet", "teams", "call", "capture", "recording",
        "speaker",
      ], section: .general, icon: "speaker.wave.2", destination: .systemAudio),
    SettingsSearchItem(
      name: "Notifications", subtitle: "Proactive alerts and status",
      keywords: ["alerts", "notify"], section: .general, icon: "gearshape",
      destination: .generalNotifications),
    SettingsSearchItem(
      name: "Font Size", subtitle: "Adjust text size across the app",
      keywords: ["text size", "zoom", "scale", "reset"], section: .general, icon: "gearshape",
      destination: .fontSize),

    // Rewind
    SettingsSearchItem(
      name: "Storage", subtitle: "View frame count and disk usage",
      keywords: ["frames", "storage", "disk", "space", "gb"], section: .rewind,
      icon: "clock.arrow.circlepath", destination: .rewindStorage),
    SettingsSearchItem(
      name: "Excluded Apps", subtitle: "Screen capture is paused when these apps are active",
      keywords: ["exclude", "ignore", "block apps", "blocklist", "reset to defaults"],
      section: .rewind, icon: "clock.arrow.circlepath", destination: .rewindExcludedApps),
    SettingsSearchItem(
      name: "Battery Optimization", subtitle: "Saves power by reducing screenshot frequency",
      keywords: ["battery", "power", "energy", "low power"], section: .rewind,
      icon: "clock.arrow.circlepath", destination: .rewindBattery),
    SettingsSearchItem(
      name: "Data Retention", subtitle: "How long to keep screen recordings",
      keywords: ["retention", "storage", "delete old", "keep data"], section: .rewind,
      icon: "clock.arrow.circlepath", destination: .rewindRetention),

    // Transcription
    SettingsSearchItem(
      name: "Language Mode", subtitle: "Choose single or multi-language transcription",
      keywords: ["language", "multilingual", "single language"], section: .transcription,
      icon: "waveform", destination: .languageMode),
    SettingsSearchItem(
      name: "Voice Assistant Languages",
      subtitle: "Languages you speak to Omi over push-to-talk",
      keywords: ["voice", "push to talk", "ptt", "language", "russian", "multilingual"],
      section: .transcription, icon: "person.wave.2",
      destination: .voiceLanguages),
    SettingsSearchItem(
      name: "Custom Vocabulary",
      subtitle: "Improve recognition of names, brands, and technical terms",
      keywords: ["vocabulary", "words", "custom words", "dictionary"], section: .transcription,
      icon: "waveform", destination: .vocabulary),
    SettingsSearchItem(
      name: "Conversation Location",
      subtitle: "Optionally save one location when a conversation starts",
      keywords: ["location", "conversation", "snapshot", "privacy"], section: .transcription,
      icon: "location", destination: .conversationLocation),
    SettingsSearchItem(
      name: "Local VAD Gate", subtitle: "Skip silence to reduce transcription cost",
      keywords: ["vad", "silence", "gate", "cost", "transcription"], section: .transcription,
      icon: "waveform", destination: .vadGate),

    // Notifications
    SettingsSearchItem(
      name: "Notification Settings", subtitle: "Control how often you receive notifications",
      keywords: ["frequency", "alerts"], section: .notifications, icon: "bell",
      destination: .notificationSettings),
    SettingsSearchItem(
      name: "Notification Frequency", subtitle: "How often to receive notifications",
      keywords: ["frequency", "how often", "interval"], section: .notifications, icon: "bell",
      destination: .notificationFrequency),
    SettingsSearchItem(
      name: "Focus Notifications", subtitle: "Show notification on focus changes",
      keywords: ["focus", "distraction", "notify focus"], section: .notifications, icon: "bell",
      destination: .focusNotifications),
    SettingsSearchItem(
      name: "Task Notifications",
      subtitle: "Allow interruptions when a task needs attention",
      keywords: ["task", "action item", "notify task", "interruption", "proactive"],
      section: .notifications, icon: "bell",
      destination: .taskNotifications),
    SettingsSearchItem(
      name: "Insight Notifications", subtitle: "Show notification when an insight is generated",
      keywords: ["insight", "insights", "notify insight"], section: .notifications, icon: "bell",
      destination: .insightNotifications),
    SettingsSearchItem(
      name: "Memory Notifications", subtitle: "Show notification when a memory is extracted",
      keywords: ["memory", "facts", "notify memory"], section: .notifications, icon: "bell",
      destination: .memoryNotifications),
    // Privacy
    SettingsSearchItem(
      name: "Local Data", subtitle: "Local storage for conversation transcripts and metadata",
      keywords: ["local", "database", "storage"], section: .privacy, icon: "lock.shield",
      destination: .localData),
    SettingsSearchItem(
      name: "What We Track", subtitle: "View analytics and telemetry data we collect",
      keywords: ["tracking", "analytics", "telemetry", "data collection"], section: .privacy,
      icon: "lock.shield", destination: .tracking),

    // Account
    SettingsSearchItem(
      name: "Account", subtitle: "Your profile and email", keywords: ["profile", "email"],
      section: .account, icon: "person.circle", destination: .account),

    // Plan and Usage
    SettingsSearchItem(
      name: "Current Plan", subtitle: "See your current subscription and renewal status",
      keywords: ["current plan", "renewal", "billing"], section: .planUsage, icon: "creditcard",
      destination: .currentPlan),
    // About
    SettingsSearchItem(
      name: "Software Updates", subtitle: "Check for and manage app updates",
      keywords: ["update", "auto update", "sparkle", "version", "check for updates", "check now"],
      section: .about, icon: "info.circle", destination: .softwareUpdates),
    SettingsSearchItem(
      name: "Automatic Updates", subtitle: "Check for updates automatically in the background",
      keywords: ["auto check", "background updates", "check automatically"], section: .about,
      icon: "info.circle", destination: .automaticUpdates),
    SettingsSearchItem(
      name: "Auto-Install Updates",
      subtitle: "Automatically download and install updates when available",
      keywords: ["auto install", "automatic install", "download updates", "install updates"],
      section: .about, icon: "info.circle", destination: .autoInstallUpdates),
    SettingsSearchItem(
      name: "Update Channel", subtitle: "Choose between stable and beta update channels",
      keywords: ["channel", "beta", "stable", "release channel"], section: .about,
      icon: "info.circle", destination: .updateChannel),
    SettingsSearchItem(
      name: "Version Info", subtitle: "Current app version and build number",
      keywords: ["version", "build", "app version", "build number"], section: .about,
      icon: "info.circle", destination: .version),
    SettingsSearchItem(
      name: "Report an Issue", subtitle: "Help us improve omi",
      keywords: ["bug", "feedback", "report", "issue"], section: .about, icon: "info.circle",
      destination: .aboutReportIssue),

    // Advanced subsections
    SettingsSearchItem(
      name: "Reset Onboarding", subtitle: "Restart setup wizard for this app build only",
      keywords: ["reset", "onboarding", "restart", "setup"], section: .advanced,
      icon: "arrow.counterclockwise", destination: .resetOnboarding),
    SettingsSearchItem(
      name: "AI User Profile", subtitle: "AI-generated summary of your preferences and habits",
      keywords: ["profile", "generate", "generate now", "regenerate"], section: .advanced,
      icon: "brain", destination: .aiUserProfile),
    SettingsSearchItem(
      name: "Your Stats", subtitle: "View your usage statistics and activity",
      keywords: ["statistics", "conversations", "usage"], section: .advanced, icon: "chart.bar",
      destination: .stats),
    SettingsSearchItem(
      name: "Ask Mode", subtitle: "Show the per-turn Ask and Act choice in chat",
      keywords: ["ask", "act", "read only", "chat"], section: .advanced,
      icon: "cpu", destination: .askMode),
    SettingsSearchItem(
      name: "Ask omi Floating Bar",
      subtitle: "Configure the floating bar appearance and visibility",
      keywords: ["floating bar", "ask omi", "show bar"], section: .floatingBar, icon: "sparkles",
      destination: .floatingBar),
    SettingsSearchItem(
      name: "Background Style", subtitle: "Toggle between solid and transparent background",
      keywords: ["background", "solid", "transparent", "blur"], section: .floatingBar,
      icon: "sparkles", destination: .floatingBarBackground),
    SettingsSearchItem(
      name: "Draggable Floating Bar",
      subtitle: "Allow repositioning the floating bar by dragging it",
      keywords: ["drag", "move", "reposition", "draggable"], section: .floatingBar,
      icon: "sparkles", destination: .floatingBarDraggable),
    SettingsSearchItem(
      name: "Typed Questions", subtitle: "Speak replies aloud for typed floating-bar questions",
      keywords: ["typed", "text", "speech", "tts", "audio answers"], section: .floatingBar,
      icon: "sparkles", destination: .typedVoiceAnswers),
    SettingsSearchItem(
      name: "Screen Sharing in Chat",
      subtitle: "Let Ask Omi capture your screen when you ask about it",
      keywords: ["screenshot", "screen", "capture", "share screen", "vision", "see my screen"],
      section: .floatingBar, icon: "camera.viewfinder", destination: .screenSharing),
    SettingsSearchItem(
      name: "Voice Speed", subtitle: "Adjust the playback speed for voice replies",
      keywords: ["voice speed", "speech speed", "playback speed", "tts speed"],
      section: .floatingBar, icon: "sparkles", destination: .voiceSpeed),
    SettingsSearchItem(
      name: "Shortcuts", subtitle: "Configure Open Omi and push-to-talk keyboard shortcuts",
      keywords: ["shortcuts", "keyboard", "hotkeys", "push to talk"], section: .shortcuts,
      icon: "keyboard", destination: .openOmiShortcut),
    SettingsSearchItem(
      name: "Open Omi Shortcut", subtitle: "Global shortcut to open the Omi app from anywhere",
      keywords: ["shortcut", "hotkey", "keyboard", "global shortcut"], section: .shortcuts,
      icon: "keyboard", destination: .openOmiShortcut),
    SettingsSearchItem(
      name: "Push to Talk", subtitle: "Hold a key to speak, release to send your question to AI",
      keywords: ["push to talk", "ptt", "hold to talk", "microphone key"], section: .shortcuts,
      icon: "keyboard", destination: .pushToTalk),
    SettingsSearchItem(
      name: "Double-tap for Locked Mode",
      subtitle: "Double-tap the push-to-talk key to keep listening hands-free",
      keywords: ["double tap", "locked mode", "hands free", "listening"], section: .shortcuts,
      icon: "keyboard", destination: .pushToTalkDoubleTap),
    SettingsSearchItem(
      name: "Push-to-Talk Sounds",
      subtitle: "Play audio feedback when starting and ending voice input",
      keywords: ["sounds", "audio feedback", "ptt sounds"], section: .shortcuts, icon: "keyboard",
      destination: .pushToTalkSounds),
    SettingsSearchItem(
      name: "Multiple Chat Sessions", subtitle: "Create separate chat threads",
      keywords: ["multi chat", "threads"], section: .advanced, icon: "slider.horizontal.3",
      destination: .multipleChats),
    SettingsSearchItem(
      name: "Launch at Login", subtitle: "Start omi automatically when you log in",
      keywords: ["startup", "login", "boot"], section: .advanced, icon: "slider.horizontal.3",
      destination: .launchAtLogin),
    SettingsSearchItem(
      name: "Report Issue", subtitle: "Send app logs and report a problem",
      keywords: ["bug", "feedback", "logs", "report"], section: .advanced,
      icon: "wrench.and.screwdriver", destination: .advancedReportIssue),
  ]
}

enum SettingsSidebarMetrics {
  static let expandedWidth: CGFloat = 260
  static let horizontalInset: CGFloat = OmiSpacing.sm
  static let itemAvailableWidth = expandedWidth - 2 * horizontalInset
}

/// Settings sidebar that replaces the main sidebar when in settings
struct SettingsSidebar: View {
  @Binding var selectedSection: SettingsContentView.SettingsSection
  @Binding var highlightedSettingId: String?
  let onBack: () -> Void

  @State private var isBackHovered = false
  @State private var searchQuery = ""
  @FocusState private var isSearchFocused: Bool

  private let iconWidth: CGFloat = 20
  // Merged nav: `.account` hosts Account & Plan (renders `.planUsage` content
  // too) and `.notifications` hosts Notifications & Privacy (renders `.privacy`
  // content too). The absorbed cases stay routable for deep links/automation
  // and highlight their merged item via `sidebarItem`.
  static let visibleSections: [SettingsContentView.SettingsSection] = [
    .general,
    .account,
    .transcription,
    .floatingBar,
    .notifications,
    .rewind,
    .shortcuts,
    .advanced,
    .about,
  ]

  private var filteredSearchItems: [SettingsSearchItem] {
    guard !searchQuery.isEmpty else { return [] }
    let words = searchQuery.lowercased().split(separator: " ").map(String.init)
    guard !words.isEmpty else { return [] }
    return SettingsSearchItem.availableSearchItemsForCurrentOS.filter { item in
      let nameLower = item.name.lowercased()
      let subtitleLower = item.subtitle.lowercased()
      let keywordsLower = item.keywords.map { $0.lowercased() }
      return words.allSatisfy { word in
        nameLower.contains(word) || subtitleLower.contains(word)
          || keywordsLower.contains(where: { $0.contains(word) })
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Back button header
      backButton
        .padding(.top, OmiSpacing.md)
        .padding(.horizontal, OmiSpacing.lg)

      Spacer().frame(height: OmiSpacing.xxl)

      // Settings title
      Text("Settings")
        .scaledFont(size: OmiType.heading, weight: .bold)
        .foregroundColor(OmiColors.textPrimary)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.bottom, OmiSpacing.md)

      // Search field
      searchField
        .padding(.horizontal, OmiSpacing.md)
        .padding(.bottom, OmiSpacing.md)

      if searchQuery.isEmpty {
        // Normal settings sections
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
            ForEach(Self.visibleSections, id: \.self) { section in
              SettingsSidebarItem(
                section: section,
                isSelected: selectedSection.sidebarItem == section,
                iconWidth: iconWidth,
                onTap: {
                  OmiMotion.withGated(.easeInOut(duration: 0.15)) {
                    selectedSection = section
                  }
                }
              )

            }
          }
        }
        .padding(.horizontal, OmiSpacing.sm)
      } else {
        // Search results
        searchResultsList
          .padding(.horizontal, OmiSpacing.sm)
      }

      Spacer()
    }
    .frame(width: SettingsSidebarMetrics.expandedWidth)
    .background(OmiColors.backgroundPrimary)
  }

  private var searchField: some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: "magnifyingglass")
        .scaledFont(size: OmiType.body)
        .foregroundColor(isSearchFocused ? OmiColors.accent : OmiColors.textTertiary)
        .omiAnimation(.easeInOut(duration: 0.15), value: isSearchFocused)

      TextField("Search settings...", text: $searchQuery)
        .textFieldStyle(.plain)
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textPrimary)
        .focused($isSearchFocused)

      if !searchQuery.isEmpty {
        Button {
          searchQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, OmiSpacing.sm)
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
        .fill(OmiColors.backgroundTertiary)
        .overlay(
          RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
            .stroke(
              isSearchFocused ? OmiColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    )
  }

  private var searchResultsList: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
        if filteredSearchItems.isEmpty {
          Text("No results")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
            .padding(.horizontal, OmiSpacing.md)
            .padding(.vertical, OmiSpacing.xl)
        } else {
          ForEach(filteredSearchItems) { item in
            SettingsSearchResultRow(item: item) {
              OmiMotion.withGated(.easeInOut(duration: 0.15)) {
                selectedSection = item.section
              }
              searchQuery = ""
              let targetId = item.settingId
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                highlightedSettingId = targetId
              }
            }
          }
        }
      }
    }
  }

  private var backButton: some View {
    Button(action: onBack) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: "chevron.left")
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(OmiColors.textSecondary)

        Text("Back")
          .scaledFont(size: OmiType.body, weight: .medium)
          .foregroundColor(OmiColors.textSecondary)

        Spacer()
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
          .fill(isBackHovered ? OmiColors.backgroundTertiary.opacity(0.5) : Color.clear)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isBackHovered = hovering
    }
  }
}

// MARK: - Settings Sidebar Item
struct SettingsSidebarItem: View {
  let section: SettingsContentView.SettingsSection
  let isSelected: Bool
  let iconWidth: CGFloat
  let onTap: () -> Void

  @State private var isHovered = false

  private var icon: String {
    switch section {
    case .general: return "gearshape"
    case .rewind: return "clock.arrow.circlepath"
    case .transcription: return "waveform"
    case .notifications: return "bell"
    case .privacy: return "lock.shield"
    case .account: return "person.circle"
    case .planUsage: return "creditcard"
    case .floatingBar: return "sparkles"
    case .shortcuts: return "keyboard"
    case .advanced: return "chart.bar"
    case .about: return "info.circle"
    }
  }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: OmiSpacing.md) {
        Image(systemName: icon)
          .scaledFont(size: OmiType.subheading)
          .foregroundColor(isSelected ? OmiColors.textPrimary : OmiColors.textTertiary)
          .frame(width: iconWidth)

        Text(section.displayTitle)
          .scaledFont(size: OmiType.body, weight: isSelected ? .medium : .regular)
          .foregroundColor(isSelected ? OmiColors.textPrimary : OmiColors.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(1)

        Spacer()
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
          .fill(
            isSelected
              ? OmiColors.backgroundTertiary.opacity(0.8)
              : (isHovered ? OmiColors.backgroundTertiary.opacity(0.5) : Color.clear))
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}

// MARK: - Settings Subsection Item
struct SettingsSubsectionItem: View {
  let subsection: SettingsContentView.AdvancedSubsection
  let isSelected: Bool
  let iconWidth: CGFloat
  let onTap: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: OmiSpacing.sm) {
        // Indentation spacer
        Spacer()
          .frame(width: iconWidth + 12)

        Image(systemName: subsection.icon)
          .scaledFont(size: OmiType.body)
          .foregroundColor(isSelected ? OmiColors.textPrimary : OmiColors.textTertiary)
          .frame(width: 16)

        Text(subsection.rawValue)
          .scaledFont(size: OmiType.body, weight: isSelected ? .medium : .regular)
          .foregroundColor(isSelected ? OmiColors.textPrimary : OmiColors.textSecondary)

        Spacer()
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
          .fill(
            isSelected
              ? OmiColors.backgroundTertiary.opacity(0.6)
              : (isHovered ? OmiColors.backgroundTertiary.opacity(0.3) : Color.clear))
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}

// MARK: - Settings Search Result Row
struct SettingsSearchResultRow: View {
  let item: SettingsSearchItem
  let onTap: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: item.icon)
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textTertiary)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(item.name)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)

          Text(item.breadcrumb)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
        }

        Spacer()
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
          .fill(isHovered ? OmiColors.backgroundTertiary.opacity(0.5) : Color.clear)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}

// MARK: - Setting Highlight Modifier

struct SettingHighlightModifier: ViewModifier {
  let settingId: String
  @Binding var highlightedSettingId: String?
  @State private var isHighlighted = false

  init(settingId: String, highlightedSettingId: Binding<String?>) {
    self.settingId = settingId
    self._highlightedSettingId = highlightedSettingId
  }

  init(destination: SettingsDestination, highlightedSettingId: Binding<String?>) {
    self.settingId = destination.rawValue
    self._highlightedSettingId = highlightedSettingId
  }

  func body(content: Content) -> some View {
    content
      .id(settingId)
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
          .fill(isHighlighted ? OmiColors.accent.opacity(0.12) : Color.clear)
          .omiAnimation(.easeInOut(duration: 0.3), value: isHighlighted)
          .allowsHitTesting(false)
      )
      .onChange(of: highlightedSettingId) { _, newId in
        highlightIfNeeded(newId)
      }
      .onAppear { highlightIfNeeded(highlightedSettingId) }
  }

  private func highlightIfNeeded(_ candidate: String?) {
    guard SettingsDeepLinkPresentation(rawValue: candidate)?.settingId == settingId,
      !isHighlighted
    else { return }
    OmiMotion.withGated { isHighlighted = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      OmiMotion.withGated(.easeInOut(duration: 0.5)) { isHighlighted = false }
      if highlightedSettingId == settingId { highlightedSettingId = nil }
    }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    SettingsSidebar(
      selectedSection: .constant(.advanced),
      highlightedSettingId: .constant(nil),
      onBack: {}
    )
    .preferredColorScheme(.dark)
  }
#endif
