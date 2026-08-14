import AppKit
import Combine
import GRDB
import OmiTheme
import SwiftUI

// MARK: - Imports Section

struct ImportConnector: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let description: String
  let brand: ConnectorBrand
  let statusText: String
  let metricText: String?
  let actionTitle: String
  let isConnected: Bool

  static let all: [ImportConnector] = [
    ImportConnector(
      id: "calendar",
      title: "Calendar",
      subtitle: "Google Calendar",
      description: "Import events and recurring routines.",
      brand: .calendar,
      statusText: "Not connected",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
    ImportConnector(
      id: "email",
      title: "Email",
      subtitle: "Gmail",
      description: "Import email history and follow-ups.",
      brand: .gmail,
      statusText: "Not connected",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
    ImportConnector(
      id: "local-files",
      title: "Local files",
      subtitle: "This Mac",
      description: "Index documents, code, and working folders.",
      brand: .localFiles,
      statusText: "Not connected",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
    ImportConnector(
      id: "apple-notes",
      title: "Apple Notes",
      subtitle: "Private notes",
      description: "Import notes and private written context.",
      brand: .appleNotes,
      statusText: "Not connected",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
    ImportConnector(
      id: "x",
      title: "X (Twitter)",
      subtitle: "Your posts & bookmarks",
      description: "Connect your X account so Omi learns from your tweets and bookmarks.",
      brand: .x,
      statusText: "Not connected",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
    ImportConnector(
      id: "chatgpt",
      title: "ChatGPT",
      subtitle: "Memory import",
      description: "Paste a memory export into Omi.",
      brand: .chatgpt,
      statusText: "Optional",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
    ImportConnector(
      id: "claude",
      title: "Claude",
      subtitle: "Memory import",
      description: "Paste a memory export into Omi.",
      brand: .claude,
      statusText: "Optional",
      metricText: nil,
      actionTitle: "Connect",
      isConnected: false
    ),
  ]
}

@MainActor
final class ImportConnectorStatusStore: ObservableObject {
  struct ConnectorMetrics {
    var sourceCount: Int?
    var memoryCount: Int?
    var lastSyncedAt: Date?
    var lastDeltaCount: Int?
    var availabilityText: String?
  }

  struct Snapshot {
    let isConnected: Bool
    let actionTitle: String
    let primaryText: String
    let secondaryText: String?
  }

  @Published private var metricsByID: [String: ConnectorMetrics] = [:]
  let connectorDidSync = PassthroughSubject<String, Never>()

  private let defaults: UserDefaults
  private let sourceCountKeyPrefix = "appsImportConnectorSourceCount."
  private let memoryCountKeyPrefix = "appsImportConnectorMemoryCount."
  private let lastSyncedAtKeyPrefix = "appsImportConnectorLastSyncedAt."
  private let lastDeltaCountKeyPrefix = "appsImportConnectorLastDeltaCount."
  private let hasLastDeltaKeyPrefix = "appsImportConnectorHasLastDelta."
  private let availabilityTextKeyPrefix = "appsImportConnectorAvailabilityText."
  private let manualConnectorIDs: Set<String> = ["chatgpt", "claude"]
  private let onboardingChatGPTImportedMemoriesKey = "onboardingChatGPTImportedMemoriesCount"
  private let onboardingClaudeImportedMemoriesKey = "onboardingClaudeImportedMemoriesCount"
  private var sessionUserID: String?

  init(defaults: UserDefaults = .standard, sessionUserID: String? = nil) {
    self.defaults = defaults
    self.sessionUserID = Self.normalizedUserID(
      sessionUserID ?? defaults.string(forKey: .authUserId)
    )
    load()
  }

  func setSessionUserID(_ userID: String?) {
    let userID = Self.normalizedUserID(userID)
    guard userID != sessionUserID else { return }
    sessionUserID = userID
    load()
  }

  func snapshot(for connector: ImportConnector) -> Snapshot {
    let metrics = metricsByID[connector.id] ?? ConnectorMetrics()
    let isConnected = isConnected(connector: connector, metrics: metrics)
    let actionTitle: String
    if manualConnectorIDs.contains(connector.id) {
      actionTitle = isConnected ? "Update" : "Connect"
    } else {
      actionTitle = isConnected ? "Sync now" : "Connect"
    }

    return Snapshot(
      isConnected: isConnected,
      actionTitle: actionTitle,
      primaryText: primaryText(for: connector, metrics: metrics, isConnected: isConnected),
      secondaryText: secondaryText(for: connector, metrics: metrics, isConnected: isConnected)
    )
  }

  func markSynced(
    connectorID: String,
    sourceCount: Int? = nil,
    memoryCount: Int? = nil,
    lastDeltaCount: Int? = nil,
    availabilityText: String? = nil,
    syncedAt: Date = Date()
  ) {
    var metrics = metricsByID[connectorID] ?? ConnectorMetrics()
    if let sourceCount {
      metrics.sourceCount = max(sourceCount, 0)
      defaults.set(metrics.sourceCount, forKey: storageKey(prefix: sourceCountKeyPrefix, connectorID: connectorID))
    }
    if let memoryCount {
      metrics.memoryCount = max(memoryCount, 0)
      defaults.set(metrics.memoryCount, forKey: storageKey(prefix: memoryCountKeyPrefix, connectorID: connectorID))
    }
    metrics.lastSyncedAt = syncedAt
    defaults.set(
      syncedAt.timeIntervalSince1970,
      forKey: storageKey(prefix: lastSyncedAtKeyPrefix, connectorID: connectorID)
    )
    metrics.lastDeltaCount = lastDeltaCount
    defaults.set(
      lastDeltaCount != nil,
      forKey: storageKey(prefix: hasLastDeltaKeyPrefix, connectorID: connectorID)
    )
    if let lastDeltaCount {
      defaults.set(
        lastDeltaCount,
        forKey: storageKey(prefix: lastDeltaCountKeyPrefix, connectorID: connectorID)
      )
    } else {
      defaults.removeObject(forKey: storageKey(prefix: lastDeltaCountKeyPrefix, connectorID: connectorID))
    }
    if let availabilityText {
      metrics.availabilityText = availabilityText
      defaults.set(
        availabilityText,
        forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: connectorID)
      )
    }
    metricsByID[connectorID] = metrics
    connectorDidSync.send(connectorID)
  }

  private func clearStoredMetrics(for connectorID: String) {
    defaults.removeObject(forKey: storageKey(prefix: sourceCountKeyPrefix, connectorID: connectorID))
    defaults.removeObject(forKey: storageKey(prefix: memoryCountKeyPrefix, connectorID: connectorID))
    defaults.removeObject(forKey: storageKey(prefix: lastSyncedAtKeyPrefix, connectorID: connectorID))
    defaults.removeObject(forKey: storageKey(prefix: lastDeltaCountKeyPrefix, connectorID: connectorID))
    defaults.removeObject(forKey: storageKey(prefix: hasLastDeltaKeyPrefix, connectorID: connectorID))
    defaults.removeObject(forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: connectorID))
    metricsByID[connectorID] = ConnectorMetrics()
  }

  func refresh() async {
    refreshPersistedManualImportMetrics()
    await refreshLocalFilesMetrics()
    await refreshAppleNotesMetrics()
  }

  func refreshPersistedManualImportMetrics() {
    hydrateLegacyManualImports()
  }

  private func load() {
    metricsByID = [:]
    guard sessionUserID != nil else { return }
    for connector in ImportConnector.all {
      migrateLegacyMetricsIfNeeded(connectorID: connector.id)
      var metrics = ConnectorMetrics()

      let sourceCountKey = storageKey(prefix: sourceCountKeyPrefix, connectorID: connector.id)
      let memoryCountKey = storageKey(prefix: memoryCountKeyPrefix, connectorID: connector.id)
      let lastSyncedAtKey = storageKey(prefix: lastSyncedAtKeyPrefix, connectorID: connector.id)
      let hasLastDeltaKey = storageKey(prefix: hasLastDeltaKeyPrefix, connectorID: connector.id)
      let lastDeltaCountKey = storageKey(prefix: lastDeltaCountKeyPrefix, connectorID: connector.id)
      let availabilityTextKey = storageKey(prefix: availabilityTextKeyPrefix, connectorID: connector.id)

      if defaults.object(forKey: sourceCountKey) != nil {
        metrics.sourceCount = defaults.integer(forKey: sourceCountKey)
      }
      if defaults.object(forKey: memoryCountKey) != nil {
        metrics.memoryCount = defaults.integer(forKey: memoryCountKey)
      }
      if defaults.object(forKey: lastSyncedAtKey) != nil {
        let timestamp = defaults.double(forKey: lastSyncedAtKey)
        if timestamp > 0 {
          metrics.lastSyncedAt = Date(timeIntervalSince1970: timestamp)
        }
      }
      if defaults.bool(forKey: hasLastDeltaKey) {
        metrics.lastDeltaCount = defaults.integer(forKey: lastDeltaCountKey)
      }
      metrics.availabilityText = defaults.string(forKey: availabilityTextKey)

      metricsByID[connector.id] = metrics
    }

    hydrateLegacyManualImports()

    // A remembered path is not enough to call Apple Notes connected. The
    // status becomes connected only after the reader proves the store is readable.
  }

  private func hydrateLegacyManualImports() {
    guard let sessionUserID else { return }
    let ownerUserID = Self.normalizedUserID(defaults.string(forKey: .onboardingMemoryImportOwnerUserId))
    let legacyChatGPTCount = defaults.integer(forKey: onboardingChatGPTImportedMemoriesKey)
    let legacyClaudeCount = defaults.integer(forKey: onboardingClaudeImportedMemoriesKey)
    if ownerUserID == nil,
      legacyChatGPTCount > 0 || legacyClaudeCount > 0
    {
      defaults.set(sessionUserID, forKey: .onboardingMemoryImportOwnerUserId)
    }

    let resolvedOwnerUserID = Self.normalizedUserID(
      defaults.string(forKey: .onboardingMemoryImportOwnerUserId)
    )
    guard resolvedOwnerUserID == sessionUserID else { return }

    let chatGPTMemoryCountKey = storageKey(prefix: memoryCountKeyPrefix, connectorID: "chatgpt")
    if legacyChatGPTCount > 0,
      defaults.object(forKey: chatGPTMemoryCountKey) == nil
    {
      var metrics = metricsByID["chatgpt"] ?? ConnectorMetrics()
      metrics.memoryCount = legacyChatGPTCount
      metrics.availabilityText = "Imported during onboarding"
      metricsByID["chatgpt"] = metrics
      defaults.set(legacyChatGPTCount, forKey: chatGPTMemoryCountKey)
      defaults.set(
        "Imported during onboarding",
        forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: "chatgpt")
      )
    }

    let claudeMemoryCountKey = storageKey(prefix: memoryCountKeyPrefix, connectorID: "claude")
    if legacyClaudeCount > 0,
      defaults.object(forKey: claudeMemoryCountKey) == nil
    {
      var metrics = metricsByID["claude"] ?? ConnectorMetrics()
      metrics.memoryCount = legacyClaudeCount
      metrics.availabilityText = "Imported during onboarding"
      metricsByID["claude"] = metrics
      defaults.set(legacyClaudeCount, forKey: claudeMemoryCountKey)
      defaults.set(
        "Imported during onboarding",
        forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: "claude")
      )
    }
  }

  private func storageKey(prefix: String, connectorID: String) -> String {
    guard let sessionUserID else { return prefix + connectorID }
    return "\(prefix)user.\(sessionUserID).\(connectorID)"
  }

  private func migrateLegacyMetricsIfNeeded(connectorID: String) {
    guard sessionUserID != nil else { return }
    for prefix in [
      sourceCountKeyPrefix,
      memoryCountKeyPrefix,
      lastSyncedAtKeyPrefix,
      lastDeltaCountKeyPrefix,
      hasLastDeltaKeyPrefix,
      availabilityTextKeyPrefix,
    ] {
      let legacyKey = prefix + connectorID
      let scopedKey = storageKey(prefix: prefix, connectorID: connectorID)
      if defaults.object(forKey: scopedKey) == nil,
        let legacyValue = defaults.object(forKey: legacyKey)
      {
        defaults.set(legacyValue, forKey: scopedKey)
      }
      defaults.removeObject(forKey: legacyKey)
    }
  }

  private static func normalizedUserID(_ userID: String?) -> String? {
    let trimmed = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private func refreshLocalFilesMetrics() async {
    guard let dbQueue = await RewindDatabase.shared.getDatabaseQueue() else { return }

    do {
      let result: (count: Int, lastIndexedAt: Date?) = try await dbQueue.read { db in
        guard
          let row = try Row.fetchOne(
            db,
            sql: """
                  SELECT COUNT(*) AS count, MAX(indexedAt) AS lastIndexedAt
                  FROM indexed_files
              """
          )
        else {
          return (0, nil)
        }
        let count: Int = row["count"] ?? 0
        let lastIndexedAt: Date? = row["lastIndexedAt"]
        return (count, lastIndexedAt)
      }

      var metrics = metricsByID["local-files"] ?? ConnectorMetrics()
      metrics.sourceCount = result.count
      defaults.set(
        result.count,
        forKey: storageKey(prefix: sourceCountKeyPrefix, connectorID: "local-files")
      )
      if metrics.lastSyncedAt == nil, let lastIndexedAt = result.lastIndexedAt {
        metrics.lastSyncedAt = lastIndexedAt
        defaults.set(
          lastIndexedAt.timeIntervalSince1970,
          forKey: storageKey(prefix: lastSyncedAtKeyPrefix, connectorID: "local-files")
        )
      }
      if metrics.lastSyncedAt != nil || result.count > 0 {
        metrics.availabilityText = "On-device index"
        defaults.set(
          "On-device index",
          forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: "local-files")
        )
      } else {
        metrics.availabilityText = nil
        defaults.removeObject(
          forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: "local-files")
        )
      }
      metricsByID["local-files"] = metrics
    } catch {
      log("ImportConnectorStatusStore: Failed to refresh local files metrics: \(error)")
    }
  }

  private func refreshAppleNotesMetrics() async {
    let status = await AppleNotesReaderService.shared.connectionStatus(maxResults: 250)
    switch status {
    case .connected(let noteCount, _):
      var metrics = metricsByID["apple-notes"] ?? ConnectorMetrics()
      metrics.sourceCount = noteCount
      defaults.set(
        noteCount,
        forKey: storageKey(prefix: sourceCountKeyPrefix, connectorID: "apple-notes")
      )
      if metrics.lastSyncedAt == nil {
        let syncedAt = Date()
        metrics.lastSyncedAt = syncedAt
        defaults.set(
          syncedAt.timeIntervalSince1970,
          forKey: storageKey(prefix: lastSyncedAtKeyPrefix, connectorID: "apple-notes")
        )
      }
      metrics.availabilityText = "Private notes accessible"
      defaults.set(
        "Private notes accessible",
        forKey: storageKey(prefix: availabilityTextKeyPrefix, connectorID: "apple-notes")
      )
      metricsByID["apple-notes"] = metrics
    case .needsAccess(_, let reasonCode), .error(_, let reasonCode):
      log("ImportConnectorStatusStore: Apple Notes refresh unavailable code=\(reasonCode)")
      clearStoredMetrics(for: "apple-notes")
    }
  }

  private func isConnected(connector: ImportConnector, metrics: ConnectorMetrics) -> Bool {
    if metrics.lastSyncedAt != nil {
      return true
    }

    return manualConnectorIDs.contains(connector.id) && (metrics.memoryCount ?? 0) > 0
  }

  private func primaryText(
    for connector: ImportConnector,
    metrics: ConnectorMetrics,
    isConnected: Bool
  ) -> String {
    if let sourceCount = metrics.sourceCount {
      if let memoryCount = metrics.memoryCount, memoryCount > 0 {
        return
          "\(sourceCount.formatted()) \(sourceLabel(for: connector, count: sourceCount)) • \(memoryCount.formatted()) memories"
      }
      if isConnected || sourceCount > 0 {
        return "\(sourceCount.formatted()) \(sourceLabel(for: connector, count: sourceCount))"
      }
    }

    if let memoryCount = metrics.memoryCount, memoryCount > 0 {
      return "\(memoryCount.formatted()) memories imported"
    }

    if isConnected, let availabilityText = metrics.availabilityText {
      return availabilityText
    }

    return connector.statusText
  }

  private func secondaryText(
    for connector: ImportConnector,
    metrics: ConnectorMetrics,
    isConnected: Bool
  ) -> String? {
    if let lastSyncedAt = metrics.lastSyncedAt {
      var text = "Synced \(relativeTimestamp(lastSyncedAt))"
      if let lastDeltaCount = metrics.lastDeltaCount, lastDeltaCount > 0 {
        text += " • +\(lastDeltaCount.formatted()) new"
      }
      return text
    }

    if let availabilityText = metrics.availabilityText,
      availabilityText != primaryText(for: connector, metrics: metrics, isConnected: isConnected)
    {
      return availabilityText
    }

    if let metricText = connector.metricText {
      return metricText
    }

    return manualConnectorIDs.contains(connector.id) && isConnected ? "Imported earlier" : nil
  }

  private func sourceLabel(for connector: ImportConnector, count: Int) -> String {
    switch connector.id {
    case "calendar":
      return count == 1 ? "event" : "events"
    case "email":
      return count == 1 ? "email" : "emails"
    case "local-files":
      return count == 1 ? "file indexed" : "files indexed"
    case "apple-notes":
      return count == 1 ? "note" : "notes"
    case "x":
      return count == 1 ? "post" : "posts"
    default:
      return count == 1 ? "item" : "items"
    }
  }

  private func relativeTimestamp(_ date: Date) -> String {
    RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
  }
}

struct ImportsSection: View {
  private let connectors = ImportConnector.all
  @ObservedObject var statusStore: ImportConnectorStatusStore
  let onSelectConnector: (ImportConnector) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      Text("Imports")
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 260), spacing: OmiSpacing.md)],
        alignment: .leading,
        spacing: OmiSpacing.md
      ) {
        ForEach(connectors) { connector in
          ImportConnectorCard(
            connector: connector,
            snapshot: statusStore.snapshot(for: connector)
          ) {
            onSelectConnector(connector)
          }
        }
      }
    }
  }
}

struct ImportConnectorRow: View {
  let connector: ImportConnector
  let snapshot: ImportConnectorStatusStore.Snapshot
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        ConnectorBrandIcon(brand: connector.brand, size: 34, cornerRadius: 9)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(connector.title)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)
            .lineLimit(1)

          Text(connector.description)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        Spacer(minLength: 12)

        ImportConnectorActionButton(title: snapshot.actionTitle, isConnected: snapshot.isConnected)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .background(isHovering ? OmiColors.backgroundSecondary : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

struct ImportConnectorCard: View {
  let connector: ImportConnector
  let snapshot: ImportConnectorStatusStore.Snapshot
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack(spacing: OmiSpacing.md) {
          ConnectorBrandIcon(brand: connector.brand, size: 50, cornerRadius: OmiChrome.smallControlRadius)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text(connector.title)
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)
              .lineLimit(1)

            Text(connector.subtitle)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
              .lineLimit(1)
          }

          Spacer()
        }

        Text(connector.description)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        HStack {
          VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
            Text(snapshot.primaryText)
              .scaledFont(size: OmiType.caption, weight: .medium)
              .foregroundColor(snapshot.isConnected ? OmiColors.textSecondary : OmiColors.textTertiary)

            if let secondaryText = snapshot.secondaryText {
              Text(secondaryText)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
                .lineLimit(1)
            }
          }

          Spacer()

          ImportConnectorActionButton(title: snapshot.actionTitle, isConnected: snapshot.isConnected)
        }
      }
      .padding(OmiSpacing.md)
      .background(isHovering ? OmiColors.backgroundSecondary : OmiColors.backgroundPrimary)
      .cornerRadius(OmiChrome.smallControlRadius)
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
          .stroke(OmiColors.backgroundTertiary, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}

struct ImportConnectorActionButton: View {
  let title: String
  let isConnected: Bool

  var body: some View {
    Text(title)
      .scaledFont(size: OmiType.caption, weight: .medium)
      .foregroundColor(isConnected ? OmiColors.textPrimary : .black)
      .frame(width: isConnected ? 84 : 72, height: 28)
      .background(isConnected ? OmiColors.backgroundSecondary : Color.white)
      .cornerRadius(OmiChrome.chipRadius)
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius)
          .stroke(OmiColors.border, lineWidth: 1)
      )
  }
}

struct ConnectionModalActionButton: View {
  let title: String
  var isConnected = false

  var body: some View {
    Text(title)
      .scaledFont(size: OmiType.caption, weight: .medium)
      .foregroundColor(isConnected ? OmiColors.textPrimary : .black)
      .lineLimit(1)
      .padding(.horizontal, OmiSpacing.md)
      .frame(minWidth: isConnected ? 84 : 72)
      .frame(height: 28)
      .background(isConnected ? OmiColors.backgroundSecondary : Color.white)
      .cornerRadius(OmiChrome.chipRadius)
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.chipRadius)
          .stroke(OmiColors.border, lineWidth: 1)
      )
  }
}

struct ImportConnectorSheet: View {
  let connector: ImportConnector
  let appState: AppState?
  @ObservedObject var statusStore: ImportConnectorStatusStore
  let onDismiss: () -> Void

  @ObservedObject private var runner = ConnectorImportRunner.shared
  @State private var draftText = ""
  /// The trimmed draft a run consumed, kept to make success-clearing exact:
  /// only ever wipe the text the run actually imported, never a newer paste.
  @State private var submittedDraft: String?
  @FocusState private var draftFocused: Bool

  private var snapshot: ImportConnectorStatusStore.Snapshot {
    statusStore.snapshot(for: connector)
  }

  private var runState: ConnectorImportRunner.RunState? {
    runner.runs[connector.id]
  }

  private var isRunning: Bool {
    runState?.phase == .running
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      HStack(alignment: .top, spacing: OmiSpacing.md) {
        ConnectorBrandIcon(brand: connector.brand, size: 56, cornerRadius: OmiChrome.controlRadius)

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(connector.title)
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)

          Text(connector.subtitle)
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)

          Text(connector.description)
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textSecondary)
            .padding(.top, OmiSpacing.xxs)
        }

        Spacer()

        DismissButton(action: onDismiss)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          if connector.id == "chatgpt" || connector.id == "claude" {
            memoryImportContent
          } else {
            connectorActionContent
          }

          statusSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(OmiSpacing.xxl)
    .background(OmiColors.backgroundPrimary)
    .onChange(of: runState?.phase) { _, newPhase in
      // A successful import consumed the pasted draft, so clear it —
      // but only if it is still the submitted text. A reopened sheet
      // (submittedDraft == nil) or a draft edited mid-run must never
      // be wiped by an older run finishing. A failed run keeps the
      // draft so the user can retry without re-pasting.
      if newPhase == .succeeded {
        if draftText.trimmingCharacters(in: .whitespacesAndNewlines) == submittedDraft {
          draftText = ""
        }
        submittedDraft = nil
      }
    }
    .onDisappear {
      // A seen success is done with: clear it so the next open shows
      // the persisted snapshot status instead of stale success text.
      // Failures stay until the next start so they can't be missed.
      runner.acknowledgeSuccess(connectorID: connector.id)
    }
  }

  private var connectorActionContent: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      if let metricText = connector.metricText {
        Text(metricText)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
      }

      Button {
        startConnectorImport()
      } label: {
        ConnectionModalActionButton(
          title: primaryActionTitle,
          isConnected: snapshot.isConnected
        )
      }
      .buttonStyle(.plain)
      .disabled(isRunning)

      if connector.id == "local-files" {
        Text("Local files are indexed on-device and used to build your memory graph.")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
      }
    }
  }

  private var memoryImportContent: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      Text("Open \(connector.title), paste the copied prompt, then drop the full response here.")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textSecondary)

      Button {
        openAndCopyPrompt(for: memorySource)
      } label: {
        ConnectionModalActionButton(title: "Open \(connector.title) and Copy Prompt")
      }
      .buttonStyle(.plain)

      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(OmiColors.backgroundSecondary)
          .overlay(
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
              .stroke(
                Color.white.opacity(draftFocused ? 0.18 : 0.08),
                lineWidth: 1
              )
          )

        if draftText.isEmpty {
          Text("Paste the full \(connector.title) response here…")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
            .padding(.horizontal, draftFieldHorizontalInset)
            .padding(.vertical, draftFieldVerticalInset)
            .allowsHitTesting(false)
        }

        TextEditor(text: $draftText)
          .scrollContentBackground(.hidden)
          .font(.system(size: 13))
          .foregroundColor(OmiColors.textPrimary)
          // NSTextView adds a built-in 5pt line-fragment inset, so
          // subtract it here to align the caret with the placeholder.
          .padding(.horizontal, draftFieldHorizontalInset - 5)
          .padding(.vertical, draftFieldVerticalInset)
          // The running import consumed the text captured at start,
          // so edits mid-run would be ignored — and a success landing
          // from a run started in an earlier sheet instance clears
          // the draft, which must not eat text pasted mid-run.
          // `.disabled` alone doesn't evict an already-focused
          // NSTextView, so `startMemoryLogImport` also drops focus.
          .focused($draftFocused)
          .disabled(isRunning)
      }
      // Collapsed until the user engages, per the macOS convention for
      // paste-blob inputs in compact modals: grow on focus or content.
      .frame(height: draftFieldExpanded ? 200 : 64)
      .omiAnimation(.easeInOut(duration: 0.18), value: draftFieldExpanded)

      Button {
        startMemoryLogImport()
      } label: {
        ConnectionModalActionButton(
          title: isRunning ? "Importing…" : "Import \(connector.title)"
        )
      }
      .buttonStyle(.plain)
      .disabled(isRunning || isDraftEmpty)
    }
  }

  private var memorySource: OnboardingMemoryLogSource {
    connector.id == "chatgpt" ? .chatgpt : .claude
  }

  private var primaryActionTitle: String {
    switch connector.id {
    case "calendar":
      return isRunning ? "Importing…" : (snapshot.isConnected ? "Sync now" : "Connect Calendar")
    case "email":
      return isRunning ? "Importing…" : (snapshot.isConnected ? "Sync now" : "Connect Gmail")
    case "apple-notes":
      return isRunning ? "Importing…" : (snapshot.isConnected ? "Sync now" : "Connect Apple Notes")
    case "x":
      return isRunning ? "Connecting…" : (snapshot.isConnected ? "Sync now" : "Connect X")
    case "local-files":
      return isRunning ? "Reindexing…" : (snapshot.isConnected ? "Reindex Local Files" : "Index Local Files")
    default:
      return isRunning ? "Working…" : connector.actionTitle
    }
  }

  private func startConnectorImport() {
    switch connector.id {
    case "calendar":
      startRun(
        title: "Connecting to Calendar",
        detail: "Reading past events and upcoming commitments for memory extraction."
      ) { progress in
        await ConnectorImportOperations.importCalendar(progress: progress)
      }
    case "email":
      startRun(
        title: "Connecting to Gmail",
        detail: "Reading recent email history and follow-ups from the last year."
      ) { progress in
        await ConnectorImportOperations.importGmail(progress: progress)
      }
    case "x":
      startRun(
        title: "Connecting to X",
        detail: "Opening x.com to authorize access to your posts and bookmarks.",
        availabilityText: "Posts & bookmarks"
      ) { progress in
        await ConnectorImportOperations.connectX(progress: progress)
      }
    case "apple-notes":
      startRun(
        title: "Connecting to Apple Notes",
        detail: "Checking access and preparing to import recent notes.",
        availabilityText: "Private notes accessible"
      ) { progress in
        await ConnectorImportOperations.importAppleNotes(progress: progress)
      }
    case "local-files":
      startRun(
        title: "Indexing local files",
        detail: "Scanning your on-device files so Omi can use them in memory search.",
        availabilityText: "On-device index"
      ) { _ in
        await ConnectorImportOperations.rescanLocalFiles()
      }
    default:
      break
    }
  }

  private var isDraftEmpty: Bool {
    draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // Collapsed while empty (even when focused, since macOS auto-focuses the
  // editor on open); grows once there is text to paste/type into.
  private var draftFieldExpanded: Bool {
    !draftText.isEmpty
  }

  private let draftFieldHorizontalInset: CGFloat = 14
  private let draftFieldVerticalInset: CGFloat = 12

  private func startMemoryLogImport() {
    // The Import button is disabled while the draft is empty; this guard
    // is the function's precondition, not a reachable UI path.
    let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let source = memorySource
    draftFocused = false
    submittedDraft = trimmed
    startRun(
      title: "Importing \(source.displayName)",
      detail: "Extracting durable memories from the pasted conversation.",
      availabilityText: "Imported manually"
    ) { _ in
      await ConnectorImportOperations.importMemoryLog(text: trimmed, source: source)
    }
  }

  /// Hands the run to the shared runner so it survives this sheet closing.
  /// Marking the connector synced happens inside the runner-owned task,
  /// not in a button closure tied to this sheet's lifetime.
  private func startRun(
    title: String,
    detail: String,
    availabilityText: String? = nil,
    operation: @escaping @MainActor (ConnectorImportRunner.ProgressSink) async -> ConnectorImportOperations.Outcome
  ) {
    let connectorID = connector.id
    let statusStore = statusStore
    // Capture first-sync state before markSynced flips the persisted latch, so
    // the terminal telemetry can separate first-ever connects from re-syncs.
    let wasFirstSync = !statusStore.snapshot(for: connector).isConnected
    ConnectorImportRunner.shared.start(
      connectorID: connectorID,
      progressTitle: title,
      progressDetail: detail
    ) { progress in
      switch await operation(progress) {
      case .success(let result, let message):
        statusStore.markSynced(
          connectorID: connectorID,
          sourceCount: result.sourceCount,
          memoryCount: result.memoryCount,
          lastDeltaCount: result.newItems,
          availabilityText: availabilityText
        )
        return .success(
          message: message,
          metrics: ConnectorImportRunner.RunMetrics(
            sourceCount: result.sourceCount,
            memoryCount: result.memoryCount,
            wasFirstSync: wasFirstSync
          )
        )
      case .failure(let message, let failureClass):
        return .failure(
          message: message,
          metrics: ConnectorImportRunner.RunMetrics(
            failureClass: failureClass,
            wasFirstSync: wasFirstSync
          )
        )
      }
    }
  }

  private func openAndCopyPrompt(for source: OnboardingMemoryLogSource) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(source.prompt, forType: .string)
    NSWorkspace.shared.open(source.prefilledBrowserURL)
  }

  @ViewBuilder
  private var statusSection: some View {
    if let run = runState, run.phase == .running {
      statusCard {
        HStack(alignment: .top, spacing: OmiSpacing.md) {
          ProgressView()
            .controlSize(.small)
            .padding(.top, OmiSpacing.hairline)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text(run.progressTitle)
              .scaledFont(size: OmiType.caption, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Text(run.progressDetail)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textSecondary)
              .fixedSize(horizontal: false, vertical: true)

            Text("You can close this window now. Omi keeps importing in the background.")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textTertiary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    } else if let statusMessage = runState?.statusMessage {
      Text(statusMessage)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.success)
    } else if let errorMessage = runState?.errorMessage {
      Text(UserFacingErrorPresentation.message(from: errorMessage, while: .integration(connector.title)))
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.warning)
    } else if snapshot.isConnected || snapshot.secondaryText != nil {
      statusCard {
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          Text("Current import status")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(OmiColors.textTertiary)

          Text(snapshot.primaryText)
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          if let secondaryText = snapshot.secondaryText {
            Text(secondaryText)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(OmiColors.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    } else {
      Text(
        "Start the import here. Once it starts, you can close this window and Omi keeps importing in the background."
      )
      .scaledFont(size: OmiType.caption)
      .foregroundColor(OmiColors.textTertiary)
    }
  }

  private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(OmiSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(OmiColors.backgroundSecondary)
      .cornerRadius(OmiChrome.controlRadius)
  }
}
