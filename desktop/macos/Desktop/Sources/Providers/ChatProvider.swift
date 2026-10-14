import Combine
import CoreGraphics
import CryptoKit
@preconcurrency import GRDB
import OmiSupport
import SwiftUI
import UniformTypeIdentifiers

/// Boxes a value so it can cross a `@Sendable` boundary without itself
/// conforming to `Sendable`. Safe here because the captured JSON payloads are
/// read straight through and never mutated after boxing.
private struct ChatProviderSendableBox<Value>: @unchecked Sendable {
  let value: Value
}

/// Mutable timing/usage accumulator shared between a turn's @Sendable tool
/// callbacks and the @MainActor turn body. All access is funneled through the
/// MainActor (callbacks run via ChatTurnCallbackQueue), matching the existing
/// responseMetrics/pendingToolTraceInputs accumulators, so unchecked Sendable
/// conformance is safe.
private final class ChatToolTimingState: @unchecked Sendable {
  var toolNames: [String] = []
  var toolStartTimes: [String: Date] = [:]
}

struct LocalChatSelectionStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func selectedChatID(ownerID: String) -> String {
    defaults.string(forKey: key(ownerID: ownerID)) ?? "default"
  }

  func setSelectedChatID(_ chatID: String, ownerID: String) {
    defaults.set(chatID, forKey: key(ownerID: ownerID))
  }

  private func key(ownerID: String) -> String {
    let ownerHash = SHA256.hash(data: Data(ownerID.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "intentive.chat.selected.v1.\(ownerHash)"
  }
}

/// Local owner-isolation probes explicitly skip model credentials: the synthetic
/// owner has no Firebase session. Only ownership, a canonical surface mapping,
/// and a fixed journal exchange run here; managed queries keep normal admission.
@MainActor

private struct ChatJournalTerminalTarget {
  let surface: AgentSurfaceReference
  let assistantMessageId: String
  let ownerID: String
  let onFinalized: (@MainActor (Bool) -> Void)?
}

// MARK: - UserDefaults Extension for KVO

extension UserDefaults {
  @objc dynamic var multiChatEnabled: Bool {
    return bool(forKey: "multiChatEnabled")
  }
}

// MARK: - Chat Session Model

/// A chat session that groups related messages
struct ChatSession: Identifiable, Codable, Equatable {
  let id: String
  var title: String
  var preview: String?
  let createdAt: Date
  var updatedAt: Date
  var messageCount: Int
  var starred: Bool

  enum CodingKeys: String, CodingKey {
    case id, title, preview, starred
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case messageCount = "message_count"
  }

  init(
    id: String = UUID().uuidString, title: String = "New Chat", preview: String? = nil,
    createdAt: Date = Date(), updatedAt: Date = Date(),
    messageCount: Int = 0, starred: Bool = false
  ) {
    self.id = id
    self.title = title
    self.preview = preview
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.messageCount = messageCount
    self.starred = starred
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New Chat"
    preview = try container.decodeIfPresent(String.self, forKey: .preview)
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
    starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
  }
}

// MARK: - Content Block Model

/// Structured tool input for inline display
struct ToolCallInput {
  /// Short summary for inline display (e.g., file path, command)
  let summary: String
  /// Full JSON details for expanded view
  let details: String?
}

/// A block of content within an AI message (text or tool call indicator)
/// Stable identity for opening a background agent from the chat timeline.
/// Prefer `sessionId` / `runId` for kernel hydrate; `pillId` is the UI cache key.
struct AgentTimelineRef: Equatable {
  var pillId: UUID?
  var sessionId: String?
  var runId: String?

  var hasIdentity: Bool {
    pillId != nil
      || !(sessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      || !(runId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  /// Kernel lookup prefers run, then session, then pill externalRefId.
  var hydratePreference: AgentTimelineHydratePreference {
    AgentTimelineHydratePreference.make(pillId: pillId, sessionId: sessionId, runId: runId)
  }
}

/// Pure ordering for open-by-id hydrate (unit-testable without kernel I/O).
struct AgentTimelineHydratePreference: Equatable {
  enum Key: Equatable {
    case runId(String)
    case sessionId(String)
    case pillId(UUID)
  }

  let keys: [Key]

  static func make(pillId: UUID?, sessionId: String?, runId: String?) -> AgentTimelineHydratePreference {
    var keys: [Key] = []
    if let runId = sessionIdOrNil(runId) {
      keys.append(.runId(runId))
    }
    if let sessionId = sessionIdOrNil(sessionId) {
      keys.append(.sessionId(sessionId))
    }
    if let pillId {
      keys.append(.pillId(pillId))
    }
    return AgentTimelineHydratePreference(keys: keys)
  }

  /// First preference key that matches the provided lookups (run → session → pill).
  func firstMatchingKey(
    runIdMatches: (String) -> Bool,
    sessionIdMatches: (String) -> Bool,
    pillIdMatches: (UUID) -> Bool
  ) -> Key? {
    for key in keys {
      switch key {
      case .runId(let runId) where runIdMatches(runId):
        return key
      case .sessionId(let sessionId) where sessionIdMatches(sessionId):
        return key
      case .pillId(let pillId) where pillIdMatches(pillId):
        return key
      default:
        continue
      }
    }
    return nil
  }

  private static func sessionIdOrNil(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

/// Applies timeline open result to card unavailable UI (unit-testable).
enum AgentTimelineOpenFeedback {
  /// Returns whether the card should show the unavailable message after an open attempt.
  static func shouldShowUnavailable(succeeded: Bool) -> Bool {
    !succeeded
  }

  /// Link-out opens a resolvable agent; hide it when open failed / unavailable / no callback / no id.
  static func shouldShowLinkOut(
    hasResolvableAgent: Bool,
    hasOpenAction: Bool,
    showUnavailable: Bool
  ) -> Bool {
    hasResolvableAgent && hasOpenAction && !showUnavailable
  }
}

enum ChatContentBlock: Identifiable {
  case text(id: String, text: String)
  case toolCall(
    id: String, name: String, status: ToolCallStatus,
    toolUseId: String? = nil,
    input: ToolCallInput? = nil,
    output: String? = nil)
  case thinking(id: String, text: String)
  /// Collapsible card showing a summary with expandable full text (used for AI profile/discovery)
  case discoveryCard(id: String, title: String, summary: String, fullText: String)
  case agentSpawn(
    id: String,
    pillId: UUID?,
    sessionId: String,
    runId: String,
    title: String,
    objective: String
  )
  case agentCompletion(
    id: String,
    pillId: UUID?,
    sessionId: String?,
    runId: String?,
    title: String,
    promptSnippet: String,
    output: String,
    status: String
  )

  var id: String {
    switch self {
    case .text(let id, _): return id
    case .toolCall(let id, _, _, _, _, _): return id
    case .thinking(let id, _): return id
    case .discoveryCard(let id, _, _, _): return id
    case .agentSpawn(let id, _, _, _, _, _): return id
    case .agentCompletion(let id, _, _, _, _, _, _, _): return id
    }
  }

  var agentTimelineRef: AgentTimelineRef? {
    switch self {
    case .agentSpawn(_, let pillId, let sessionId, let runId, _, _):
      return AgentTimelineRef(pillId: pillId, sessionId: sessionId, runId: runId)
    case .agentCompletion(_, let pillId, let sessionId, let runId, _, _, _, _):
      return AgentTimelineRef(pillId: pillId, sessionId: sessionId, runId: runId)
    default:
      return nil
    }
  }

  /// Human-friendly display name for a tool
  static func displayName(for toolName: String) -> String {
    // Strip MCP prefixes (e.g., "mcp__intentive-tools__execute_sql" → "execute_sql")
    let cleanName: String
    if toolName.hasPrefix("mcp__") {
      cleanName = String(toolName.split(separator: "__").last ?? Substring(toolName))
    } else {
      cleanName = toolName
    }

    // Handle tool names with embedded details (e.g. "WebSearch: \"query\"")
    if cleanName.hasPrefix("WebSearch:") {
      let query = String(cleanName.dropFirst("WebSearch: ".count))
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      return query.isEmpty ? "Searching the web" : "Searching: \(query)"
    }
    if cleanName.hasPrefix("WebFetch:") {
      return "Fetching page"
    }
    if cleanName.lowercased().hasPrefix("read:") {
      return "Reading file"
    }
    if cleanName.lowercased().hasPrefix("write:") {
      return "Writing file"
    }
    if cleanName.lowercased().hasPrefix("edit:") {
      return "Editing file"
    }
    if cleanName.lowercased().hasPrefix("bash:") {
      return "Running command"
    }

    switch cleanName {
    case "execute_sql": return "Querying database"
    case "semantic_search": return "Searching conversations"
    case "spawn_agent": return "Starting agent"
    case "run_agent_and_wait": return "Running agent"
    case "Read": return "Reading file"
    case "Write": return "Writing file"
    case "Edit": return "Editing file"
    case "Bash": return "Running command"
    case "Grep": return "Searching code"
    case "Glob": return "Finding files"
    case "WebSearch": return "Searching the web"
    case "WebFetch": return "Fetching page"
    default: return "Using \(cleanName)"
    }
  }

  /// Tools whose runs are legitimately long — shell commands, file
  /// generation/edits, web fetches, database queries, and delegated
  /// agents. The stall banner ("This is taking longer than usual") is
  /// suppressed for these so normal long work doesn't read as stuck.
  static func isSlowExpectedTool(_ toolName: String) -> Bool {
    let cleaned: String
    if toolName.hasPrefix("mcp__") {
      cleaned = String(toolName.split(separator: "__").last ?? Substring(toolName))
    } else {
      cleaned = toolName
    }
    // Any MCP tool is an out-of-process call we don't time-bound.
    if toolName.hasPrefix("mcp__") { return true }
    let lower = cleaned.lowercased()
    let slowPrefixes = ["bash", "write", "edit", "multiedit", "webfetch", "websearch", "task", "notebookedit"]
    if slowPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
    let slowExact: Set<String> = [
      "execute_sql", "semantic_search", "spawn_agent",
      "run_attempt", "run_agent_and_wait", "send_agent_message",
    ]
    // Strip any embedded summary suffix ("Bash: cmd" style) before matching.
    let head = lower.split(separator: ":").first.map(String.init) ?? lower
    return slowExact.contains(head.trimmingCharacters(in: .whitespaces))
  }

  /// Extracts a short summary from tool input for inline display
  static func toolInputSummary(for toolName: String, input: [String: Any]) -> ToolCallInput? {
    let cleanName: String
    if toolName.hasPrefix("mcp__") {
      cleanName = String(toolName.split(separator: "__").last ?? Substring(toolName))
    } else {
      cleanName = toolName
    }

    let summary: String?
    switch cleanName {
    case "Read":
      summary = input["file_path"] as? String
    case "Write", "Edit":
      summary = input["file_path"] as? String
    case "Bash":
      if let cmd = input["command"] as? String {
        summary = cmd.count > 80 ? String(cmd.prefix(80)) + "…" : cmd
      } else {
        summary = nil
      }
    case "Grep":
      let pattern = input["pattern"] as? String ?? ""
      let path = input["path"] as? String
      summary = path != nil ? "\(pattern) in \(path!)" : pattern
    case "Glob":
      summary = input["pattern"] as? String
    case "WebSearch":
      summary = input["query"] as? String
    case "WebFetch":
      summary = input["url"] as? String
    case "execute_sql":
      if let query = input["query"] as? String {
        summary = query.count > 100 ? String(query.prefix(100)) + "…" : query
      } else {
        summary = nil
      }
    case "semantic_search":
      summary = input["query"] as? String
    case "spawn_agent":
      summary = (input["objective"] ?? input["brief"] ?? input["query"]) as? String
    case "run_agent_and_wait":
      summary = input["objective"] as? String
    case "request_permission":
      summary = input["type"] as? String
    default:
      // Try common key names
      summary = (input["file_path"] ?? input["path"] ?? input["query"] ?? input["command"]) as? String
    }

    guard let summary = summary, !summary.isEmpty else { return nil }

    // Build full details JSON
    let details: String?
    if let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
      let str = String(data: data, encoding: .utf8)
    {
      details = str
    } else {
      details = nil
    }

    return ToolCallInput(summary: summary, details: details)
  }
}

enum ToolCallStatus: CaseIterable {
  case running
  /// Promoted by `StallDetector` after the per-tool / inter-event
  /// timer crosses `StallThresholds.slowGapMs`. Still in flight.
  case slow
  /// Promoted after `StallThresholds.stalledGapMs`. Still in flight,
  /// but eligible for the message-level Cancel banner.
  case stalled
  case completed
  /// Terminal failure (timeout, interrupt, bridge error).
  case failed

  /// True for any state where the tool is still working. Pattern
  /// matches throughout the UI should use this instead of `== .running`
  /// so `.slow` and `.stalled` don't accidentally look complete.
  var isInFlight: Bool {
    switch self {
    case .running, .slow, .stalled:
      return true
    case .completed, .failed:
      return false
    }
  }

  static func fromBridgeStatus(_ status: String) -> ToolCallStatus {
    switch status {
    case "started", "progress":
      return .running
    case "failed", "cancelled", "interrupted":
      return .failed
    default:
      return .completed
    }
  }
}

final class ChatResponseMetrics: @unchecked Sendable {
  struct Snapshot {
    let sqlRowsReturned: Int
    let sqlQueryCount: Int
    let screenContext: ScreenContextChatCycleSnapshot
  }

  private let lock = NSLock()
  private var isFirstResponse = true
  private var isGenerating = false
  private var sqlRowsReturned = 0
  private var sqlQueryCount = 0
  private let screenContextMetrics = ScreenContextChatCycleMetrics()

  func markFirstOutputIfNeeded() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard isFirstResponse else { return false }
    isFirstResponse = false
    return true
  }

  func markGenerationStartedIfNeeded() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !isGenerating else { return false }
    isGenerating = true
    return true
  }

  func recordToolResult(name: String, result: String) {
    screenContextMetrics.recordToolResult(name: name, output: result)
    guard name == "execute_sql" else { return }
    let rowsReturned = Self.sqlRowsReturned(in: result)
    lock.lock()
    sqlQueryCount += 1
    sqlRowsReturned += rowsReturned
    lock.unlock()
  }

  func recordToolRequested(name: String) {
    screenContextMetrics.recordToolRequested(name)
  }

  func snapshot() -> Snapshot {
    lock.lock()
    defer { lock.unlock() }
    return Snapshot(
      sqlRowsReturned: sqlRowsReturned,
      sqlQueryCount: sqlQueryCount,
      screenContext: screenContextMetrics.snapshot()
    )
  }

  private static func sqlRowsReturned(in result: String) -> Int {
    guard let match = result.range(of: #"(\d+) row\(s\)"#, options: .regularExpression) else {
      return 0
    }
    let numStr = result[match].components(separatedBy: " ").first ?? "0"
    return Int(numStr) ?? 0
  }
}

final class ChatToolTraceInputStore: @unchecked Sendable {
  struct Entry {
    let inputJson: String
    let started: ContinuousClock.Instant
  }

  private let lock = NSLock()
  private var entries: [String: Entry] = [:]

  func record(id: String, inputJson: String, started: ContinuousClock.Instant = .now) {
    lock.lock()
    entries[id] = Entry(inputJson: inputJson, started: started)
    lock.unlock()
  }

  func take(id: String) -> Entry? {
    lock.lock()
    defer { lock.unlock() }
    return entries.removeValue(forKey: id)
  }
}

// MARK: - Chat Message Model

/// Metadata about the context and resources used to generate an AI response
struct MessageMetadata {
  var model: String?
  var inputTokens: Int?
  var outputTokens: Int?
  var cacheReadTokens: Int?
  var cacheWriteTokens: Int?
  var costUsd: Double?
  var systemPrompt: String?
  var hasScreenshot: Bool
  var screenshotSizeBytes: Int?
  var toolNames: [String]
  /// Total rows returned across all execute_sql tool calls during this response
  var sqlRowsReturned: Int
  /// Number of execute_sql tool calls made during this response
  var sqlQueryCount: Int

  var totalTokens: Int? {
    guard let input = inputTokens, let output = outputTokens else { return nil }
    return input + output + (cacheReadTokens ?? 0) + (cacheWriteTokens ?? 0)
  }

  // MARK: - Dynamic context sections from system prompt

  /// A single tagged section found in the system prompt
  struct PromptSection {
    let tag: String
    let itemCount: Int
    let charCount: Int

    /// Human-readable label derived from the XML tag name
    var label: String {
      tag.replacingOccurrences(of: "_", with: " ")
        .localizedCapitalized
    }
  }

  /// Dynamically discovers all XML-tagged sections in the system prompt and counts items in each.
  /// This is future-proof: any new `<some_tag>...</some_tag>` section automatically appears.
  var promptSections: [PromptSection] {
    guard let prompt = systemPrompt else { return [] }
    var sections: [PromptSection] = []
    var seen = Set<String>()

    // Find all <tag>...</tag> pairs
    guard let pattern = try? NSRegularExpression(pattern: #"<([a-z][a-z0-9_]*)>"#, options: []) else { return [] }
    let matches = pattern.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))

    for match in matches {
      guard let tagRange = Range(match.range(at: 1), in: prompt) else { continue }
      let tag = String(prompt[tagRange])

      // Skip duplicates
      guard !seen.contains(tag) else { continue }
      seen.insert(tag)

      let openTag = "<\(tag)>"
      let closeTag = "</\(tag)>"
      guard let openRange = prompt.range(of: openTag),
        let closeRange = prompt.range(of: closeTag),
        openRange.upperBound < closeRange.lowerBound
      else { continue }

      let content = String(prompt[openRange.upperBound..<closeRange.lowerBound])
      let charCount = content.count

      // Count meaningful lines (items starting with "- ", or role-prefixed lines for conversation)
      let lines = content.components(separatedBy: "\n")
      let itemCount: Int
      if tag == "conversation_history" {
        itemCount = lines.filter { $0.hasPrefix("User:") || $0.hasPrefix("Assistant:") }.count
      } else {
        let bulletLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }.count
        // If no bullet items, count non-empty non-header lines
        if bulletLines > 0 {
          itemCount = bulletLines
        } else {
          itemCount = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
      }

      sections.append(PromptSection(tag: tag, itemCount: itemCount, charCount: charCount))
    }

    return sections
  }

  // Backward-compatible summary counts used by the floating-bar metadata popover.
  // These intentionally keep the older semantics instead of exposing every raw XML section.
  var memoriesCount: Int {
    guard let prompt = systemPrompt,
      let factsStart = prompt.range(of: "<user_facts>"),
      let factsEnd = prompt.range(of: "</user_facts>")
    else { return 0 }
    let factsSection = String(prompt[factsStart.upperBound..<factsEnd.lowerBound])
    return
      factsSection
      .components(separatedBy: "\n")
      .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
      .count
  }

  var conversationTurns: Int {
    guard let prompt = systemPrompt,
      let histStart = prompt.range(of: "<conversation_history>"),
      let histEnd = prompt.range(of: "</conversation_history>")
    else { return 0 }
    let histSection = String(prompt[histStart.upperBound..<histEnd.lowerBound])
    return
      histSection
      .components(separatedBy: "\n")
      .filter { $0.hasPrefix("User:") || $0.hasPrefix("Assistant:") }
      .count
  }

  var tasksCount: Int {
    guard let prompt = systemPrompt,
      let tasksStart = prompt.range(of: "<user_tasks>"),
      let tasksEnd = prompt.range(of: "</user_tasks>")
    else { return 0 }
    let tasksSection = String(prompt[tasksStart.upperBound..<tasksEnd.lowerBound])
    return
      tasksSection
      .components(separatedBy: "\n")
      .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
      .count
  }

  var goalsCount: Int {
    guard let prompt = systemPrompt,
      let goalsStart = prompt.range(of: "<user_goals>"),
      let goalsEnd = prompt.range(of: "</user_goals>")
    else { return 0 }
    let goalsSection = String(prompt[goalsStart.upperBound..<goalsEnd.lowerBound])
    return
      goalsSection
      .components(separatedBy: "\n")
      .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
      .count
  }

  var availableToolsCount: Int {
    guard let prompt = systemPrompt else { return 0 }
    return [
      "execute_sql",
      "semantic_search",
      "spawn_agent",
      "run_agent_and_wait",
      "get_daily_recap",
      "complete_task",
      "delete_task",
    ]
    .filter { prompt.contains("**\($0)**") }
    .count
  }
}

/// A single chat message
enum ChatSender: Equatable {
  case user
  case ai
}

enum ChatTurnOwner: Equatable {
  case mainChat
  case floatingDefault
  case floatingVoice
  case agentPill(UUID)

  /// Per-turn reasoning-effort lane relayed to the desktop gateway.
  /// Typed chat runs "adaptive": the model decides how much to think per
  /// question (including explicit "think properly / take 5 minutes" asks).
  /// PTT/voice runs "fast": thinking off, low effort, latency-optimized.
  /// Background agent pills keep the legacy behavior.
  var reasoningEffort: String? {
    switch self {
    case .floatingVoice: return "fast"
    case .mainChat, .floatingDefault: return "adaptive"
    case .agentPill: return nil
    }
  }

  func canInterrupt(_ activeOwner: ChatTurnOwner) -> Bool {
    switch (self, activeOwner) {
    case (.floatingDefault, .floatingDefault),
      (.floatingDefault, .floatingVoice),
      (.floatingVoice, .floatingDefault),
      (.floatingVoice, .floatingVoice):
      return true
    case (.agentPill(let lhs), .agentPill(let rhs)):
      return lhs == rhs
    default:
      return self == activeOwner
    }
  }
}

// MARK: - Citation Model

/// A citation referencing a source conversation or memory
struct Citation: Identifiable {
  let id: String
  let sourceType: CitationSourceType
  let title: String
  let preview: String
  let emoji: String?
  let createdAt: Date?

  enum CitationSourceType {
    case conversation
    case memory
  }
}

// MARK: - Chat Mode

/// Controls whether the AI agent can perform write actions (Act) or is restricted to read-only (Ask)
enum ChatMode: String, CaseIterable {
  case ask
  case act
}

enum ChatSystemPromptStyle {
  case main
  case floating
}

/// Complete local-agent request assembled by the one-assistant chat path.
/// Keeping attachment identity inside this value prevents the UI state and
/// agent transport calls from drifting into separate request shapes.
@MainActor
class ChatProvider: ObservableObject {

  nonisolated static func shouldInterruptTimedOutAgentQuery(queryStarted: Bool) -> Bool {
    queryStarted
  }

  nonisolated static func hasCompletedRealExchange(_ messages: [ChatMessage]) -> Bool {
    firstCompletedRealExchange(messages) != nil
  }

  nonisolated static func firstCompletedRealExchange(
    _ messages: [ChatMessage]
  ) -> (userText: String, assistantText: String)? {
    var sawCompletedUser = false
    var userText = ""
    for message in messages {
      if message.sender == .user, message.journalStatus == .completed,
        !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        sawCompletedUser = true
        userText = message.text
      } else if sawCompletedUser, message.sender == .ai,
        message.journalStatus == .completed,
        !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return (userText, message.text)
      }
    }
    return nil
  }

  /// Weak reference to the app-root main-window instance (set by
  /// ViewModelContainer.init()), so the local automation bridge can drive
  /// the real main chat surface in-process — no synthetic mouse/keyboard
  /// input, so it never touches the user's actual cursor.
  static weak var mainInstance: ChatProvider?

  // MARK: - Published State
  @Published var chatMode: ChatMode = .act
  @Published var draftText = "" {
    didSet {
      guard !isRestoringDraft else { return }
      draftRevisions[activeDraftKey, default: 0] &+= 1
      ChatDraftStore.shared.setText(draftText, for: activeDraftKey)
    }
  }
  /// Files staged for attachment to the next message. Each chat keeps an
  /// independent in-memory staging list, just like its persisted draft text.
  @Published var pendingAttachments: [ChatAttachment] = [] {
    didSet {
      guard !isRestoringPendingAttachments else { return }
      pendingAttachmentsByDraftKey[activeDraftKey] = pendingAttachments
      ChatDraftStore.shared.setAttachments(pendingAttachments, for: activeDraftKey)
    }
  }
  @Published var messages: [ChatMessage] = []
  @Published var sessions: [ChatSession] = []
  @Published var currentSession: ChatSession? {
    didSet { restoreDraftForCurrentContextIfNeeded() }
  }
  @Published var isLoading = false
  @Published var isLoadingSessions = true  // Start true since we load sessions on init
  @Published private(set) var isCreatingSession = false
  @Published var isSending = false
  @Published var isStopping = false
  @Published private(set) var activeTurnOwner: ChatTurnOwner?
  @Published var isClearing = false
  @Published var errorMessage: String?
  /// Monotonic token that increments each time the local user sends a message.
  /// ChatMessagesView observes this to anchor the viewport on send, rather than
  /// inferring solely from messages.count changes (which can also come from
  /// polling/sync).
  @Published var localSendToken: LocalSendToken = LocalSendToken(generation: 0)

  /// The personalized post-onboarding opener shown in the empty Chat tab the
  /// moment onboarding finishes: a greeting addressed to the user by name plus
  /// tappable starter questions. Non-nil only during that first landing;
  /// cleared once the user sends their first message. See
  /// `presentOnboardingOpener()`.
  @Published var onboardingOpener: OnboardingOpenerContent?

  // MARK: - ChatErrorState (structured replacement for the inline error banner)
  //
  // Structured error state for the chat surface. Drives the
  // ChatErrorCard view. Coexists with the legacy `errorMessage`
  // banner: mappable BridgeError cases set `currentError` and clear
  // `errorMessage`; unmappable cases (encoding, quota, agent errors
  // with free-form messages) keep falling back to the legacy banner.
  //
  // The upgrade sheet is deliberately not migrated; it is a product flow,
  // not an error recovery surface.
  @Published var currentError: ChatErrorState?

  /// Preferred user-visible error string for compact surfaces (floating bar).
  var displayErrorMessage: String? {
    if let currentError {
      return currentError.userFacingSummary
    }
    return errorMessage
  }

  /// Captured at the start of each sendMessage so the .retry recovery
  /// action can re-issue the user's last prompt. Cleared after a
  /// successful re-send or on dismiss to avoid stale retries.
  private var lastFailedPrompt: String?
  private var pendingErrorRecoveryPrompt: String?

  /// Monotonically-incremented id for each sendMessage / stopAgent cycle.
  /// Watchdog tasks capture their gen and only reset state if it still
  /// matches — so a watchdog fired by a stuck send #N won't cancel a
  /// later, healthy send #N+1. See sendMessage() and stopAgent().
  private var sendGeneration: Int = 0
  /// Catalog list requests can overlap user mutations while they are suspended
  /// on the local runtime. Never let an older snapshot replace a receipt that
  /// has already been applied to the visible catalog.
  private var catalogMutationGeneration: UInt64 = 0
  private var catalogFetchGeneration: UInt64 = 0
  private var catalogOwnerGeneration: UInt64 = 0
  /// Last-intent-wins lease for chat selection. Journal reloads can suspend,
  /// so an older selection must not persist or roll back over a newer one.
  private var chatSelectionGeneration: UInt64 = 0

  private struct CatalogOwnerLease {
    let ownerID: String?
    let ownerGeneration: UInt64
    let authorization: RuntimeOwnerAuthorizationSnapshot?
  }
  private var sendLockOwnership = ChatSendLockOwnership()
  private var activeBridgeSendGeneration: Int?
  private var activeChatTelemetryAttempt: (generation: Int, attempt: ChatQueryTelemetryAttempt)?
  private var activeChatTurnLifecycle: (generation: Int, lifecycle: ChatTurnLifecycle)?
  private var activeChatClientTurnId: (generation: Int, id: String)?
  private var activeStopReason: (generation: Int, reason: ChatTurnStopReason)?

  /// Set to a send's generation when the 60s watchdog fires for it, *before*
  /// the watchdog interrupts the bridge. `interrupt()` resumes the in-flight
  /// request with `BridgeError.stopped`, which the send-loop catch would
  /// otherwise treat as a silent user stop — so the catch checks this marker to
  /// surface "Response took too long" instead of vanishing the turn. See the
  /// watchdog in sendMessage() and the `.stopped` catch branch.
  private var sendWatchdogFiredGeneration: Int?

  /// A per-tool guard fires before the whole-turn watchdog when an adapter
  /// leaves a tool request active without making forward progress.
  private var sendToolStallAbortGeneration: Int?

  private static let perToolStallAbortMs = 90_000
  private static let genericWatchdogInactivityMs = 60_000
  private static let genericWatchdogPollMs = 5_000

  /// Set during onboarding so the managed session is persisted for restart recovery.
  var isOnboarding = false
  var preOnboardingMainMessages: [ChatMessage]?
  @Published var sessionsLoadError: String?
  @Published var hasMoreMessages = false
  @Published var isLoadingMoreMessages = false
  @Published var showStarredOnly = false
  @Published var searchQuery = ""
  /// Pre-computed grouped sessions for sidebar display.
  /// Updated reactively via Combine instead of recomputed on every SwiftUI render pass.
  @Published private(set) var groupedSessions: [(String, [ChatSession])] = []

  /// Whether the user is currently viewing the default chat (syncs with Flutter app)
  @Published var isInDefaultChat = true

  private var activeDraftKey = ChatDraftKey.mainChat(contextID: "default")
  private var isRestoringDraft = false
  private var draftRevisions: [ChatDraftKey: UInt64] = [:]

  /// Multi-chat mode setting - when false, only default chat is shown (syncs with Flutter)
  /// When true, user can create multiple chat sessions
  @AppStorage("multiChatEnabled") var multiChatEnabled = false

  // MARK: - Agent client
  private var agentClient: AgentClient.Session?
  private var activeConversationRequest: Task<ConversationResponseCompletion, Error>?
  private var activeConversationText = ""
  private var activeDirectConversation: (turnID: String, userText: String, generation: Int)?
  private static let sharedConversationPromptBindings = ConversationPromptBindingStore<ConversationPromptScope>(
    bootstrap: bootstrapConversationPrompt)
  private static func bootstrapConversationPrompt(id: String, scope: ConversationPromptScope) async throws
    -> ConversationPromptReceipt
  {
    try await APIClient.shared.bootstrapConversation(conversationID: id, authorizationSnapshot: scope.authorization)
  }
  var conversationPromptBindings: ConversationPromptBindingStore<ConversationPromptScope> {
    Self.sharedConversationPromptBindings
  }

  #if DEBUG
    var listChatCatalogForTests: (() async throws -> [LocalChatSummary])?
    var createChatCatalogForTests: ((String, String?) async throws -> LocalChatSummary)?
    var updateChatCatalogForTests:
      ((String, String?, LocalChatTitleOrigin?, LocalChatTitleOrigin?, Bool?) async throws -> LocalChatSummary)?
    var deleteChatCatalogForTests: ((String) async throws -> Set<String>)?
    var clearChatJournalForTests: ((String) async -> Bool)?
    var reloadChatJournalForTests: ((AgentSurfaceReference) async -> Bool)?
    var beginRealtimeChatClearForTests: ((AgentSurfaceReference) -> Bool)?
    var endRealtimeChatClearForTests: ((AgentSurfaceReference) -> Void)?
    var garbageCollectChatAttachmentsForTests: ((String, Set<String>) async throws -> Void)?
    var runtimeOwnerIdForTests: (() -> String?)?
    var ensureBridgeStartedForTests: ((Int?) async -> Bool)?
    var refreshMemoriesForPromptForTests: (() async -> Void)?
    var loadAIProfileForTests: (() async -> String?)?
    var recordStreamingJournalExchangeForTests: ((ChatMessage, ChatMessage) async -> [ChatMessage]?)?
    var initialMessageForTests: ((String, [String], String) async throws -> InitialMessageResponse)?
    var recordInitialGreetingForTests: ((AgentSurfaceReference, ChatMessage, String) async -> Bool)?
    var generateTitleForTests: ((String, String, String) async throws -> GenerateTitleResponse)?
    var agentClientForTests: AgentClient.Session?

    func setActiveSendChatIDForTests(_ chatID: String?) {
      activeSendChatID = chatID
    }
  #endif

  private func resolvedAgentClient() -> AgentClient.Session {
    #if DEBUG
      if let agentClientForTests { return agentClientForTests }
    #endif
    if let agentClient { return agentClient }
    let session = AgentClient.makeSession()
    agentClient = session
    return session
  }

  lazy var kernelTurnProjection = KernelTurnProjection(host: self)
  private let journalWriteCoordinator = ChatJournalWriteCoordinator()
  private var journalOwnerByMessageID: [String: String] = [:]
  private var journalTerminalTargets = ChatTerminalTargetRegistry<ChatJournalTerminalTarget>()
  private var agentBridgeStarted = false
  private let bridgeReadinessSingleFlight =
    AgentRuntimeStartupSingleFlight<RuntimeOwnerAuthorizationSnapshot, Bool>()
  private let messagesPageSize = 50
  /// Visible journal offset used while refreshing older local turns.
  private var messagesPaginationOffset = 0

  /// Reset history-pagination state. Must accompany every clear/replace of
  /// `messages` outside the two loaders (`selectSession`,
  /// `loadDefaultChatMessages`), which set both fields from a fresh fetch.
  func resetMessagesPagination() {
    messagesPaginationOffset = 0
    hasMoreMessages = false
  }

  private var multiChatObserver: AnyCancellable?
  private var sessionGroupingObserver: AnyCancellable?
  private var activationObserver: AnyCancellable?
  private var runtimeOwnerObserver: AnyCancellable?
  private var signOutObserver: AnyCancellable?
  private var sessionInvalidateObserver: AnyCancellable?

  private var refreshAllObserver: AnyCancellable?

  // MARK: - Streaming Buffer
  /// Accumulates text and thinking deltas during streaming and flushes them to
  /// the published messages array in batches, reducing SwiftUI re-render frequency.
  private let streamingBuffer = ChatStreamingBuffer(flushInterval: 0.035)

  private struct PendingAttachmentScope {
    let ownerID: String
    let chatID: String
  }

  private var pendingAttachmentsByDraftKey: [ChatDraftKey: [ChatAttachment]] = [:]
  private var pendingAttachmentScopes: [String: PendingAttachmentScope] = [:]
  private var attachmentsAwaitingJournalAdmission: Set<String> = []
  private var isRestoringPendingAttachments = false
  private let chatSelectionStore = LocalChatSelectionStore()
  private var pendingCreateChatID: String?
  private var activeSendChatID: String?
  private var activeRealtimeChatClearSurface: AgentSurfaceReference?
  private var activeHarnessClearTransactionID: UUID?

  struct AuthorizedHarnessClearTransaction {
    fileprivate let id: UUID
    let surface: AgentSurfaceReference
  }

  private struct ChatSelectionRollbackState {
    let session: ChatSession?
    let wasDefault: Bool
    let messages: [ChatMessage]
    let paginationOffset: Int
    let hasMoreMessages: Bool
  }

  /// The last committed projection, retained while last-intent-wins selection
  /// requests overlap. A later failed request must never roll back to an older
  /// request's provisional session identity.
  private var chatSelectionRollbackState: ChatSelectionRollbackState?

  // MARK: - Filtered Sessions
  var filteredSessions: [ChatSession] {
    let starredSessions = showStarredOnly ? sessions.filter(\.starred) : sessions
    guard !searchQuery.isEmpty else { return starredSessions }
    let query = searchQuery.lowercased()
    return starredSessions.filter { session in
      session.title.lowercased().contains(query) || (session.preview?.lowercased().contains(query) ?? false)
    }
  }

  // MARK: - Cached Context for Prompts
  private var cachedMemories: [MemoryItem] = []
  private var memoriesLoaded = false
  private var cachedAIProfile: String = ""
  private var aiProfileLoaded = false

  // MARK: - Current Session ID
  var currentSessionId: String? {
    currentSession?.id
  }

  // MARK: - Current Model
  var currentModel: String {
    "Intentive"
  }

  // MARK: - System Prompt
  // Prompts are defined in ChatPrompts.swift (converted from Python backend)

  init() {
    isRestoringDraft = true
    draftText = ChatDraftStore.shared.text(for: activeDraftKey)
    isRestoringDraft = false
    isRestoringPendingAttachments = true
    pendingAttachments = ChatDraftStore.shared.attachments(for: activeDraftKey)
    pendingAttachmentsByDraftKey[activeDraftKey] = pendingAttachments
    isRestoringPendingAttachments = false
    restorePendingAttachmentScopes(pendingAttachments, for: activeDraftKey)
    log("ChatProvider initialized with direct conversation transport")

    // Observe changes to multiChatEnabled setting
    multiChatObserver = UserDefaults.standard.publisher(for: \.multiChatEnabled)
      .dropFirst()  // Skip initial value
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        Task { @MainActor in
          await self?.reinitialize()
        }
      }

    // Refresh messages when app becomes active
    activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in
        Task { @MainActor in
          await self?.refreshJournalProjection()
        }
      }

    // RuntimeOwnerIdentity posts this notification on MainActor while the
    // exclusive owner-transition fence is still held. Invalidate the
    // projection synchronously so a suspended owner A replay cannot publish
    // after owner B work is admitted.
    runtimeOwnerObserver = NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          self?.resetSessionStateForAuthChange()
        }
      }

    // Tear down conversation storage on sign-out. The owner-bound subprocess
    // bakes OMI_API_KEY (Firebase ID token) at spawn and holds an
    // in-memory `piSessions` map keyed only by legacy harness scope ("main"). When
    // the user signs out + back in with a different account, the next
    // message would otherwise reuse the previous user's session and the
    // omi-account proxy returns 402 against the old token. Stopping the
    // subprocess drops both the token and the session map; the next
    // sendMessage will spawn a fresh subprocess via ensureBridgeStarted.
    signOutObserver = NotificationCenter.default.publisher(for: .userDidSignOut)
      .sink { [weak self] _ in
        Task { @MainActor in
          guard let self = self else { return }
          log("ChatProvider: userDidSignOut — clearing chat state so the next user gets fresh context")
          if self.agentBridgeStarted {
            await self.resolvedAgentClient().stop()
            self.agentBridgeStarted = false
          }
          self.resetSessionStateForAuthChange()
          self.resetDraftAfterSignOut()
        }
      }

    // Light session invalidation (expired creds) — stop bridge only; preserve chat draft/state.
    sessionInvalidateObserver = NotificationCenter.default.publisher(for: .sessionDidInvalidate)
      .sink { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          log("ChatProvider: sessionDidInvalidate — stopping agent bridge")
          if self.agentBridgeStarted {
            await self.resolvedAgentClient().stop()
            self.agentBridgeStarted = false
          }
        }
      }

    // Cmd+R: refresh messages on demand
    refreshAllObserver = NotificationCenter.default.publisher(for: .refreshAllData)
      .sink { [weak self] _ in
        Task { @MainActor in
          await self?.refreshJournalProjection()
        }
      }

    // Keep groupedSessions in sync — runs off the hot path so SwiftUI body never recomputes it
    sessionGroupingObserver = Publishers.CombineLatest4($sessions, $searchQuery, $currentSession, $showStarredOnly)
      .receive(on: RunLoop.main)
      .sink { [weak self] _, _, _, _ in
        guard let self else { return }
        self.groupedSessions = self.computeGroupedSessions()
      }

    // Kill agent bridge subprocess on app quit to prevent orphaned Node.js processes
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      // The notification is delivered on the main queue, so force the
      // latest coalesced draft writes to disk before this callback can
      // return and the process exits (including Sparkle relaunches).
      MainActor.assumeIsolated {
        ChatDraftStore.shared.flush()
      }
      guard let self else { return }
      Task { @MainActor in
        await self.resolvedAgentClient().stop()
      }
    }
  }

  private var terminationObserver: NSObjectProtocol?

  private var currentDraftKey: ChatDraftKey {
    .mainChat(contextID: currentSession?.id ?? "default")
  }

  private func restoreDraftForCurrentContextIfNeeded() {
    let nextKey = currentDraftKey
    guard nextKey != activeDraftKey else { return }
    activeDraftKey = nextKey
    isRestoringDraft = true
    draftText = ChatDraftStore.shared.text(for: nextKey)
    isRestoringDraft = false
    isRestoringPendingAttachments = true
    let restoredAttachments =
      pendingAttachmentsByDraftKey[nextKey]
      ?? ChatDraftStore.shared.attachments(for: nextKey)
    pendingAttachmentsByDraftKey[nextKey] = restoredAttachments
    pendingAttachments = restoredAttachments
    isRestoringPendingAttachments = false
    restorePendingAttachmentScopes(restoredAttachments, for: nextKey)
  }

  private func restorePendingAttachmentScopes(
    _ attachments: [ChatAttachment],
    for key: ChatDraftKey
  ) {
    guard key.scope == "main_chat", let ownerID = runtimeOwnerId else { return }
    for attachment in attachments {
      pendingAttachmentScopes[attachment.id] = PendingAttachmentScope(
        ownerID: ownerID,
        chatID: key.contextID
      )
    }
  }

  private func resetDraftAfterSignOut() {
    activeDraftKey = .mainChat(contextID: "default")
    chatSelectionRollbackState = nil
    isRestoringDraft = true
    draftText = ""
    isRestoringDraft = false
    isRestoringPendingAttachments = true
    pendingAttachments = []
    isRestoringPendingAttachments = false
  }

  /// Pre-start the active bridge so the first query doesn't wait for process launch
  func warmupBridge() async -> Bool {
    await preparePromptContextIfNeeded()
    return await ensureBridgeStarted()
  }

  /// Drop a cached agent surface so the next query recreates it with fresh prompt context.
  func invalidateAgentSurface(surface: AgentSurfaceReference) async {
    conversationPromptBindings.reset()
  }

  /// Ensure the shared agent daemon is started (restarts only after process death).
  func ensureBridgeStartedForKernel() async -> Bool {
    await ensureBridgeStarted()
  }

  private func ensureBridgeStarted(
    authoritativeGeneration: Int? = nil
  ) async -> Bool {
    #if DEBUG
      if let ensureBridgeStartedForTests {
        return await ensureBridgeStartedForTests(authoritativeGeneration)
      }
    #endif
    guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      await presentBridgeStartupFailure(
        BridgeError.authMissing, authoritativeGeneration: authoritativeGeneration)
      return false
    }
    do {
      return try await bridgeReadinessSingleFlight.run(key: authorization) { [weak self] in
        guard let self else { throw BridgeError.stopped }
        return try await self.performBridgeReadinessStartup()
      }
    } catch {
      await presentBridgeStartupFailure(error, authoritativeGeneration: authoritativeGeneration)
      return false
    }
  }

  private func performBridgeReadinessStartup() async throws -> Bool {
    if agentBridgeStarted, await resolvedAgentClient().isAlive { return true }
    try await resolvedAgentClient().start()
    await kernelTurnProjection.attachClient(resolvedAgentClient())
    agentBridgeStarted = true
    return true
  }

  private func presentBridgeStartupFailure(
    _ error: Error,
    authoritativeGeneration: Int?
  ) async {
    logError("Failed to start conversation storage", error: error)
    let mayMutateSendState = authoritativeGeneration.map { sendGeneration == $0 } ?? true
    guard mayMutateSendState else { return }
    if let bridgeError = error as? BridgeError, let card = ChatErrorState.from(bridgeError) {
      currentError = card
      errorMessage = nil
    } else {
      errorMessage = "AI not available: \(error.localizedDescription)"
    }
  }

  /// Prepares retained Memory/profile context for conversational compute.
  private func preparePromptContextIfNeeded() async {
    await warmupPromptContext()
  }

  private func resetSessionStateForAuthChange() {
    // These files are owned by the outgoing account's persisted drafts, not by
    // this in-memory projection. Clearing the projection must not destroy bytes
    // that need to rehydrate if the user switches back to that account.
    activeConversationRequest?.cancel()
    conversationPromptBindings.reset()
    catalogOwnerGeneration &+= 1
    catalogMutationGeneration &+= 1
    catalogFetchGeneration &+= 1
    chatSelectionGeneration &+= 1
    isLoadingSessions = false
    kernelTurnProjection.invalidateOwnerState()
    journalWriteCoordinator.cancelAll()
    journalOwnerByMessageID.removeAll()
    journalTerminalTargets = ChatTerminalTargetRegistry<ChatJournalTerminalTarget>()
    // A ChatErrorCard belongs to the session that produced it. Retaining an
    // auth-required card after a successful account switch incorrectly asks
    // the newly signed-in user to sign in again.
    currentError = nil
    errorMessage = nil
    lastFailedPrompt = nil
    messages.removeAll()
    resetMessagesPagination()
    isRestoringPendingAttachments = true
    pendingAttachments.removeAll()
    isRestoringPendingAttachments = false
    pendingAttachmentsByDraftKey.removeAll()
    pendingAttachmentScopes.removeAll()
    draftRevisions.removeAll()
    pendingCreateChatID = nil
    if let activeRealtimeChatClearSurface {
      endRealtimeChatClear(surface: activeRealtimeChatClearSurface)
      self.activeRealtimeChatClearSurface = nil
    }
    activeHarnessClearTransactionID = nil
    isCreatingSession = false
    isClearing = false
    sessions.removeAll()
    currentSession = nil
    isInDefaultChat = true
    isLoading = false
    isLoadingMoreMessages = false
    deletingSessionIds.removeAll()
    activeDraftKey = .mainChat(contextID: "default")
    chatSelectionRollbackState = nil
    let hasCurrentOwner = runtimeOwnerId != nil
    isRestoringDraft = true
    draftText = hasCurrentOwner ? ChatDraftStore.shared.text(for: activeDraftKey) : ""
    isRestoringDraft = false
    let restoredAttachments =
      hasCurrentOwner
      ? ChatDraftStore.shared.attachments(for: activeDraftKey) : []
    pendingAttachmentsByDraftKey[activeDraftKey] = restoredAttachments
    isRestoringPendingAttachments = true
    pendingAttachments = restoredAttachments
    isRestoringPendingAttachments = false
    restorePendingAttachmentScopes(restoredAttachments, for: activeDraftKey)
    cachedMemories = []
    memoriesLoaded = false
    cachedAIProfile = ""
    aiProfileLoaded = false
  }

  private var runtimeOwnerId: String? {
    #if DEBUG
      if let runtimeOwnerIdForTests {
        return runtimeOwnerIdForTests()
      }
    #endif
    return RuntimeOwnerIdentity.currentOwnerId()
  }

  private func captureCatalogOwnerLease() -> CatalogOwnerLease {
    CatalogOwnerLease(
      ownerID: runtimeOwnerId,
      ownerGeneration: catalogOwnerGeneration,
      authorization: RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    )
  }

  private func isCatalogOwnerLeaseCurrent(_ lease: CatalogOwnerLease) -> Bool {
    guard lease.ownerGeneration == catalogOwnerGeneration,
      lease.ownerID == runtimeOwnerId
    else { return false }
    guard let authorization = lease.authorization else { return true }
    return RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
  }

  private func isChatSelectionLeaseCurrent(
    _ generation: UInt64,
    ownerLease: CatalogOwnerLease
  ) -> Bool {
    generation == chatSelectionGeneration && isCatalogOwnerLeaseCurrent(ownerLease)
  }

  private func reloadChatJournal(surface: AgentSurfaceReference) async -> Bool {
    #if DEBUG
      if let reloadChatJournalForTests { return await reloadChatJournalForTests(surface) }
    #endif
    return await kernelTurnProjection.reload(surface: surface)
  }

  private func beginRealtimeChatClear(surface: AgentSurfaceReference) -> Bool {
    #if DEBUG
      if let beginRealtimeChatClearForTests { return beginRealtimeChatClearForTests(surface) }
    #endif
    ConversationVoiceController.shared.close()
    conversationPromptBindings.reset()
    return true
  }

  private func endRealtimeChatClear(surface: AgentSurfaceReference) {
    #if DEBUG
      if let endRealtimeChatClearForTests {
        endRealtimeChatClearForTests(surface)
        return
      }
    #endif
    // Clear-generation fencing is enforced by the canonical journal.
  }

  /// Acquires the same typed-send, catalog-mutation, and realtime persistence
  /// exclusion boundary used by the product Clear action. Harness resets must
  /// hold this before touching the authoritative journal so an admitted turn
  /// cannot repopulate the chat after the reset returns.
  func beginAuthorizedHarnessClearTransaction(
    surface: AgentSurfaceReference
  ) -> (transaction: AuthorizedHarnessClearTransaction?, error: String?) {
    guard !isClearing else { return (nil, "chat clear already in progress") }
    guard !isCreatingSession else { return (nil, "new chat creation is in progress") }
    guard !isLoading else { return (nil, "chat loading is in progress") }
    guard deletingSessionIds.isEmpty else { return (nil, "chat deletion is in progress") }
    guard activeSendChatID == nil else { return (nil, "chat response is in progress") }
    guard beginRealtimeChatClear(surface: surface) else { return (nil, "voice turn is in progress") }
    let transaction = AuthorizedHarnessClearTransaction(id: UUID(), surface: surface)
    activeHarnessClearTransactionID = transaction.id
    activeRealtimeChatClearSurface = surface
    chatSelectionGeneration &+= 1
    isClearing = true
    return (transaction, nil)
  }

  func endAuthorizedHarnessClearTransaction(_ transaction: AuthorizedHarnessClearTransaction) {
    guard activeHarnessClearTransactionID == transaction.id,
      activeRealtimeChatClearSurface == transaction.surface
    else { return }
    endRealtimeChatClear(surface: transaction.surface)
    activeHarnessClearTransactionID = nil
    activeRealtimeChatClearSurface = nil
    isClearing = false
  }

  func isAuthorizedHarnessClearTransactionCurrent(
    _ transaction: AuthorizedHarnessClearTransaction
  ) -> Bool {
    activeHarnessClearTransactionID == transaction.id
      && activeRealtimeChatClearSurface == transaction.surface
      && isClearing
  }

  private func garbageCollectChatAttachments(
    ownerID: String,
    retaining retainedAttachmentURIs: Set<String>
  ) async throws {
    #if DEBUG
      if let garbageCollectChatAttachmentsForTests {
        try await garbageCollectChatAttachmentsForTests(ownerID, retainedAttachmentURIs)
        return
      }
    #endif
    try await LocalChatAttachmentStore.shared.garbageCollect(
      ownerID: ownerID,
      retaining: retainedAttachmentURIs
    )
  }

  func mainChatRuntimeChatId(sessionId: String?) -> String {
    guard let sessionId, !sessionId.isEmpty else { return "default" }
    return sessionId
  }

  private func querySurface(
    surfaceRef: AgentSurfaceReference?,
    sessionId: String?,
    systemPromptStyle: ChatSystemPromptStyle
  ) -> AgentSurfaceReference {
    switch Self.querySurfaceChoice(
      hasSurfaceRef: surfaceRef != nil, isOnboarding: isOnboarding,
      isFloating: systemPromptStyle == .floating)
    {
    case .onboarding: return .onboarding()
    case .explicit: return surfaceRef ?? .mainChat(chatId: mainChatRuntimeChatId(sessionId: sessionId))
    case .floatingMain: return mainChatSurfaceReference()
    case .defaultMain: return .mainChat(chatId: mainChatRuntimeChatId(sessionId: sessionId))
    }
  }

  private func journalOrigin(for surface: AgentSurfaceReference) -> String {
    switch surface.surfaceKind {
    case "floating_chat", "floating_bar": return "floating_chat"
    case "realtime": return "realtime_voice"
    default: return "typed_chat"
    }
  }

  private func listLocalChatCatalog() async throws -> LocalChatCatalogSnapshot {
    #if DEBUG
      if let listChatCatalogForTests {
        return LocalChatCatalogSnapshot(
          chats: try await listChatCatalogForTests(),
          retainedAttachmentURIs: []
        )
      }
    #endif
    return try await resolvedAgentClient().listChatCatalog()
  }

  private func createLocalChatCatalog(chatID: String, title: String?) async throws -> LocalChatSummary {
    #if DEBUG
      if let createChatCatalogForTests { return try await createChatCatalogForTests(chatID, title) }
    #endif
    return try await resolvedAgentClient().createChatCatalog(chatID: chatID, title: title)
  }

  private func updateLocalChatCatalog(
    chatID: String,
    title: String? = nil,
    titleOrigin: LocalChatTitleOrigin? = nil,
    expectedTitleOrigin: LocalChatTitleOrigin? = nil,
    starred: Bool? = nil
  ) async throws -> LocalChatSummary {
    let ownerLease = captureCatalogOwnerLease()
    let updated: LocalChatSummary
    #if DEBUG
      if let updateChatCatalogForTests {
        updated = try await updateChatCatalogForTests(
          chatID, title, titleOrigin, expectedTitleOrigin, starred)
      } else {
        updated = try await resolvedAgentClient().updateChatCatalog(
          chatID: chatID,
          title: title,
          titleOrigin: titleOrigin,
          expectedTitleOrigin: expectedTitleOrigin,
          starred: starred
        )
      }
    #else
      updated = try await resolvedAgentClient().updateChatCatalog(
        chatID: chatID,
        title: title,
        titleOrigin: titleOrigin,
        expectedTitleOrigin: expectedTitleOrigin,
        starred: starred
      )
    #endif
    guard isCatalogOwnerLeaseCurrent(ownerLease) else { throw BridgeError.authMissing }
    catalogMutationGeneration &+= 1
    return updated
  }

  private func deleteLocalChatCatalog(chatID: String) async throws -> Set<String> {
    let ownerLease = captureCatalogOwnerLease()
    let retainedAttachmentURIs: Set<String>
    #if DEBUG
      if let deleteChatCatalogForTests {
        retainedAttachmentURIs = try await deleteChatCatalogForTests(chatID)
      } else {
        retainedAttachmentURIs = try await resolvedAgentClient().deleteChatCatalog(chatID: chatID)
      }
    #else
      retainedAttachmentURIs = try await resolvedAgentClient().deleteChatCatalog(chatID: chatID)
    #endif
    guard isCatalogOwnerLeaseCurrent(ownerLease) else { throw BridgeError.authMissing }
    catalogMutationGeneration &+= 1
    return retainedAttachmentURIs
  }

  /// Load the owner-scoped catalog from the local Node authority.
  func fetchSessions() async {
    let ownerLease = captureCatalogOwnerLease()
    catalogFetchGeneration &+= 1
    let fetchGeneration = catalogFetchGeneration
    let startingMutationGeneration = catalogMutationGeneration
    isLoadingSessions = true
    defer {
      if catalogFetchGeneration == fetchGeneration {
        isLoadingSessions = false
      }
    }

    do {
      var snapshot = try await listLocalChatCatalog()
      var catalog = snapshot.chats
      if !catalog.contains(where: { $0.chatID == "default" }) {
        catalog.append(try await createLocalChatCatalog(chatID: "default", title: "New Chat"))
        snapshot = LocalChatCatalogSnapshot(
          chats: catalog,
          retainedAttachmentURIs: snapshot.retainedAttachmentURIs
        )
      }
      guard catalogFetchGeneration == fetchGeneration,
        catalogMutationGeneration == startingMutationGeneration,
        isCatalogOwnerLeaseCurrent(ownerLease)
      else {
        log("ChatProvider ignored a stale local catalog snapshot")
        return
      }
      sessions = multiChatEnabled ? catalog.map(\.chatSession) : []
      sessionsLoadError = nil

      if let ownerID = runtimeOwnerId {
        do {
          ChatDraftStore.shared.reconcileMainChatCatalog(
            ownerID: ownerID,
            retainingChatIDs: Set(catalog.map(\.chatID)).union(["default"])
          )
          let retainedAttachmentURIs = snapshot.retainedAttachmentURIs.union(
            ChatDraftStore.shared.managedAttachmentURIs(ownerID: ownerID)
          )
          try await garbageCollectChatAttachments(
            ownerID: ownerID,
            retaining: retainedAttachmentURIs
          )
        } catch {
          logError("Local attachment sweep remains pending", error: error)
        }
      }

      if let selectedID = currentSession?.id,
        !sessions.contains(where: { $0.id == selectedID })
      {
        await switchToDefaultChat()
      }
      log("ChatProvider loaded \(catalog.count) local catalog entries")
    } catch {
      guard catalogFetchGeneration == fetchGeneration,
        catalogMutationGeneration == startingMutationGeneration,
        isCatalogOwnerLeaseCurrent(ownerLease)
      else { return }
      sessions = []
      sessionsLoadError = error.localizedDescription
      logError("Failed to load local chat catalog", error: error)
    }
  }

  /// Refresh before presenting the popover so retained voice and other
  /// non-typed journal writes are reflected in preview/count/activity order.
  func refreshCatalogForPresentation() async {
    guard multiChatEnabled else { return }
    await fetchSessions()
  }

  /// Captures the journal-owned attachment references while the outgoing
  /// account is still authorized. Sign-out uses this to delete draft-only
  /// bytes without breaking an already accepted message after a crash-window
  /// left the same managed URI in both the draft and journal.
  func retainedJournalAttachmentURIsForSignOut(ownerID: String) async -> Set<String>? {
    let ownerLease = captureCatalogOwnerLease()
    guard ownerLease.ownerID == ownerID, isCatalogOwnerLeaseCurrent(ownerLease) else { return nil }
    do {
      let retained = try await listLocalChatCatalog().retainedAttachmentURIs
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return nil }
      return retained
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return nil }
      logError("ChatProvider: retained attachment capture failed before sign-out", error: error)
      return nil
    }
  }

  /// Toggle the local starred filter without refetching the authoritative catalog.
  func toggleStarredFilter() async {
    showStarredOnly.toggle()
    log("Toggled starred filter: \(showStarredOnly)")
    AnalyticsManager.shared.chatStarredFilterToggled(enabled: showStarredOnly)
  }

  /// Create a new chat session
  /// - Parameters:
  ///   - title: Optional session title
  ///   - skipGreeting: Skip the initial AI greeting message
  func createNewSession(
    title: String? = nil,
    skipGreeting: Bool = false,
    authoritativeSendGeneration: Int? = nil,
    allowWhileClearing: Bool = false
  ) async -> ChatSession? {
    guard !isCreatingSession else { return nil }
    guard !isClearing || allowWhileClearing else {
      errorMessage = "Wait for this chat to finish clearing before creating another chat."
      return nil
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before creating another chat."
      return nil
    }
    guard !isLoading else {
      errorMessage = "Wait for this chat to finish loading before creating another chat."
      return nil
    }
    let ownerLease = captureCatalogOwnerLease()
    isCreatingSession = true
    defer {
      if isCatalogOwnerLeaseCurrent(ownerLease) {
        isCreatingSession = false
      }
    }
    let chatID = pendingCreateChatID ?? UUID().uuidString.lowercased()
    pendingCreateChatID = chatID
    do {
      let session = try await createLocalChatCatalog(chatID: chatID, title: title).chatSession
      guard isCatalogOwnerLeaseCurrent(ownerLease) else {
        return nil
      }
      catalogMutationGeneration &+= 1
      pendingCreateChatID = nil
      guard authoritativeSendGeneration.map({ sendGeneration == $0 }) ?? true else { return nil }
      chatSelectionGeneration &+= 1
      if let existingIndex = sessions.firstIndex(where: { $0.id == session.id }) {
        sessions[existingIndex] = session
      } else {
        sessions.insert(session, at: 0)
      }
      currentSession = session
      isInDefaultChat = false
      if let ownerID = runtimeOwnerId {
        chatSelectionStore.setSelectedChatID(session.id, ownerID: ownerID)
      }
      messages = []
      resetMessagesPagination()
      ConversationVoiceController.shared.close()
      log("Created new chat session: \(session.id)")
      AnalyticsManager.shared.chatSessionCreated()

      // Generate the initial greeting message for the visible chat.
      if !skipGreeting {
        await fetchInitialMessage(for: session, authoritativeSendGeneration: authoritativeSendGeneration)
      }

      return isCatalogOwnerLeaseCurrent(ownerLease) ? session : nil
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return nil }
      logError("Failed to create chat session", error: error)
      if authoritativeSendGeneration.map({ sendGeneration == $0 }) ?? true {
        errorMessage = "Failed to create new chat"
      }
      return nil
    }
  }

  /// Fetch an initial greeting for a new session, then admit it through the
  /// canonical journal before it can appear in any visible projection.
  private func fetchInitialMessage(
    for session: ChatSession,
    authoritativeSendGeneration: Int? = nil
  ) async {
    do {
      let ownerLease = captureCatalogOwnerLease()
      guard let ownerId = ownerLease.ownerID, isCatalogOwnerLeaseCurrent(ownerLease) else {
        log("ChatProvider: initial greeting skipped because owner is unavailable")
        return
      }
      await refreshMemoriesForPrompt()
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      await loadAIProfileIfNeeded()
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      let memories = cachedMemories.prefix(20).map { String($0.content.prefix(1_000)) }
      let profileText = String(cachedAIProfile.prefix(8_000))
      let response: InitialMessageResponse
      #if DEBUG
        if let initialMessageForTests {
          response = try await initialMessageForTests(profileText, memories, ownerId)
        } else {
          response = try await APIClient.shared.getInitialMessage(
            profileText: profileText,
            memories: memories,
            expectedOwnerId: ownerId
          )
        }
      #else
        response = try await APIClient.shared.getInitialMessage(
          profileText: profileText,
          memories: memories,
          expectedOwnerId: ownerId
        )
      #endif
      guard isCatalogOwnerLeaseCurrent(ownerLease),
        authoritativeSendGeneration.map({ sendGeneration == $0 }) ?? true
      else { return }

      let surface = AgentSurfaceReference.mainChat(
        chatId: mainChatRuntimeChatId(sessionId: session.id)
      )
      let greeting = ChatMessage(
        id: UUID().uuidString.lowercased(),
        text: response.message,
        sender: .ai,
        isSynced: true,
        journalStatus: .completed
      )
      let accepted: Bool
      #if DEBUG
        if let recordInitialGreetingForTests {
          accepted = await recordInitialGreetingForTests(surface, greeting, ownerId)
        } else {
          accepted =
            await kernelTurnProjection.recordTurn(
              surface: surface,
              message: greeting,
              origin: "typed_chat",
              status: .completed,
              ownerID: ownerId
            ) != nil
        }
      #else
        accepted =
          await kernelTurnProjection.recordTurn(
            surface: surface,
            message: greeting,
            origin: "typed_chat",
            status: .completed,
            ownerID: ownerId
          ) != nil
      #endif
      guard isCatalogOwnerLeaseCurrent(ownerLease), accepted else {
        log("ChatProvider: initial greeting journal admission failed")
        return
      }

      // Preview is also downstream of canonical journal acceptance.
      if let index = sessions.firstIndex(where: { $0.id == session.id }) {
        sessions[index].preview = response.message
      }

      // Track analytics
      AnalyticsManager.shared.initialMessageGenerated()

      log("Added initial greeting message for session \(session.id)")
    } catch {
      // Non-fatal: session still works without greeting
      logError("Failed to fetch initial message", error: error)
    }
  }

  /// Select a session and load its messages
  func selectSession(_ session: ChatSession, force: Bool = false) async {
    guard !isClearing else {
      errorMessage = "Wait for this chat to finish clearing before switching chats."
      return
    }
    guard !isCreatingSession else {
      errorMessage = "Wait for the new chat to finish opening before switching chats."
      return
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before switching chats."
      return
    }
    if session.id == "default" {
      await switchToDefaultChat()
      return
    }
    guard force || currentSession?.id != session.id || isInDefaultChat else { return }
    let ownerLease = captureCatalogOwnerLease()
    let rollbackState =
      chatSelectionRollbackState
      ?? ChatSelectionRollbackState(
        session: currentSession,
        wasDefault: isInDefaultChat,
        messages: messages,
        paginationOffset: messagesPaginationOffset,
        hasMoreMessages: hasMoreMessages
      )
    chatSelectionRollbackState = rollbackState
    chatSelectionGeneration &+= 1
    let selectionGeneration = chatSelectionGeneration

    currentSession = session
    isInDefaultChat = false
    isLoading = true
    errorMessage = nil
    hasMoreMessages = false

    let surface = mainChatSurfaceReference()
    guard await ensureBridgeStartedForKernel(),
      isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease)
    else {
      guard isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease) else { return }
      currentSession = rollbackState.session
      isInDefaultChat = rollbackState.wasDefault
      messages = rollbackState.messages
      messagesPaginationOffset = rollbackState.paginationOffset
      hasMoreMessages = rollbackState.hasMoreMessages
      chatSelectionRollbackState = nil
      errorMessage = "Failed to load chat"
      isLoading = false
      return
    }
    guard await reloadChatJournal(surface: surface),
      isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease)
    else {
      guard isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease) else { return }
      currentSession = rollbackState.session
      isInDefaultChat = rollbackState.wasDefault
      messages = rollbackState.messages
      messagesPaginationOffset = rollbackState.paginationOffset
      hasMoreMessages = rollbackState.hasMoreMessages
      chatSelectionRollbackState = nil
      errorMessage = "Failed to load chat"
      isLoading = false
      return
    }
    guard isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease) else { return }
    guard isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease) else { return }
    if let ownerID = ownerLease.ownerID {
      chatSelectionStore.setSelectedChatID(session.id, ownerID: ownerID)
    }
    ConversationVoiceController.shared.close()
    messagesPaginationOffset = messages.count
    hasMoreMessages = false
    chatSelectionRollbackState = nil
    log("ChatProvider loaded \(messages.count) kernel journal messages for session \(session.id)")

    isLoading = false
  }

  /// Load more (older) messages for the current session
  func loadMoreMessages() async {
    guard !isLoadingMoreMessages else { return }

    isLoadingMoreMessages = true

    await kernelTurnProjection.refresh(surface: mainChatSurfaceReference())
    messagesPaginationOffset = messages.count
    hasMoreMessages = false

    isLoadingMoreMessages = false
  }

  /// Track which sessions are currently being deleted
  @Published var deletingSessionIds: Set<String> = []

  /// Preserve baseline clear semantics with local authority: `default` clears
  /// in place; a named chat is atomically deleted and replaced by a fresh local
  /// session (including its normal greeting).
  func clearCurrentChat() async {
    guard !isClearing else { return }
    guard !isCreatingSession else {
      errorMessage = "Wait for the new chat to finish opening before clearing this chat."
      return
    }
    guard !isLoading else {
      errorMessage = "Wait for this chat to finish loading before clearing it."
      return
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before clearing this chat."
      return
    }
    guard activeSendChatID == nil else {
      errorMessage = "Wait for the current response to finish before clearing this chat."
      return
    }
    let ownerLease = captureCatalogOwnerLease()
    guard let ownerID = ownerLease.ownerID else {
      errorMessage = "Failed to clear chat"
      return
    }
    let chatID = currentSession?.id ?? "default"
    let surface = AgentSurfaceReference.mainChat(chatId: chatID)
    guard beginRealtimeChatClear(surface: surface) else {
      errorMessage = "Wait for the current voice turn to finish before clearing this chat."
      return
    }
    activeRealtimeChatClearSurface = surface
    chatSelectionGeneration &+= 1
    isClearing = true
    defer {
      if isCatalogOwnerLeaseCurrent(ownerLease) {
        endRealtimeChatClear(surface: surface)
        if activeRealtimeChatClearSurface == surface {
          activeRealtimeChatClearSurface = nil
        }
        isClearing = false
      }
    }
    var attachmentCleanupPending = false

    if chatID == "default" {
      let cleared: Bool
      #if DEBUG
        if let clearChatJournalForTests {
          cleared = await clearChatJournalForTests(chatID)
        } else {
          cleared = await kernelTurnProjection.clearOwnerSurfaceState(chatId: chatID)
        }
      #else
        cleared = await kernelTurnProjection.clearOwnerSurfaceState(chatId: chatID)
      #endif
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      guard cleared else {
        errorMessage = "Failed to clear chat"
        return
      }
      if isInDefaultChat && currentSession == nil {
        messages = []
        resetMessagesPagination()
      }
      await fetchSessions()
    } else {
      let retainedAttachmentURIs: Set<String>
      do {
        retainedAttachmentURIs = try await deleteLocalChatCatalog(chatID: chatID)
      } catch {
        guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
        errorMessage = "Failed to clear chat"
        logError("Failed to replace cleared local chat", error: error)
        return
      }
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      let deletedDraftKey = ChatDraftKey.mainChat(contextID: chatID)
      let deletedAttachments = pendingAttachmentsByDraftKey.removeValue(forKey: deletedDraftKey) ?? []
      for attachment in deletedAttachments {
        pendingAttachmentScopes.removeValue(forKey: attachment.id)
      }
      ChatDraftStore.shared.clear(deletedDraftKey, ownerID: ownerID)
      ChatDraftStore.shared.flush()
      sessions.removeAll { $0.id == chatID }
      currentSession = nil
      isInDefaultChat = true
      messages = []
      resetMessagesPagination()

      do {
        try await garbageCollectChatAttachments(
          ownerID: ownerID,
          retaining: retainedAttachmentURIs.union(
            ChatDraftStore.shared.managedAttachmentURIs(ownerID: ownerID)
          )
        )
      } catch {
        attachmentCleanupPending = true
        logError("Cleared chat attachment cleanup will retry", error: error)
      }
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      guard await createNewSession(allowWhileClearing: true) != nil else {
        guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
        errorMessage = "Chat cleared, but a new chat couldn't be opened."
        return
      }
    }
    guard isCatalogOwnerLeaseCurrent(ownerLease), runtimeOwnerId == ownerID else { return }
    errorMessage =
      attachmentCleanupPending
      ? "Chat cleared. Attachment cleanup will retry automatically."
      : nil
    log("Cleared local chat journal: \(chatID)")
    AnalyticsManager.shared.chatCleared()
  }

  /// Harness counterpart for a named chat whose journal clear has already
  /// succeeded. The local catalog remains authoritative, so removing only the
  /// Swift row would let the old chat reappear on the next catalog fetch.
  func deleteNamedChatCatalogForAuthorizedHarness(_ session: ChatSession) async -> String? {
    let ownerLease = captureCatalogOwnerLease()
    guard let ownerID = ownerLease.ownerID else { return "missing owner for named chat reset" }
    let retainedAttachmentURIs: Set<String>
    do {
      retainedAttachmentURIs = try await deleteLocalChatCatalog(chatID: session.id)
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else {
        return "owner changed during named chat reset"
      }
      logError("Harness failed to delete named local chat catalog", error: error)
      return "failed to delete named local chat catalog"
    }
    guard isCatalogOwnerLeaseCurrent(ownerLease) else {
      return "owner changed during named chat reset"
    }

    let deletedDraftKey = ChatDraftKey.mainChat(contextID: session.id)
    let deletedAttachments = pendingAttachmentsByDraftKey.removeValue(forKey: deletedDraftKey) ?? []
    for attachment in deletedAttachments {
      pendingAttachmentScopes.removeValue(forKey: attachment.id)
    }
    ChatDraftStore.shared.clear(deletedDraftKey, ownerID: ownerID)
    ChatDraftStore.shared.flush()
    sessions.removeAll { $0.id == session.id }
    chatSelectionGeneration &+= 1
    currentSession = nil
    isInDefaultChat = true
    messages = []
    resetMessagesPagination()

    do {
      try await garbageCollectChatAttachments(
        ownerID: ownerID,
        retaining: retainedAttachmentURIs.union(
          ChatDraftStore.shared.managedAttachmentURIs(ownerID: ownerID)
        )
      )
    } catch {
      logError("Harness named-chat attachment cleanup will retry", error: error)
    }
    return nil
  }

  /// Delete a chat session
  func deleteSession(_ session: ChatSession) async {
    guard session.id != "default" else {
      errorMessage = "The default chat cannot be deleted."
      return
    }
    guard !isCreatingSession else {
      errorMessage = "Wait for the new chat to finish opening before deleting it."
      return
    }
    guard activeSendChatID == nil else {
      errorMessage = "Wait for the current response to finish before deleting a chat."
      return
    }
    guard !isClearing else {
      errorMessage = "Wait for this chat to finish clearing before deleting a chat."
      return
    }
    guard !isLoading else {
      errorMessage = "Wait for this chat to finish loading before deleting a chat."
      return
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before deleting another chat."
      return
    }
    let ownerLease = captureCatalogOwnerLease()
    deletingSessionIds.insert(session.id)
    defer {
      if isCatalogOwnerLeaseCurrent(ownerLease) {
        deletingSessionIds.remove(session.id)
      }
    }
    let retainedAttachmentURIs: Set<String>
    let ownerID: String
    do {
      guard let currentOwnerID = runtimeOwnerId else { throw BridgeError.authMissing }
      ownerID = currentOwnerID
      retainedAttachmentURIs = try await deleteLocalChatCatalog(chatID: session.id)
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      errorMessage = "Failed to delete chat"
      logError("Failed to delete local chat", error: error)
      return
    }
    guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
    let deletedDraftKey = ChatDraftKey.mainChat(contextID: session.id)
    let deletedAttachments = pendingAttachmentsByDraftKey.removeValue(forKey: deletedDraftKey) ?? []
    for attachment in deletedAttachments {
      pendingAttachmentScopes.removeValue(forKey: attachment.id)
    }
    ChatDraftStore.shared.clear(deletedDraftKey, ownerID: ownerID)
    ChatDraftStore.shared.flush()
    sessions.removeAll { $0.id == session.id }

    var fallbackSession: ChatSession?
    if currentSession?.id == session.id {
      chatSelectionGeneration &+= 1
      currentSession = nil
      isInDefaultChat = true
      messages = []
      resetMessagesPagination()
      fallbackSession = sessions.first
    }

    log("Deleted local chat: \(session.id)")
    AnalyticsManager.shared.chatSessionDeleted()

    var attachmentCleanupPending = false
    do {
      let allRetainedAttachmentURIs = retainedAttachmentURIs.union(
        ChatDraftStore.shared.managedAttachmentURIs(ownerID: ownerID)
      )
      try await garbageCollectChatAttachments(
        ownerID: ownerID,
        retaining: allRetainedAttachmentURIs
      )
    } catch {
      attachmentCleanupPending = true
      logError("Deleted local chat but attachment cleanup is pending", error: error)
    }
    guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
    // Keep the deletion gate held through the retained-URI snapshot and GC so
    // no accepted send can add an attachment between those two operations.
    deletingSessionIds.remove(session.id)
    if let fallbackSession {
      await selectSession(fallbackSession)
    }
    guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
    if attachmentCleanupPending {
      errorMessage = "Chat deleted. Attachment cleanup will retry automatically."
    }
  }

  /// Toggle starred status for a session
  func toggleStarred(_ session: ChatSession) async {
    guard !isClearing else {
      errorMessage = "Wait for this chat to finish clearing before updating a chat."
      return
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before updating a chat."
      return
    }
    let ownerLease = captureCatalogOwnerLease()
    do {
      let updated = try await updateLocalChatCatalog(
        chatID: session.id,
        starred: !session.starred
      ).chatSession
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }

      // Update in sessions list
      if let index = sessions.firstIndex(where: { $0.id == session.id }) {
        sessions[index] = updated
      }

      // Update current session if it's the same
      if currentSession?.id == session.id {
        currentSession = updated
      }

      log("Toggled starred for session \(session.id): \(updated.starred)")
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      errorMessage = "Couldn't update this chat. Try again."
      logError("Failed to toggle starred", error: error)
    }
  }

  /// Update session title (user-initiated rename)
  func updateSessionTitle(_ session: ChatSession, title: String) async {
    guard !isClearing else {
      errorMessage = "Wait for this chat to finish clearing before renaming a chat."
      return
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before renaming a chat."
      return
    }
    let ownerLease = captureCatalogOwnerLease()
    do {
      let updated = try await updateLocalChatCatalog(
        chatID: session.id,
        title: title,
        titleOrigin: .manual
      ).chatSession
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }

      // Update in sessions list
      if let index = sessions.firstIndex(where: { $0.id == session.id }) {
        sessions[index] = updated
      }

      // Update current session if it's the same
      if currentSession?.id == session.id {
        currentSession = updated
      }

      log("Updated title for session \(session.id): \(title)")
      AnalyticsManager.shared.sessionRenamed()
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      errorMessage = "Couldn't rename this chat. Try again."
      logError("Failed to update session title", error: error)
    }
  }

  // MARK: - Load Context (Memories)

  /// Loads user memories from local SQLite for use in prompts (refreshed each turn).
  private func refreshMemoriesForPrompt() async {
    let ownerLease = captureCatalogOwnerLease()
    #if DEBUG
      if let refreshMemoriesForPromptForTests {
        await refreshMemoriesForPromptForTests()
        guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
        return
      }
    #endif
    do {
      let memories = try await MemoryStorage.shared.list(limit: 50)
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      cachedMemories = memories
      memoriesLoaded = true
      log("ChatProvider refreshed \(cachedMemories.count) memories from local DB")
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      logError("Failed to load memories from local DB", error: error)
      // Continue without memories - non-critical
    }
  }

  /// Formats cached memories into a string for the prompt
  private func formatMemoriesSection() -> String {
    guard !cachedMemories.isEmpty else { return "" }

    let userName = AuthService.shared.displayName.isEmpty ? "the user" : AuthService.shared.givenName

    var lines: [String] = ["<user_facts>", "Facts about \(userName):"]
    for memory in cachedMemories.prefix(30) {  // Limit to 30 most relevant
      lines.append("- [memory] \(memory.content)")
    }
    lines.append("</user_facts>")

    return lines.joined(separator: "\n")
  }

  // MARK: - Load Goals

  /// Refreshes user goals from the current owner's local SQLite database for
  /// every prompt so a task/goal mutation is visible on the next Chat turn.
  private func loadAIProfileIfNeeded() async {
    guard !aiProfileLoaded else { return }
    let ownerLease = captureCatalogOwnerLease()
    #if DEBUG
      if let loadAIProfileForTests {
        let profileText = await loadAIProfileForTests()
        guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
        if let profileText { cachedAIProfile = profileText }
        aiProfileLoaded = true
        return
      }
    #endif
    let profile = await AIUserProfileService.shared.getLatestProfile()
    guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
    if let profile {
      cachedAIProfile = profile.profileText
      log("ChatProvider loaded AI profile (generated \(profile.generatedAt))")
    }
    aiProfileLoaded = true
  }

  /// Formats AI profile into a prompt section
  private func formatAIProfileSection() -> String {
    guard !cachedAIProfile.isEmpty else { return "" }
    return "\n<ai_user_profile>\n\(cachedAIProfile)\n</ai_user_profile>"
  }

  // MARK: - Load Database Schema

  /// Queries sqlite_master to build an up-to-date schema description for the prompt
  func initialize() async {
    await initializeVisibleMessages()
    await warmupPromptContext()
  }

  /// Load the chat state that is directly visible in Dashboard/Chat without warming prompt-only context.
  func initializeVisibleMessages() async {
    if multiChatEnabled {
      await fetchSessions()
      let selectedChatID = runtimeOwnerId.map { chatSelectionStore.selectedChatID(ownerID: $0) } ?? "default"
      if selectedChatID != "default",
        let selectedSession = sessions.first(where: { $0.id == selectedChatID })
      {
        await selectSession(selectedSession, force: true)
      } else {
        await switchToDefaultChat()
      }
    } else {
      // Single chat mode: just load default chat messages (syncs with Flutter)
      isLoadingSessions = false
      await loadDefaultChatMessages()
    }
  }

  /// Warm local prompt context used by first send / bridge startup.
  func warmupPromptContext() async {
    await refreshMemoriesForPrompt()
    await loadAIProfileIfNeeded()
  }

  /// Reinitialize after settings change
  func reinitialize() async {
    sessions = []
    messages = []
    resetMessagesPagination()
    currentSession = nil
    isInDefaultChat = true
    await initialize()
  }

  /// Retry loading after a failure — clears error state and re-runs initialize
  func retryLoad() async {
    sessionsLoadError = nil
    await initialize()
  }

  /// Switch to the stable local `default` chat.
  func switchToDefaultChat() async {
    guard !isClearing else {
      errorMessage = "Wait for this chat to finish clearing before switching chats."
      return
    }
    guard !isCreatingSession else {
      errorMessage = "Wait for the new chat to finish opening before switching chats."
      return
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before switching chats."
      return
    }
    let ownerLease = captureCatalogOwnerLease()
    let rollbackState =
      chatSelectionRollbackState
      ?? ChatSelectionRollbackState(
        session: currentSession,
        wasDefault: isInDefaultChat,
        messages: messages,
        paginationOffset: messagesPaginationOffset,
        hasMoreMessages: hasMoreMessages
      )
    chatSelectionRollbackState = rollbackState
    chatSelectionGeneration &+= 1
    let selectionGeneration = chatSelectionGeneration
    currentSession = nil
    isInDefaultChat = true
    let loaded = await loadDefaultChatMessages(expectedSelectionGeneration: selectionGeneration)
    guard isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease) else { return }
    guard loaded else {
      currentSession = rollbackState.session
      isInDefaultChat = rollbackState.wasDefault
      messages = rollbackState.messages
      messagesPaginationOffset = rollbackState.paginationOffset
      hasMoreMessages = rollbackState.hasMoreMessages
      chatSelectionRollbackState = nil
      errorMessage = "Failed to load chat"
      return
    }
    if let ownerID = ownerLease.ownerID {
      chatSelectionStore.setSelectedChatID("default", ownerID: ownerID)
    }
    ConversationVoiceController.shared.close()
    chatSelectionRollbackState = nil
    log("Switched to default chat")
  }

  /// Load the kernel-owned default-chat journal.
  @discardableResult
  func loadDefaultChatMessages(expectedSelectionGeneration: UInt64? = nil) async -> Bool {
    let selectionGeneration: UInt64
    if let expectedSelectionGeneration {
      selectionGeneration = expectedSelectionGeneration
    } else {
      chatSelectionGeneration &+= 1
      selectionGeneration = chatSelectionGeneration
    }
    let ownerLease = captureCatalogOwnerLease()
    let ownsSelection = {
      selectionGeneration == self.chatSelectionGeneration
        && self.isCatalogOwnerLeaseCurrent(ownerLease)
    }
    guard ownsSelection() else { return false }
    isLoading = true
    errorMessage = nil
    hasMoreMessages = false

    do {
      _ = try await createLocalChatCatalog(chatID: "default", title: "New Chat")
    } catch {
      guard ownsSelection() else { return false }
      messages = []
      resetMessagesPagination()
      sessionsLoadError = error.localizedDescription
      isLoading = false
      return false
    }

    guard ownsSelection() else { return false }

    let surface = mainChatSurfaceReference()
    guard await ensureBridgeStartedForKernel() else {
      guard ownsSelection() else { return false }
      messages = []
      resetMessagesPagination()
      sessionsLoadError = "Failed to load messages"
      isLoading = false
      return false
    }
    guard ownsSelection() else { return false }
    guard await reloadChatJournal(surface: surface) else {
      guard ownsSelection() else { return false }
      sessionsLoadError = "Failed to load messages"
      isLoading = false
      return false
    }
    guard ownsSelection() else { return false }
    guard ownsSelection() else { return false }
    messagesPaginationOffset = messages.count
    hasMoreMessages = false
    sessionsLoadError = nil
    log("ChatProvider loaded \(messages.count) default kernel journal messages")
    isLoading = false
    return true
  }

  // MARK: - Kernel Journal Refresh

  /// Activation/notification is only a wakeup. Ordered range replay in
  /// KernelTurnProjection is the sole source of new or updated messages.
  private func refreshJournalProjection() async {
    guard await ensureBridgeStartedForKernel() else { return }
    await kernelTurnProjection.refresh(surface: mainChatSurfaceReference())
  }

  // MARK: - Stop

  /// Stop the running agent, keeping partial response
  func canInterruptActiveTurn(owner: ChatTurnOwner) -> Bool {
    guard isSending else { return true }
    guard let activeTurnOwner else { return false }
    return owner.canInterrupt(activeTurnOwner)
  }

  @discardableResult
  func stopAgent(owner: ChatTurnOwner) -> Bool {
    stopAgent(owner: owner, reason: .userStop)
  }

  @discardableResult
  func stopAgent(owner: ChatTurnOwner, reason: ChatTurnStopReason) -> Bool {
    guard isSending, let activeTurnOwner, owner.canInterrupt(activeTurnOwner) else { return false }
    let generation = sendGeneration
    if let direct = activeDirectConversation, direct.generation == generation {
      ConversationVoiceController.shared.observeTextOnlyTurn(
        turnID: direct.turnID,
        userText: direct.userText, assistantText: activeConversationText,
        outcome: "interrupted", isFinal: true)
      ConversationVoiceController.shared.finishTextOnlyTurn(turnID: direct.turnID)
      activeDirectConversation = nil
    } else if ConversationVoiceController.shared.isOpen {
      ConversationVoiceController.shared.interruptReply()
    }
    activeStopReason = (generation, reason)
    finishActiveChatTelemetry(
      generation: generation, stopReason: reason,
      partialResponse: !activeConversationText.isEmpty)
    sendGeneration += 1
    activeConversationRequest?.cancel()
    activeConversationRequest = nil
    streamingBuffer.cancelPendingFlush()
    flushStreamingBuffer()
    Task { [weak self] in
      _ = await self?.finishJournalTarget(generation: generation, status: .failed)
    }
    _ = releaseSendLock(sendGeneration: generation)
    return true
  }

  /// Record through the canonical journal before returning anything that a
  /// surface can project. `recordExchange` publishes the pending/accepted rows
  /// during its refresh, so low-latency UI and durable identity are one path.
  @discardableResult
  func recordJournalExchange(
    surface: AgentSurfaceReference? = nil,
    ownerID: String? = nil,
    continuityKey: String,
    userText: String,
    assistantText: String,
    origin: String,
    contentBlocks: [ChatContentBlock] = [],
    resources: [ChatResource] = [],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async -> (user: ChatMessage?, assistant: ChatMessage?) {
    let targetSurface = surface ?? mainChatSurfaceReference()
    let normalizedContinuityKey = continuityKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return await admitJournalExchange(
      continuityKey: normalizedContinuityKey,
      userText: userText,
      assistantText: assistantText,
      contentBlocks: contentBlocks,
      resources: resources
    ) { [weak self] in
      guard let self else { return false }
      return await self.kernelTurnProjection.recordExchange(
        surface: targetSurface,
        userText: userText,
        assistantText: assistantText,
        origin: origin,
        continuityKey: normalizedContinuityKey,
        assistantContentBlocks: contentBlocks,
        resources: resources,
        ownerID: ownerID,
        authorizationSnapshot: authorizationSnapshot
      )
    }
  }

  /// Atomic admission for the user row plus its empty streaming response
  /// target. Keeping this as one production seam lets tests reject the
  /// canonical transaction and prove neither visible half is exposed.
  @discardableResult
  func recordStreamingJournalExchange(
    surface: AgentSurfaceReference,
    ownerID: String,
    continuityKey: String,
    userMessage: ChatMessage,
    assistantMessage: ChatMessage,
    origin: String,
    sessionId: String?,
    messageSource: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    expectedGeneration: Int? = nil
  ) async -> Bool {
    #if DEBUG
      if let recordStreamingJournalExchangeForTests {
        guard let projected = await recordStreamingJournalExchangeForTests(userMessage, assistantMessage)
        else { return false }
        messages = projected
        return true
      }
    #endif
    return await admitStreamingJournalExchange(
      userMessage: userMessage,
      assistantMessage: assistantMessage
    ) { [weak self] turns in
      guard let self else { return nil }
      return await self.kernelTurnProjection.recordExchange(
        surface: surface,
        turns: turns,
        origin: origin,
        continuityKey: continuityKey,
        sessionId: sessionId,
        messageSource: messageSource,
        ownerID: ownerID,
        authorizationSnapshot: authorizationSnapshot,
        expectedGeneration: expectedGeneration
      )
    }
  }

  @discardableResult
  func admitStreamingJournalExchange(
    userMessage: ChatMessage,
    assistantMessage: ChatMessage,
    recordCanonicalExchange:
      @MainActor (
        _ turns: [KernelTurnProjection.ExchangeTurn]
      ) async -> [KernelJournalTurn]?
  ) async -> Bool {
    guard userMessage.sender == .user,
      assistantMessage.sender == .ai,
      assistantMessage.isStreaming,
      userMessage.clientTurnId == assistantMessage.clientTurnId
    else {
      return false
    }
    let turns: [KernelTurnProjection.ExchangeTurn] = [
      .init(message: userMessage, status: .completed),
      .init(message: assistantMessage, status: .streaming),
    ]
    return await recordCanonicalExchange(turns) != nil
  }

  /// Behavioral seam for the journal-first admission contract. Tests inject a
  /// controllable canonical recorder; production passes the kernel journal.
  /// This method itself never appends or merges `messages`.
  @discardableResult
  func admitJournalExchange(
    continuityKey: String,
    userText: String,
    assistantText: String,
    contentBlocks: [ChatContentBlock] = [],
    resources: [ChatResource] = [],
    recordCanonicalExchange: @MainActor () async -> Bool
  ) async -> (user: ChatMessage?, assistant: ChatMessage?) {
    let key = continuityKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    let assistant = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return (nil, nil) }
    guard !user.isEmpty || !assistant.isEmpty || !contentBlocks.isEmpty || !resources.isEmpty else {
      return (nil, nil)
    }
    guard await recordCanonicalExchange() else { return (nil, nil) }

    let userID = KernelTurnProjection.stableTurnID(continuityKey: key, role: "user")
    let assistantID = KernelTurnProjection.stableTurnID(continuityKey: key, role: "assistant")
    return (
      user: user.isEmpty ? nil : messages.first(where: { $0.id == userID }),
      assistant: assistant.isEmpty && contentBlocks.isEmpty && resources.isEmpty
        ? nil
        : messages.first(where: { $0.id == assistantID })
    )
  }

  func mainChatSurfaceReference() -> AgentSurfaceReference {
    .mainChat(chatId: mainChatRuntimeChatId(sessionId: isInDefaultChat ? nil : currentSessionId))
  }

  func shouldProjectJournalSurface(_ surface: AgentSurfaceReference) -> Bool {
    surface.externalRefKind == "chat"
      && surface.externalRefId == mainChatSurfaceReference().externalRefId
  }

  /// PTT is a realtime projection of the selected main chat, never a second
  /// chat. Retain the exact external reference so the runtime resolves the
  /// canonical main-chat conversation for non-default chats.
  func realtimeVoiceSurfaceReference() -> AgentSurfaceReference {
    mainChatSurfaceReference().realtimeVoiceCompanion()
  }

  /// Upsert by canonical turn ID only. Text equality is deliberately ignored:
  /// two identical messages with distinct turn IDs are distinct journal rows.
  /// Some `ChatMessage` fields live only in the in-memory row and are never
  /// written to the kernel journal, so `KernelJournalTurn.chatMessage()` cannot
  /// reconstruct them and a journal projection can never be their authority:
  /// `metadata` (model/token/cost stats attached at completion, rendered in the
  /// message footer) and `notificationScreenshot`.
  /// Replacing a row wholesale with the projection would drop them, so carry
  /// them forward from the row being replaced. A field the projection *does*
  /// carry (non-nil) wins, so this stays correct if the journal schema later
  /// starts persisting one of them.
  static func carryingLocalOnlyFields(_ projected: ChatMessage, from existing: ChatMessage) -> ChatMessage {
    var merged = projected
    if merged.metadata == nil { merged.metadata = existing.metadata }
    if merged.notificationScreenshot == nil { merged.notificationScreenshot = existing.notificationScreenshot }
    return merged
  }

  func resetJournalProjection(surface: AgentSurfaceReference) {
    guard surface == mainChatSurfaceReference() else { return }
    messages = []
    resetMessagesPagination()
  }

  private func scheduleJournalUpdate(
    messageId: String,
    status: KernelJournalTurnStatus? = nil,
    surface: AgentSurfaceReference? = nil
  ) {
    guard let message = messages.first(where: { $0.id == messageId }) else { return }
    guard let ownerID = journalOwnerByMessageID[messageId] ?? runtimeOwnerId else { return }
    let targetSurface = surface ?? mainChatSurfaceReference()
    // A `.streaming` coalesce must never land after the terminal mutation (it
    // would regress the turn back to streaming), so it stays gated by
    // terminalization. Every other update is a durable, non-regressing content
    // mutation and must remain journalable after the turn terminalizes.
    journalWriteCoordinator.schedule(
      messageID: messageId,
      supersededByTerminalization: status == .streaming
    ) { @MainActor [weak self] in
      guard let self else { return }
      _ = await self.kernelTurnProjection.updateTurn(
        surface: targetSurface,
        message: message,
        status: status,
        ownerID: ownerID
      )
    }
  }

  private func finishJournalUpdate(
    messageId: String,
    status: KernelJournalTurnStatus,
    surface: AgentSurfaceReference? = nil,
    ownerID: String
  ) async -> Bool {
    let targetSurface = surface ?? mainChatSurfaceReference()
    if let message = messages.first(where: { $0.id == messageId }) {
      return await kernelTurnProjection.updateTurn(
        surface: targetSurface,
        message: message,
        status: status,
        ownerID: ownerID
      ) != nil
    }
    return await kernelTurnProjection.updateTurnStatus(
      surface: targetSurface,
      turnId: messageId,
      status: status,
      ownerID: ownerID
    ) != nil
  }

  /// Claim and finalize one generation's canonical assistant row exactly
  /// once. The target is removed before awaiting so stop fallback and a late
  /// adapter completion cannot race two terminal journal updates or callbacks.
  private func finishJournalTarget(
    generation: Int,
    status: KernelJournalTurnStatus
  ) async -> Bool {
    guard let target = journalTerminalTargets.claim(generation: generation) else {
      return false
    }
    guard
      await journalWriteCoordinator.beginTerminalization(
        messageID: target.assistantMessageId
      )
    else {
      target.onFinalized?(false)
      return false
    }
    let accepted = await journalWriteCoordinator.retryTerminalization {
      await self.finishJournalUpdate(
        messageId: target.assistantMessageId,
        status: status,
        surface: target.surface,
        ownerID: target.ownerID
      )
    }
    journalOwnerByMessageID.removeValue(forKey: target.assistantMessageId)
    target.onFinalized?(accepted)
    return accepted
  }

  // MARK: - Pending Attachments

  /// Stage attachments and atomically materialize them into app-managed local storage.
  func addAttachments(_ attachments: [ChatAttachment]) {
    let room = max(0, kMaxChatAttachments - pendingAttachments.count)
    guard room > 0 else {
      errorMessage = "You can only attach up to \(kMaxChatAttachments) files."
      return
    }
    let toAdd = Array(attachments.prefix(room))
    guard let ownerID = runtimeOwnerId else {
      errorMessage = "Sign in again to attach files."
      return
    }
    let targetKey = activeDraftKey
    let chatID = mainChatSurfaceReference().externalRefId
    pendingAttachments.append(contentsOf: toAdd)
    for attachment in toAdd {
      let scope = PendingAttachmentScope(ownerID: ownerID, chatID: chatID)
      pendingAttachmentScopes[attachment.id] = scope
      materializeAttachment(id: attachment.id, targetKey: targetKey, scope: scope)
    }
  }

  func removePendingAttachment(id: String) {
    guard !attachmentsAwaitingJournalAdmission.contains(id) else { return }
    let discardedURL = pendingAttachments.first(where: { $0.id == id })?.localFileURL
    let scope = pendingAttachmentScopes.removeValue(forKey: id)
    pendingAttachments.removeAll { $0.id == id }
    guard let discardedURL, let scope else { return }
    Task {
      do {
        try await LocalChatAttachmentStore.shared.discardManagedFiles(
          [discardedURL],
          ownerID: scope.ownerID,
          chatID: scope.chatID
        )
      } catch {
        logError("ChatProvider: failed to discard staged attachment", error: error)
      }
    }
  }

  private func materializeAttachment(
    id: String,
    targetKey: ChatDraftKey,
    scope: PendingAttachmentScope
  ) {
    Task { [weak self] in
      guard let self = self,
        let attachment = await MainActor.run(body: {
          self.pendingAttachmentsByDraftKey[targetKey]?.first(where: { $0.id == id })
        })
      else { return }
      do {
        let managed = try await LocalChatAttachmentStore.shared.materialize(
          attachment,
          ownerID: scope.ownerID,
          chatID: scope.chatID
        )
        let retained = await MainActor.run {
          guard var staged = self.pendingAttachmentsByDraftKey[targetKey],
            let index = staged.firstIndex(where: { $0.id == id })
          else { return false }
          staged[index] = managed
          self.pendingAttachmentsByDraftKey[targetKey] = staged
          ChatDraftStore.shared.setAttachments(staged, for: targetKey)
          if self.activeDraftKey == targetKey {
            self.isRestoringPendingAttachments = true
            self.pendingAttachments = staged
            self.isRestoringPendingAttachments = false
          }
          return true
        }
        if let fileURL = managed.localFileURL {
          if retained {
            await LocalChatAttachmentStore.shared.releaseMaterializationProtection([fileURL])
          } else {
            try await LocalChatAttachmentStore.shared.discardManagedFiles(
              [fileURL],
              ownerID: scope.ownerID,
              chatID: scope.chatID
            )
          }
        }
      } catch {
        logError("ChatProvider: local attachment materialization failed", error: error)
        await MainActor.run {
          self.setAttachmentState(
            id: id,
            targetKey: targetKey,
            state: .failed(error.localizedDescription)
          )
        }
      }
    }
  }

  private func setAttachmentState(
    id: String,
    targetKey: ChatDraftKey,
    state: ChatAttachment.State
  ) {
    guard var staged = pendingAttachmentsByDraftKey[targetKey],
      let index = staged.firstIndex(where: { $0.id == id })
    else { return }
    staged[index].state = state
    pendingAttachmentsByDraftKey[targetKey] = staged
    ChatDraftStore.shared.setAttachments(staged, for: targetKey)
    if activeDraftKey == targetKey {
      isRestoringPendingAttachments = true
      pendingAttachments = staged
      isRestoringPendingAttachments = false
    }
  }

  /// Block until the exact submitted chat's local copies settle. A chat switch
  /// cannot retarget or consume another draft's attachments.
  private func awaitPendingAttachmentMaterialization(
    targetKey: ChatDraftKey,
    attachmentIDs: Set<String>
  ) async -> [ChatAttachment]? {
    let timeoutNs: UInt64 = 10 * 1_000_000_000
    let start = DispatchTime.now().uptimeNanoseconds
    while true {
      let staged = (pendingAttachmentsByDraftKey[targetKey] ?? []).filter {
        attachmentIDs.contains($0.id)
      }
      guard staged.count == attachmentIDs.count else { return nil }
      let isUploading = staged.contains { attachment in
        if case .uploading = attachment.state { return true }
        return false
      }
      if !isUploading {
        return staged.contains(where: {
          if case .failed = $0.state { return true }
          return false
        }) ? nil : staged
      }
      if DispatchTime.now().uptimeNanoseconds - start > timeoutNs {
        errorMessage = "Attachment copy timed out."
        return nil
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  nonisolated static func attachmentContextPrompt(for attachments: [ChatAttachment]) -> String? {
    guard !attachments.isEmpty else { return nil }
    let plural = attachments.count == 1 ? "file" : "files"
    var lines: [String] = [
      "[Attached Files]",
      "The user attached \(attachments.count) \(plural) to this exact message. Treat references like \"this\", \"the file\", \"the attachment\", or \"what do you think of this\" as referring to these attachment(s). If the answer depends on file contents, inspect the local_path with file-reading tools before asking for clarification.",
    ]
    for (index, attachment) in attachments.enumerated() {
      lines.append("")
      lines.append("\(index + 1). \(attachment.fileName)")
      lines.append("   mime_type: \(attachment.mimeType)")
      if let localFileURL = attachment.localFileURL {
        lines.append("   local_path: \(localFileURL.path)")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localFileURL.path),
          let size = attrs[.size] as? NSNumber
        {
          lines.append(
            "   size: \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))"
          )
        }
      } else {
        lines.append("   local_path: unavailable")
      }
      if attachment.isImage {
        lines.append("   image_payload: included separately when available")
      }
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Send Message

  /// Send typed input through A using the logical conversation prompt receipt.
  /// Journals both the user turn and accepted assistant turn locally.
  /// - Parameters:
  ///   - text: The message text
  @discardableResult
  func sendMessage(
    _ text: String,
    systemPromptSuffix: String? = nil,
    systemPromptPrefix: String? = nil,
    systemPromptStyle: ChatSystemPromptStyle = .main,
    surfaceRef: AgentSurfaceReference? = nil,
    imageData: Data? = nil,
    turnOwner: ChatTurnOwner = .mainChat,
    clientTurnId: String = UUID().uuidString,
    onAccepted: (@MainActor () -> Void)? = nil,
    onJournalFinalized: (@MainActor (_ accepted: Bool) -> Void)? = nil
  ) async -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 12_000 else { return nil }
    guard !isClearing, !isLoading, !isCreatingSession, deletingSessionIds.isEmpty else {
      errorMessage = "Wait for this chat to finish opening or updating before sending."
      return nil
    }
    guard !isSending, !sendLockOwnership.isHeld,
      let authorization = authorizeTurn(for: runtimeOwnerId)
    else { return nil }
    let surface = querySurface(
      surfaceRef: surfaceRef, sessionId: currentSession?.id,
      systemPromptStyle: systemPromptStyle)
    let voice = ConversationVoiceController.shared
    let joinsVoice = voice.acceptsTypedInput(surface: surface)
    if voice.isOpen && !joinsVoice { voice.close() }
    sendGeneration += 1
    let generation = sendGeneration
    guard sendLockOwnership.acquire(generation: generation) else { return nil }
    isSending = true
    isStopping = false
    activeTurnOwner = turnOwner
    activeSendChatID = surface.externalRefId
    errorMessage = nil
    currentError = nil
    lastFailedPrompt = text
    let telemetry = ChatQueryTelemetryAttempt(
      attemptId: clientTurnId,
      surface: surface.surfaceKind, harness: "conversation", runtimeSurface: surface.surfaceKind,
      inputLength: text.count, attachmentCount: pendingAttachments.count,
      hasImage: imageData != nil || pendingAttachments.contains(where: \.isImage))
    activeChatTelemetryAttempt = (generation, telemetry)
    defer {
      if !telemetry.isTerminal {
        telemetry.cancel(reason: .superseded, partialResponse: !activeConversationText.isEmpty)
      }
      clearChatTelemetryState(for: generation)
      if sendGeneration == generation { activeConversationRequest = nil }
      _ = releaseSendLock(sendGeneration: generation)
    }
    if !joinsVoice {
      guard
        voice.beginTextOnlyTurn(
          turnID: clientTurnId, authorizationSnapshot: authorization,
          cancel: { [weak self] in
            guard let self, self.sendGeneration == generation else { return }
            _ = self.stopAgent(owner: turnOwner)
            voice.observeTextOnlyTurn(
              turnID: clientTurnId, userText: text,
              assistantText: self.activeConversationText, outcome: "interrupted", isFinal: true)
            voice.finishTextOnlyTurn(turnID: clientTurnId)
          })
      else { return nil }
    }
    if !joinsVoice {
      activeDirectConversation = (clientTurnId, text, generation)
      AIEvaluationReporter.shared.captureTurnStart(
        turnID: "chat:\(clientTurnId)",
        authorizationSnapshot: authorization)
    }
    defer {
      if !joinsVoice {
        voice.finishTextOnlyTurn(turnID: clientTurnId)
        AIEvaluationReporter.shared.discardTurnAdmission(turnID: "chat:\(clientTurnId)")
      }
      if activeDirectConversation?.generation == generation { activeDirectConversation = nil }
    }
    activeConversationText = ""
    let submittedDraftKey = activeDraftKey
    let attachmentIDs = Set((turnOwner == .mainChat && surfaceRef == nil ? pendingAttachments : []).map(\.id))
    do {
      let attachments: [ChatAttachment]
      if attachmentIDs.isEmpty {
        attachments = []
      } else {
        guard
          let materialized = await awaitPendingAttachmentMaterialization(
            targetKey: submittedDraftKey, attachmentIDs: attachmentIDs)
        else { throw ConversationJournalError.unavailable }
        attachments = materialized
      }
      guard sendGeneration == generation,
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
      else { return nil }
      if joinsVoice {
        let result = try await voice.submitTypedMessage(
          text: text, clientTurnID: clientTurnId,
          image: try Self.conversationImage(imageData ?? attachments.first(where: \.isImage)?.data),
          attachments: attachments,
          onJournalFinalized: { accepted in onJournalFinalized?(accepted) },
          onAccepted: { [weak self] in
            guard let self, self.sendGeneration == generation,
              RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
            else { return }
            self.consumeSubmittedAttachments(attachments, key: submittedDraftKey)
            onAccepted?()
          }, onTextDelta: { _ in })
        if let result {
          telemetry.complete(metrics: Self.conversationCompletionMetrics(responseLength: result.count))
        } else {
          telemetry.finish(error: CancellationError(), partialResponse: false)
        }
        return result
      }
      let journal = try await snapshotConversationJournal(surface: surface)
      let binding = try await pinnedConversation(context: journal)
      voice.bindTextOnlyConversation(turnID: clientTurnId, conversationID: binding.id)
      let savedContext = await conversationContextText(authorizationSnapshot: authorization)
      guard sendGeneration == generation,
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
      else { return nil }
      let image = try Self.conversationImage(imageData ?? attachments.first(where: \.isImage)?.data)
      let ids = Self.messageIds(forAttemptId: clientTurnId)
      let user = ChatMessage(
        id: ids.user, clientTurnId: clientTurnId, text: text,
        sender: .user, attachments: attachments, turnOwner: turnOwner)
      let assistant = ChatMessage(
        id: ids.assistant, clientTurnId: clientTurnId, text: "",
        sender: .ai, isStreaming: true, turnOwner: turnOwner)
      attachmentsAwaitingJournalAdmission.formUnion(attachmentIDs)
      let accepted = await recordStreamingJournalExchange(
        surface: surface, ownerID: authorization.ownerID, continuityKey: clientTurnId,
        userMessage: user, assistantMessage: assistant, origin: "typed_chat",
        sessionId: surface.externalRefId, messageSource: "typed_chat",
        authorizationSnapshot: authorization, expectedGeneration: journal.generation)
      attachmentsAwaitingJournalAdmission.subtract(attachmentIDs)
      guard accepted else { throw ConversationJournalError.writeRejected }
      journalOwnerByMessageID[ids.assistant] = authorization.ownerID
      journalTerminalTargets.register(
        ChatJournalTerminalTarget(
          surface: surface,
          assistantMessageId: ids.assistant, ownerID: authorization.ownerID,
          onFinalized: onJournalFinalized), generation: generation)
      guard sendGeneration == generation,
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
      else {
        _ = await finishJournalTarget(generation: generation, status: .failed)
        return nil
      }
      consumeSubmittedAttachments(attachments, key: submittedDraftKey)
      localSendToken = LocalSendToken(generation: generation)
      onAccepted?()
      voice.observeTextOnlyTurn(turnID: clientTurnId, userText: text, assistantText: "", outcome: "partial")
      let guidance = voice.takeTextOnlyGuidance(turnID: clientTurnId)
      let request = ConversationResponseRequest(
        conversationID: binding.id, turnID: clientTurnId,
        promptReference: binding.prompt.reference, history: journal.history,
        message: text, context: savedContext,
        guidance: guidance.map { String(($0.note + "\n" + $0.context).prefix(2_000)) }, image: image)
      let task = Task {
        try await APIClient.shared.respondToConversation(
          request: request,
          authorizationSnapshot: authorization
        ) { [weak self] delta in
          guard let self, self.sendGeneration == generation,
            RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
          else { return }
          self.appendToMessage(id: ids.assistant, text: delta)
          self.activeConversationText += delta
          voice.observeTextOnlyTurn(
            turnID: clientTurnId, userText: text,
            assistantText: self.activeConversationText, outcome: "partial")
        }
      }
      activeConversationRequest = task
      let completion = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard sendGeneration == generation,
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
      else { return nil }
      streamingBuffer.cancelPendingFlush()
      flushStreamingBuffer()
      let result = messages.first(where: { $0.id == ids.assistant })?.text
      if let index = messages.firstIndex(where: { $0.id == ids.assistant }) {
        messages[index].isStreaming = false
        messages[index].metadata = MessageMetadata(
          model: completion.modelVersion,
          inputTokens: completion.usage?.inputTokens, outputTokens: completion.usage?.outputTokens,
          cacheReadTokens: completion.usage?.cachedInputTokens, hasScreenshot: image != nil,
          toolNames: [], sqlRowsReturned: 0, sqlQueryCount: 0)
      }
      let visibleCompletionUptime = ProcessInfo.processInfo.systemUptime
      telemetry.complete(metrics: Self.conversationCompletionMetrics(responseLength: result?.count ?? 0))
      guard await finishJournalTarget(generation: generation, status: .completed) else {
        throw ConversationJournalError.writeRejected
      }
      voice.observeTextOnlyTurn(
        turnID: clientTurnId, userText: text,
        assistantText: result ?? "", outcome: "completed", isFinal: true)
      AIEvaluationReporter.shared.recordChatTerminal(
        turnID: clientTurnId, requestID: clientTurnId,
        authorizationSnapshot: authorization, userText: text, assistantText: result ?? "",
        endedAt: visibleCompletionUptime)
      if completion.endConversation {
        endPinnedConversation(id: binding.id)
        voice.finishTextOnlyTurn(turnID: clientTurnId, conversationEnded: true)
      }
      lastFailedPrompt = nil
      if let result {
        await catalogDidAcceptFirstCompletedExchange(
          chatID: surface.externalRefId,
          ownerID: authorization.ownerID, userText: text, assistantText: result)
      }
      return result
    } catch {
      guard sendGeneration == generation,
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
      else { return nil }
      streamingBuffer.cancelPendingFlush()
      flushStreamingBuffer()
      telemetry.finish(error: error, partialResponse: !activeConversationText.isEmpty)
      _ = await finishJournalTarget(generation: generation, status: .failed)
      voice.observeTextOnlyTurn(
        turnID: clientTurnId, userText: text,
        assistantText: activeConversationText, outcome: "failed", isFinal: true)
      errorMessage = error is CancellationError ? nil : "Could not complete this reply. Try again."
      return nil
    }
  }

  private static func conversationCompletionMetrics(responseLength: Int) -> ChatQueryCompletionMetrics {
    ChatQueryCompletionMetrics(
      toolCallCount: 0, toolNames: [], costUsd: 0,
      responseLength: responseLength, screenToolRequested: false, screenToolSucceeded: false,
      screenToolApprovalRequired: false, screenToolFailureCodes: [])
  }

  private func consumeSubmittedAttachments(_ attachments: [ChatAttachment], key: ChatDraftKey) {
    guard !attachments.isEmpty else { return }
    let ids = Set(attachments.map(\.id))
    for attachment in attachments { pendingAttachmentScopes.removeValue(forKey: attachment.id) }
    var remaining = pendingAttachmentsByDraftKey[key] ?? []
    remaining.removeAll { ids.contains($0.id) }
    pendingAttachmentsByDraftKey[key] = remaining
    ChatDraftStore.shared.setAttachments(remaining, for: key)
    if activeDraftKey == key {
      isRestoringPendingAttachments = true
      pendingAttachments = remaining
      isRestoringPendingAttachments = false
    }
  }

  private static func conversationImage(_ data: Data?) throws -> ConversationImage? {
    guard let data else { return nil }
    guard let bitmap = NSBitmapImageRep(data: data),
      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]),
      jpeg.count <= 2_000_000
    else { throw ConversationAPIError.requestTooLarge }
    return ConversationImage(jpegBase64: jpeg.base64EncodedString())
  }

  func presentOnboardingOpener() {
    let name = Self.firstName(AuthService.shared.givenName)
    let baseStarters = HomeSuggestionComposer.compose(
      personalized: HomeSuggestionsStore.shared.personalizedQuestions)

    onboardingOpener = OnboardingOpenerComposer.compose(
      name: name, now: Date(), baseStarters: baseStarters)

  }

  /// Hide the opener once the user sends their first message.
  func dismissOnboardingOpener() {
    onboardingOpener = nil
  }

  private static func firstName(_ full: String) -> String {
    let trimmed = full.trimmingCharacters(in: .whitespaces)
    return trimmed.components(separatedBy: " ").first ?? trimmed
  }

  /// Sends the active main-chat composer and clears only the exact draft that
  /// was accepted into the timeline. Preflight failures leave it untouched,
  /// and typing a new draft while acceptance is pending is never overwritten.
  @discardableResult
  func sendMainDraft(_ text: String) async -> String? {
    let submittedKey = activeDraftKey
    let submittedRevision = draftRevisions[submittedKey, default: 0]
    guard let submittedOwnerID = runtimeOwnerId else { return nil }
    return await sendMessage(
      text,
      onAccepted: { [weak self] in
        self?.clearSubmittedDraftIfUnchanged(
          text,
          key: submittedKey,
          ownerID: submittedOwnerID,
          revision: submittedRevision
        )
      })
  }

  private func clearSubmittedDraftIfUnchanged(
    _ text: String,
    key: ChatDraftKey,
    ownerID: String,
    revision: UInt64
  ) {
    guard draftRevisions[key, default: 0] == revision,
      ChatDraftStore.shared.text(for: key, ownerID: ownerID) == text
    else { return }
    ChatDraftStore.shared.setText("", for: key, ownerID: ownerID)
    if runtimeOwnerId == ownerID, activeDraftKey == key {
      isRestoringDraft = true
      draftText = ""
      isRestoringDraft = false
    }
  }

  @discardableResult
  private func releaseSendLock(sendGeneration generation: Int) -> Bool {
    guard sendLockOwnership.release(generation: generation) else { return false }
    clearSendLockState()
    return true
  }

  private func stopReason(for generation: Int) -> ChatTurnStopReason {
    guard activeStopReason?.generation == generation else { return .userStop }
    return activeStopReason?.reason ?? .userStop
  }

  private func finishActiveChatTelemetry(
    generation: Int,
    stopReason: ChatTurnStopReason,
    partialResponse: Bool
  ) {
    guard let active = activeChatTelemetryAttempt,
      active.generation == generation
    else { return }
    active.attempt.finish(stopReason: stopReason, partialResponse: partialResponse)
    clearChatTelemetryState(for: generation)
  }

  private func clearChatTelemetryState(for generation: Int) {
    if activeChatTelemetryAttempt?.generation == generation {
      activeChatTelemetryAttempt = nil
    }
    if activeStopReason?.generation == generation {
      activeStopReason = nil
    }
    if activeChatTurnLifecycle?.generation == generation {
      activeChatTurnLifecycle = nil
    }
    if activeChatClientTurnId?.generation == generation {
      activeChatClientTurnId = nil
    }
  }

  private func clearSendLockState() {
    assert(!sendLockOwnership.isHeld, "send presentation state cleared while another generation owns the lock")
    let terminalizedMessageIDs = Self.terminalizeOrphanedStreamingMessages(
      &messages,
      hasActiveSendLock: sendLockOwnership.isHeld
    )
    var repairGroups: [String: [String]] = [:]
    for messageID in terminalizedMessageIDs {
      if let ownerID = journalOwnerByMessageID[messageID] ?? runtimeOwnerId {
        repairGroups[ownerID, default: []].append(messageID)
      }
    }
    let repairSurface = mainChatSurfaceReference()
    for (ownerID, messageIDs) in repairGroups {
      Task { @MainActor [weak self] in
        guard let self else { return }
        let repaired = await self.kernelTurnProjection.repairNonterminalTurns(
          surface: repairSurface,
          turnIDs: messageIDs,
          ownerID: ownerID
        )
        if repaired < messageIDs.count {
          log(
            "ChatProvider: canonical orphan repair deferred "
              + "(requested=\(messageIDs.count), repaired=\(repaired))"
          )
        }
      }
    }
    if !terminalizedMessageIDs.isEmpty {
      log("ChatProvider: terminalized \(terminalizedMessageIDs.count) orphaned streaming message(s) after send release")
    }
    isSending = false
    isStopping = false
    activeBridgeSendGeneration = nil
    activeTurnOwner = nil
    activeSendChatID = nil
    if let prompt = pendingErrorRecoveryPrompt {
      pendingErrorRecoveryPrompt = nil
      Task { [weak self] in
        await self?.sendMessage(prompt)
      }
    }
  }

  /// One accepted real pair, regardless of typed or voice origin, may claim an
  /// automatic title only while the local catalog still reports `default`.
  func catalogDidAcceptFirstCompletedExchange(
    chatID: String,
    ownerID: String,
    userText: String,
    assistantText: String
  ) async {
    guard multiChatEnabled,
      chatID != "default",
      runtimeOwnerId == ownerID,
      !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }

    await generateSessionTitle(
      sessionId: chatID,
      userText: userText,
      assistantText: assistantText
    )
  }

  /// Generate a title for the session using LLM
  private func generateSessionTitle(
    sessionId: String,
    userText: String,
    assistantText: String
  ) async {
    guard let ownerID = runtimeOwnerId else { return }
    let ownerLease = captureCatalogOwnerLease()

    do {
      let response: GenerateTitleResponse
      #if DEBUG
        if let generateTitleForTests {
          response = try await generateTitleForTests(userText, assistantText, ownerID)
        } else {
          response = try await APIClient.shared.generateSessionTitle(
            userText: userText,
            assistantText: assistantText,
            expectedOwnerId: ownerID
          )
        }
      #else
        response = try await APIClient.shared.generateSessionTitle(
          userText: userText,
          assistantText: assistantText,
          expectedOwnerId: ownerID
        )
      #endif
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      let title = Self.normalizedAutomaticTitle(response.title)
      let updated = try await updateLocalChatCatalog(
        chatID: sessionId,
        title: title,
        titleOrigin: .automatic,
        expectedTitleOrigin: .defaultTitle
      ).chatSession

      // Update session in list
      if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
        sessions[index] = updated
      }

      // Update current session
      if currentSession?.id == sessionId {
        currentSession = updated
      }

      log("Generated session title (\(updated.title.count) chars)")
      AnalyticsManager.shared.sessionTitleGenerated()
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      logError("Failed to generate session title", error: error)
      // Non-fatal - session continues with default title
    }
  }

  static func normalizedAutomaticTitle(_ title: String) -> String {
    let words = title.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
    let normalized = words.prefix(6).joined(separator: " ")
    return normalized.isEmpty ? "New Chat" : normalized
  }

  /// Update message text (replaces entire text)
  private func updateMessage(id: String, text: String) {
    if let index = messages.firstIndex(where: { $0.id == id }) {
      if messages[index].sender == .ai {
        messages[index].text = Self.normalizeAssistantSentenceSpacing(text)
      } else {
        messages[index].text = text
      }
    }
  }

  /// Normalize missing spaces after sentence punctuation in assistant messages.
  /// Example: "Hello.World" -> "Hello. World", "Great!Lets go" -> "Great! Lets go"
  ///
  /// Code spans are preserved verbatim so identifiers, file paths, and method
  /// chains like `pd.DataFrame`, `System.IO`, or `foo.Bar()` are never mangled
  /// into `pd. DataFrame`. Both fenced code blocks (``` / ~~~) and inline
  /// backtick spans are skipped. Applied on every streaming flush, so it must
  /// treat an unterminated span (fence or backtick still open mid-stream) as
  /// code to avoid corrupting code that is still arriving.
  static func normalizeAssistantSentenceSpacing(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    var output: [String] = []
    output.reserveCapacity(lines.count)
    var inFencedBlock = false

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        inFencedBlock.toggle()
        output.append(line)  // fence marker line, verbatim
      } else if inFencedBlock {
        output.append(line)  // code content, verbatim
      } else {
        output.append(normalizeInlinePreservingCode(line))
      }
    }

    return output.joined(separator: "\n")
  }

  /// Apply sentence-spacing normalization to a single line, leaving inline
  /// backtick code spans untouched. An odd number of backticks (an unterminated
  /// span) leaves its trailing content treated as code.
  private static func normalizeInlinePreservingCode(_ line: String) -> String {
    guard line.contains("`") else { return applySentenceSpacing(line) }

    let parts = line.split(separator: "`", omittingEmptySubsequences: false)
    let normalizedParts = parts.enumerated().map { index, part -> String in
      // Even segments are outside inline code; odd segments are inside.
      index.isMultiple(of: 2) ? applySentenceSpacing(String(part)) : String(part)
    }
    return normalizedParts.joined(separator: "`")
  }

  private static func applySentenceSpacing(_ text: String) -> String {
    var normalized = text

    if let punctuationUpper = try? NSRegularExpression(pattern: #"([.!?])(?=[A-Z])"#) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = punctuationUpper.stringByReplacingMatches(
        in: normalized, options: [], range: range, withTemplate: "$1 ")
    }

    if let punctuationQuotedUpper = try? NSRegularExpression(pattern: #"([.!?])(?=[\"“'‘][A-Z])"#) {
      let range = NSRange(normalized.startIndex..., in: normalized)
      normalized = punctuationQuotedUpper.stringByReplacingMatches(
        in: normalized, options: [], range: range, withTemplate: "$1 ")
    }

    return normalized
  }

  /// Append text to a streaming message via a buffer that flushes at ~100ms intervals.
  /// This reduces SwiftUI re-renders from once-per-token to ~10 times/second.
  private func appendToMessage(id: String, text: String) {
    streamingBuffer.appendText(messageId: id, text: text) { [weak self] in
      self?.flushStreamingBuffer()
    }
  }

  /// Flush accumulated text and thinking deltas to the published messages array.
  private func flushStreamingBuffer() {
    streamingBuffer.flush(messages: &messages) { message, text in
      if message.sender == .ai {
        return Self.normalizeAssistantSentenceSpacing(text)
      }
      return text
    }
    for message in messages where message.isStreaming {
      scheduleJournalUpdate(messageId: message.id, status: .streaming)
    }
  }

  /// Add a tool call indicator to a streaming message
  /// Append a discovery card block to the last AI message in the chat
  func appendDiscoveryCard(title: String, summary: String, fullText: String) {
    guard let index = messages.lastIndex(where: { $0.sender == .ai }) else { return }
    messages[index].contentBlocks.append(
      .discoveryCard(id: UUID().uuidString, title: title, summary: summary, fullText: fullText)
    )
    scheduleJournalUpdate(messageId: messages[index].id)
  }

  func recoverFromError() async {
    guard let error = currentError else { return }
    let action = error.primaryRecovery
    let promptToRetry = lastFailedPrompt
    currentError = nil
    lastFailedPrompt = nil

    switch action {
    case .retry:
      if let prompt = promptToRetry, !prompt.isEmpty {
        if isSending {
          if isStopping {
            pendingErrorRecoveryPrompt = prompt
            return
          }
          currentError = error
          lastFailedPrompt = prompt
          return
        }
        await sendMessage(prompt)
      }
    case .dismiss:
      break  // already cleared above
    case .signIn:
      log("ChatErrorCard: .signIn recovery — starting desktop OAuth")
      do {
        try await AuthService.shared.signInWithGoogle()
      } catch AuthError.cancelled {
        // User explicitly cancelled — don't auto-pivot to a different provider.
        log("ChatErrorCard: Google sign-in cancelled by user — not retrying with Apple")
        currentError = error
        lastFailedPrompt = promptToRetry
        errorMessage = nil
        return
      } catch let googleError {
        // Google unavailable/misconfigured — try Apple as fallback provider.
        log("ChatErrorCard: Google sign-in unavailable, trying Apple — \(googleError.localizedDescription)")
        do {
          try await AuthService.shared.signInWithApple()
        } catch let signInError {
          logError("ChatErrorCard: sign-in recovery failed", error: signInError)
          currentError = error
          errorMessage = signInError.localizedDescription
          return
        }
      }
      _ = try? await AuthService.shared.getIdToken(forceRefresh: true)
      _ = await ensureBridgeStarted()
      if let prompt = promptToRetry, !prompt.isEmpty {
        await sendMessage(prompt)
      }
    case .installRuntime:
      log("ChatErrorCard: .installRuntime recovery — opening nodejs.org for runtime install")
      if let url = URL(string: "https://nodejs.org/") {
        NSWorkspace.shared.open(url)
      }
    }
  }

  /// User tapped the dismiss "x" on a `ChatErrorCard`. Clears the
  /// card without firing any recovery action. Used when the user
  /// wants to acknowledge the error and move on without retrying.
  func dismissCurrentError() {
    currentError = nil
    lastFailedPrompt = nil
  }

  // MARK: - Session Grouping Helpers

  /// Group sessions by date — called by the Combine observer, not on every SwiftUI render pass.
  private func computeGroupedSessions() -> [(String, [ChatSession])] {
    let calendar = Calendar.current
    let now = Date()

    var today: [ChatSession] = []
    var yesterday: [ChatSession] = []
    var thisWeek: [ChatSession] = []
    var older: [ChatSession] = []

    for session in filteredSessions {
      if calendar.isDateInToday(session.updatedAt) {
        today.append(session)
      } else if calendar.isDateInYesterday(session.updatedAt) {
        yesterday.append(session)
      } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
        session.updatedAt > weekAgo
      {
        thisWeek.append(session)
      } else {
        older.append(session)
      }
    }

    var groups: [(String, [ChatSession])] = []
    if !today.isEmpty { groups.append(("Today", today)) }
    if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
    if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
    if !older.isEmpty { groups.append(("Older", older)) }

    return groups
  }

  // MARK: - Local automation (continuity gauntlet)

  /// Test-bundle-only owner swap: clear kernel state for owner A, apply a synthetic
  /// owner-B override (without rewriting Firebase `auth_userId` / tokens), and run
  /// one main-chat probe turn under a QueryTracer context.
  func automationSwapTestOwner(ownerBId: String, probeQuery: String) async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "swap_test_owner is disabled on production bundles"]
    }
    let trimmedOwnerB = ownerBId.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedQuery = probeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOwnerB.isEmpty else { return ["error": "missing 'owner_b'"] }
    guard !trimmedQuery.isEmpty else { return ["error": "missing 'query'"] }
    // Real Firebase uid — never the automation override — so we refuse swapping
    // when the session is not actually signed in.
    guard
      let ownerA = UserDefaults.standard.string(forKey: .authUserId)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !ownerA.isEmpty
    else {
      return ["error": "owner A is not signed in"]
    }
    guard trimmedOwnerB != ownerA else {
      return ["error": "owner_b must differ from the active owner"]
    }

    await RuntimeOwnerIdentity.applyAutomationOwnerOverride(trimmedOwnerB)
    resetSessionStateForAuthChange()

    guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: trimmedOwnerB)
    else { return ["error": "owner B authorization is unavailable"] }
    do {
      let surface = mainChatSurfaceReference()
      let bridge = AgentClient.makeBridge()
      let range = try await bridge.listJournalTurns(surface: surface, limit: 1, authorizationSnapshot: authorization)
      let key = UUID().uuidString
      let now = Int(Date().timeIntervalSince1970 * 1000)
      let writes = [("user", trimmedQuery), ("assistant", "PROBE")].enumerated().map { index, entry in
        KernelJournalTurnWrite(
          turnId: KernelTurnProjection.stableTurnID(continuityKey: key, role: entry.0),
          role: entry.0, origin: "typed_chat", status: .completed, content: entry.1,
          contentBlocksJSON: "[]", resourcesJSON: "[]", metadataJSON: "{}", createdAtMs: now + index)
      }
      let receipt = try await bridge.recordJournalExchange(
        surface: surface, ownerID: trimmedOwnerB,
        turns: writes, authorizationSnapshot: authorization, expectedGeneration: range.conversationGeneration)
      projectJournalTurns(receipt.turns)
      var detail = automationMainChatSnapshot(limit: 20)
      detail["owner_a"] = ownerA
      detail["owner_b"] = trimmedOwnerB
      detail["conversation_id"] = receipt.conversationId
      return detail
    } catch { return ["error": "owner isolation journal probe failed"] }
  }

  /// Undo automationSwapTestOwner: clear the owner override (and heal a legacy
  /// synthetic auth_userId if an older build left one). Safe no-op when no swap
  /// is active. Harnesses must call this after the owner suite (and may call it
  /// defensively pre-run).
  func automationRestoreTestOwner() async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "restore_test_owner is disabled on production bundles"]
    }
    let defaults = UserDefaults.standard
    let hadSwap =
      (defaults.string(forKey: .automationOwnerOverride)?.isEmpty == false)
      || (defaults.string(forKey: .automationOwnerABackup)?.isEmpty == false)
    guard hadSwap else {
      return ["restored": "false", "note": "no owner swap active"]
    }

    let result = await RuntimeOwnerIdentity.clearAutomationOwnerOverride()
    resetSessionStateForAuthChange()
    return [
      "restored": result.restored ? "true" : "false",
      "owner_id": result.ownerId ?? "",
      "auth_user_id": defaults.string(forKey: .authUserId) ?? "",
    ]
  }

  /// Snapshot for main-chat harness actions.
  func automationMainChatSnapshot(limit: Int) -> [String: String] {
    automationChatSnapshot(limit: limit)
  }

  /// Floating-bar snapshot over the same canonical timeline.
  func automationFloatingChatSnapshot(limit: Int) -> [String: String] {
    automationChatSnapshot(limit: limit)
  }

  private func automationChatSnapshot(limit: Int) -> [String: String] {
    let boundedLimit = max(1, limit)
    let runtimeChatId = mainChatRuntimeChatId(sessionId: currentSessionId)
    let rows: [[String: String]] = messages.suffix(boundedLimit).map { message in
      [
        "id": message.id,
        "role": message.sender == .user ? "user" : "assistant",
        "text": message.copyableText,
        "raw_text": message.text,
        "streaming": message.isStreaming ? "true" : "false",
        "content_blocks_json": ChatContentBlockCodec.encode(message.contentBlocks) ?? "[]",
        "resources_json": ChatResource.encodeResourcesForPersistence(message.displayResources) ?? "[]",
      ]
    }
    let messagesJSON: String
    if let data = try? JSONSerialization.data(withJSONObject: rows),
      let encoded = String(data: data, encoding: .utf8)
    {
      messagesJSON = encoded
    } else {
      messagesJSON = "[]"
    }
    var detail: [String: String] = [
      "chat_session_id": currentSessionId ?? "",
      "runtime_chat_id": runtimeChatId,
      "is_loading": isLoading ? "true" : "false",
      "is_loading_sessions": isLoadingSessions ? "true" : "false",
      "is_sending": isSending ? "true" : "false",
      "is_streaming": messages.contains(where: { $0.isStreaming }) ? "true" : "false",
      "message_count": "\(messages.count)",
      "messages_json": messagesJSON,
    ]
    if let lastAssistant = messages.last(where: { $0.sender != .user })?.copyableText {
      detail["last_assistant_text"] = lastAssistant
    }
    if let ownerId = runtimeOwnerId {
      detail["owner_id"] = ownerId
    }
    let hasStructuredError = currentError != nil
    let hasLegacyError = !(errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    detail["has_error"] = (hasStructuredError || hasLegacyError) ? "true" : "false"
    if let errorMessage, !errorMessage.isEmpty {
      detail["error_message"] = errorMessage
    }
    if let currentError {
      detail["current_error"] = String(describing: currentError)
    }
    return detail
  }

  /// Clear kernel `main_chat` turns for the active owner (continuity harness hygiene).
  func automationClearOwnerSurfaceState(chatId: String = "default") async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "clear_owner_surface_state is disabled on production bundles"]
    }
    return await clearOwnerSurfaceStateForAuthorizedHarness(chatId: chatId)
  }

  /// Performs the owner-scoped control clear after a non-production automation
  /// entrypoint has established eligibility.
  func clearOwnerSurfaceStateForAuthorizedHarness(chatId: String = "default") async -> [String: String] {
    kernelTurnProjection.attachControlClient(resolvedAgentClient())
    guard await kernelTurnProjection.clearOwnerSurfaceState(chatId: chatId) else {
      return ["error": "kernel owner surface clear failed", "chat_id": chatId]
    }
    return ["cleared": "true", "chat_id": chatId]
  }

  /// Read-only kernel `main_chat` turn tail for continuity harness evidence.
  func automationKernelTurnTail(limit: Int = 8) async -> [String: String] {
    let boundedLimit = max(1, min(limit, 100))
    let surface = mainChatSurfaceReference()
    guard await ensureBridgeStartedForKernel(),
      let tail = await kernelTurnProjection.fetchJournalTurnTail(
        surface: surface,
        limit: boundedLimit
      )
    else {
      return ["error": "kernel turn tail unavailable"]
    }
    let rows: [[String: String]] = tail.turns.map { turn in
      [
        "role": turn.role,
        "content": turn.content,
        "origin": turn.origin,
        "turn_seq": "\(turn.turnSeq)",
      ]
    }
    let turnsJSON: String
    if let data = try? JSONSerialization.data(withJSONObject: rows),
      let encoded = String(data: data, encoding: .utf8)
    {
      turnsJSON = encoded
    } else {
      turnsJSON = "[]"
    }
    return [
      "conversation_id": tail.conversationId,
      "turn_count": "\(tail.turns.count)",
      "turns_json": turnsJSON,
    ]
  }
}
