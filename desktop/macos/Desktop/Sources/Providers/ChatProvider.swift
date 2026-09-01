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
    return "omi.chat.selected.v1.\(ownerHash)"
  }
}

struct OwnerIsolationKernelProbeReceipt: Equatable {
  let ownerID: String
  let conversationID: String
  let sessionID: String
  let turns: [KernelJournalTurn]
}

/// Non-production owner-isolation probes need kernel ownership evidence even
/// when their synthetic owner intentionally has no Firebase credential. This
/// seam admits only an owner handshake, one canonical surface mapping, and one
/// journal exchange; it never opens a managed-model execution lane.
@MainActor
enum OwnerIsolationKernelProbe {
  static func run(
    ownerID: String,
    query: String,
    response: String,
    registerControlOnlyRuntime: @MainActor () async throws -> Void,
    synchronizeOwner: @MainActor () async -> Bool,
    resolveSurface: @MainActor () async throws -> (conversationID: String, sessionID: String),
    recordExchange: @MainActor ([KernelJournalTurnWrite]) async throws -> [KernelJournalTurn]
  ) async throws -> OwnerIsolationKernelProbeReceipt {
    try await registerControlOnlyRuntime()
    guard await synchronizeOwner() else { throw BridgeError.authMissing }
    let surface = try await resolveSurface()
    let now = Int(Date().timeIntervalSince1970 * 1000)
    let continuityID = UUID().uuidString
    let turns = [
      KernelJournalTurnWrite(
        turnId: continuityID,
        role: "user",
        origin: "typed_chat",
        status: .completed,
        content: query,
        contentBlocksJSON: "[]",
        resourcesJSON: "[]",
        metadataJSON: #"{"harness":"owner_isolation_probe"}"#,
        createdAtMs: now
      ),
      KernelJournalTurnWrite(
        turnId: "\(continuityID)-assistant",
        role: "assistant",
        origin: "typed_chat",
        status: .completed,
        content: response,
        contentBlocksJSON: "[]",
        resourcesJSON: "[]",
        metadataJSON: #"{"harness":"owner_isolation_probe"}"#,
        createdAtMs: now
      ),
    ]
    let recorded = try await recordExchange(turns)
    return OwnerIsolationKernelProbeReceipt(
      ownerID: ownerID,
      conversationID: surface.conversationID,
      sessionID: surface.sessionID,
      turns: recorded
    )
  }
}

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
    // Strip MCP prefix (e.g., "mcp__omi-tools__execute_sql" → "execute_sql")
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
struct ChatMessage: Identifiable {
  var id: String  // Mutable while a provisional UI turn becomes a durable journal turn.
  let clientTurnId: String?
  var text: String
  let createdAt: Date
  let sender: ChatSender
  var isStreaming: Bool
  /// Whether the message has been accepted by the local journal authority.
  var isSynced: Bool
  /// Citations extracted from the AI response
  var citations: [Citation]
  /// Structured content blocks for AI messages (text interspersed with tool calls)
  var contentBlocks: [ChatContentBlock]
  /// Metadata about context used to generate this response (AI messages only)
  var metadata: MessageMetadata?
  /// Context text for proactive notification messages (not shown to user, sent to Gemini)
  var notificationContext: String?
  /// Screenshot JPEG data captured when a proactive notification was generated
  var notificationScreenshot: Data?
  /// User-attached files (screenshots, images, documents) — populated for user messages.
  var attachments: [ChatAttachment]
  /// Surface-neutral resources associated with this message. Assistant messages
  /// use this for generated artifacts; user messages derive resources from
  /// `attachments` for backwards compatibility.
  var resources: [ChatResource]

  /// Which surface produced this turn. This is only an ownership label for
  /// interruption/cancellation policy; chat history is canonical and renders
  /// every Omi turn in every full chat timeline.
  var turnOwner: ChatTurnOwner?

  /// Kernel journal lifecycle when this message was projected from a journal
  /// row. Failed turns get a light visual treatment so they don't look completed.
  var journalStatus: KernelJournalTurnStatus?

  init(
    id: String = UUID().uuidString, clientTurnId: String? = nil, text: String, createdAt: Date = Date(),
    sender: ChatSender, isStreaming: Bool = false, isSynced: Bool = false,
    citations: [Citation] = [], contentBlocks: [ChatContentBlock] = [], metadata: MessageMetadata? = nil,
    notificationContext: String? = nil, notificationScreenshot: Data? = nil, attachments: [ChatAttachment] = [],
    resources: [ChatResource] = [], turnOwner: ChatTurnOwner? = nil, journalStatus: KernelJournalTurnStatus? = nil
  ) {
    self.id = id
    self.turnOwner = turnOwner
    self.clientTurnId = clientTurnId
    self.text = text
    self.createdAt = createdAt
    self.sender = sender
    self.isStreaming = isStreaming
    self.isSynced = isSynced
    self.citations = citations
    self.contentBlocks = contentBlocks
    self.metadata = metadata
    self.notificationContext = notificationContext
    self.notificationScreenshot = notificationScreenshot
    self.attachments = attachments
    self.resources = resources
    self.journalStatus = journalStatus
  }
}

extension ChatMessage {
  var copyableText: String {
    // A completed assistant turn can contain internal reasoning and transient
    // tool/lifecycle blocks alongside its user-visible answer. The message
    // copy affordance promises the answer, so retain only final text blocks.
    let finalOutput =
      contentBlocks
      .compactMap { block -> String? in
        guard case .text(_, let text) = block else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !finalOutput.isEmpty {
      return finalOutput
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var displayResources: [ChatResource] {
    if !resources.isEmpty {
      return resources
    }
    return attachments.map(ChatResource.attachment)
  }
}

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
struct ChatProviderAgentQueryInvocation {
  let prompt: String
  let session: AgentSurfaceSession
  let surface: AgentSurfaceReference
  let mode: String?
  let imageData: Data?
  let attachments: [AgentQueryAttachment]
  let producingTurnId: String?
  let expectedContext: AgentContextFreshness?
  let reasoningEffort: String?
}

/// State management for local-authoritative managed Omi chat.
/// Swift presents the shared timeline while the Node runtime owns accepted turns and catalog metadata.
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

  // MARK: - Floating Bar System Prompt Prefix
  /// Static prefix injected at the top of the system prompt for floating bar sessions.
  /// Defined here so it can be referenced both at warmup time and at query time.
  static let floatingBarSystemPromptPrefix = """
    ================================================================================
    🚨 FLOATING BAR MODE — READ THIS FIRST BEFORE ANYTHING ELSE 🚨
    ================================================================================
    Tool calls are untrusted capability proposals. The kernel owns the authoritative route, clarification decision, authorization, execution profile, and background-agent identity for this surface. Use returned Omi data rather than inventing personal facts, and never claim a proposed action or agent start succeeded before its canonical tool result.
    If a screenshot is attached and the user asks a deictic question like "which one", "which option", "which suits me", "what should I choose", or "what's on my screen", ground the answer in the visible options first and prefer what is actually on screen over unrelated context.
    If the screenshot already clearly shows the relevant options, do not ignore it just because the query is short or ambiguous.
    Respond concisely in 1-2 sentences. No lists. No headers.
    A screenshot may be attached — use it silently only if relevant. Never mention or acknowledge it.
    ================================================================================
    """

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
    var resolveKernelQuerySessionForTests: ((AgentSurfaceReference, String?) async throws -> AgentSurfaceSession)?
    var prepareKernelQueryContextForTests:
      ((AgentSurfaceReference, AgentSurfaceSession?) async throws -> (AgentSurfaceSession, AgentContextSnapshot))?
    var warmupKernelQuerySessionForTests: ((AgentSurfaceSession) async -> Void)?
    var refreshMemoriesForPromptForTests: (() async -> Void)?
    var loadGoalsForTests: (() async throws -> [LocalGoal])?
    var loadTasksForTests: (() async throws -> [TaskActionItem])?
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
    let session = AgentClient.makeSession(harnessMode: AgentHarnessMode.piMono.rawValue)
    agentClient = session
    return session
  }

  /// Single fail-closed admission boundary for query results consumed by
  /// ChatProvider surfaces. Missing, unknown, and non-success terminal states
  /// must never become visible answer text or terminal journal success.
  @discardableResult
  static func requireSuccessfulQueryResult(
    _ result: AgentClient.QueryResult
  ) throws -> AgentClient.QueryResult {
    try result.requireSucceeded()
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
  private var cachedGoals: [LocalGoal] = []
  private var goalsLoaded = false
  private var cachedTasks: [TaskActionItem] = []
  private var tasksLoaded = false
  private var cachedAIProfile: String = ""
  private var aiProfileLoaded = false
  private var cachedDatabaseSchema: String = ""
  private var schemaLoaded = false

  // MARK: - Current Session ID
  var currentSessionId: String? {
    currentSession?.id
  }

  // MARK: - Current Model
  var currentModel: String {
    "Omi"
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
    log("ChatProvider initialized, will start managed Pi on first use")

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

    // Tear down the agent bridge on sign-out. The pi-mono subprocess
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
          AgentRuntimeStatusStore.shared.reset()
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
    guard agentBridgeStarted else { return }
    await resolvedAgentClient().invalidateSurface(surface)
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
    if agentBridgeStarted {
      let alive = await resolvedAgentClient().isAlive
      if alive {
        return true
      }
      log("ChatProvider: agent bridge process died, will restart")
      agentBridgeStarted = false
      await resolvedAgentClient().prepareForCrashRecovery()
    }
    guard !agentBridgeStarted else { return true }
    // Wait for API keys (Firebase, Calendar) before starting the bridge.
    await APIKeyService.shared.waitForKeys()
    await preparePromptContextIfNeeded()
    try await resolvedAgentClient().start()
    // Managed Pi never falls back when its Omi credential is unavailable.
    await resolvedAgentClient().setGlobalAuthHandlers(
      onAuthRequired: { [weak self] _, _ in
        Task { @MainActor [weak self] in
          self?.errorMessage = "Omi authentication is required for managed AI. Sign in, then try again."
        }
      },
      onAuthSuccess: { [weak self] in
        Task { @MainActor [weak self] in
          self?.errorMessage = nil
        }
      }
    )
    await kernelTurnProjection.attachClient(resolvedAgentClient())
    let warmSurfaces: [AgentSurfaceReference] = [.mainChat(chatId: nil), .floatingChat()]
    for surface in warmSurfaces {
      let session = try await resolvedAgentClient().resolveSurfaceSession(surface)
      await resolvedAgentClient().warmupSession(session)
    }
    agentBridgeStarted = true
    log("ChatProvider: agent bridge ready")
    return true
  }

  private func presentBridgeStartupFailure(
    _ error: Error,
    authoritativeGeneration: Int?
  ) async {
    let context = await AgentRuntimeProcess.shared.consumePendingStartFailureDiagnostics()
    logError("Failed to start agent bridge", error: error, context: context)
    let mayMutateSendState = authoritativeGeneration.map { sendGeneration == $0 } ?? true
    guard mayMutateSendState else { return }
    if let bridgeError = error as? BridgeError, let card = ChatErrorState.from(bridgeError) {
      currentError = card
      errorMessage = nil
    } else {
      errorMessage = "AI not available: \(error.localizedDescription)"
    }
  }

  /// Ensures prompt-backed local context is loaded before managed Pi starts.
  private func preparePromptContextIfNeeded() async {
    await warmupPromptContext()
  }

  private func resetSessionStateForAuthChange() {
    // These files are owned by the outgoing account's persisted drafts, not by
    // this in-memory projection. Clearing the projection must not destroy bytes
    // that need to rehydrate if the user switches back to that account.
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
    cachedGoals = []
    goalsLoaded = false
    cachedTasks = []
    tasksLoaded = false
    cachedAIProfile = ""
    aiProfileLoaded = false
    cachedDatabaseSchema = ""
    schemaLoaded = false
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
    return RealtimeHubController.shared.beginChatClearBarrier(surface: surface)
  }

  private func endRealtimeChatClear(surface: AgentSurfaceReference) {
    #if DEBUG
      if let endRealtimeChatClearForTests {
        endRealtimeChatClearForTests(surface)
        return
      }
    #endif
    RealtimeHubController.shared.endChatClearBarrier(surface: surface)
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

  private struct KernelQueryContext {
    let session: AgentSurfaceSession
    let snapshot: AgentContextSnapshot
  }

  private func resolveKernelQuerySession(
    surface: AgentSurfaceReference,
    requestedModelProfile _: String?
  ) async throws -> AgentSurfaceSession {
    #if DEBUG
      if let resolveKernelQuerySessionForTests {
        return try await resolveKernelQuerySessionForTests(surface, nil)
      }
    #endif
    return try await resolvedAgentClient().resolveSurfaceSession(surface)
  }

  private func prepareKernelQueryContext(
    surface: AgentSurfaceReference,
    systemPromptStyle: ChatSystemPromptStyle,
    systemPromptPrefix: String?,
    systemPromptSuffix: String?,
    notificationContext: String?,
    screenPayload: [String: Any]?,
    includeScreenSource: Bool = true,
    requestedModelProfile: String? = nil,
    pinnedSession: AgentSurfaceSession? = nil
  ) async throws -> KernelQueryContext {
    #if DEBUG
      if let prepareKernelQueryContextForTests {
        let context = try await prepareKernelQueryContextForTests(surface, pinnedSession)
        return KernelQueryContext(session: context.0, snapshot: context.1)
      }
    #endif
    let client = resolvedAgentClient()
    let session: AgentSurfaceSession
    if let pinnedSession {
      session = pinnedSession
    } else {
      session = try await resolveKernelQuerySession(
        surface: surface,
        requestedModelProfile: requestedModelProfile
      )
    }
    let initialSnapshot = try await client.getContextSnapshot(
      sessionId: session.sessionId,
      surfaceKind: surface.surfaceKind
    )
    let workspacePath = session.profile.workingDirectory
    let memoryText = formatMemoriesSection()
    let goalText = formatGoalSection()
    let taskText = formatTasksSection()
    let identityText = formatAIProfileSection()
    var surfacePayload: [String: Any] = [
      "presentation": systemPromptStyle == .floating ? "floating" : "main",
      "onboarding": isOnboarding,
    ]
    if let systemPromptPrefix, !systemPromptPrefix.isEmpty {
      surfacePayload["experienceContext"] = systemPromptPrefix
    }
    if let systemPromptSuffix, !systemPromptSuffix.isEmpty {
      surfacePayload["responseContext"] = systemPromptSuffix
    }
    if let notificationContext, !notificationContext.isEmpty {
      surfacePayload["notificationContext"] = notificationContext
    }
    let capturedAtMs = Int(Date().timeIntervalSince1970 * 1_000)
    let screenOutcome: AgentContextSourceOutcome = screenPayload == nil ? .empty : .available
    var sources: [(AgentContextSource, AgentContextSourceOutcome, [String: Any], Int?)] = [
      (
        .identity,
        identityText.isEmpty ? .empty : .available,
        identityText.isEmpty ? [:] : ["profile": identityText, "timeZone": TimeZone.current.identifier],
        nil
      ),
      (
        .memories,
        memoryText.isEmpty ? .empty : .available,
        memoryText.isEmpty ? [:] : ["content": memoryText],
        nil
      ),
      (
        .goals,
        goalText.isEmpty ? .empty : .available,
        goalText.isEmpty ? [:] : ["content": goalText],
        nil
      ),
      (
        .tasks,
        taskText.isEmpty ? .empty : .available,
        taskText.isEmpty ? [:] : ["content": taskText],
        nil
      ),
      (
        .workspace,
        .available,
        [
          "workingDirectory": workspacePath,
          "databaseSchema": cachedDatabaseSchema,
        ],
        nil
      ),
      (.surface, .available, surfacePayload, nil),
    ]
    if includeScreenSource {
      sources.append(
        (
          .screen,
          screenOutcome,
          screenPayload ?? [:],
          screenPayload == nil ? nil : capturedAtMs + 120_000
        ))
    }
    for (source, outcome, payload, expiresAtMs) in sources {
      let revision = try AgentContextRevision.make(source: source, payload: payload, outcome: outcome)
      guard initialSnapshot.sourceRevision(for: source) != revision else { continue }
      _ = try await client.updateContextSource(
        sessionId: session.sessionId,
        surfaceKind: surface.surfaceKind,
        source: source,
        sourceRevision: revision,
        outcome: outcome,
        capturedAtMs: capturedAtMs,
        expiresAtMs: expiresAtMs,
        payload: RuntimeJSONPayloadBox(payload)
      )
    }
    let snapshot = try await client.getContextSnapshot(
      sessionId: session.sessionId,
      surfaceKind: surface.surfaceKind
    )
    return KernelQueryContext(session: session, snapshot: snapshot)
  }

  /// Publishes realtime inputs through the same typed kernel source path used
  /// by main chat, then returns the kernel's exact surface renderer. Realtime
  /// never selects, concatenates, or re-renders source material itself.
  func prepareRealtimeVoiceContextSnapshot() async throws -> KernelVoiceContextSnapshot {
    guard await ensureBridgeStartedForKernel() else { return .empty }
    do {
      let surface = realtimeVoiceSurfaceReference()
      let context = try await prepareKernelQueryContext(
        surface: surface,
        systemPromptStyle: .floating,
        systemPromptPrefix: nil,
        systemPromptSuffix: nil,
        notificationContext: nil,
        screenPayload: nil,
        includeScreenSource: false
      )
      return KernelTurnProjection.voiceContextSnapshot(
        from: context.snapshot,
        sessionId: context.session.sessionId,
        surface: surface
      )
    } catch is CancellationError {
      // Cancellation is caller-owned. A speculative key-down prefetch may
      // suppress its own supersession, while a hard refresh/barge-in must
      // observe cancellation and fail its continuity fence.
      throw CancellationError()
    } catch {
      log("ChatProvider: realtime kernel context preparation failed: \(error.localizedDescription)")
      return .empty
    }
  }

  private static func queryAttachments(_ attachments: [ChatAttachment]) -> [AgentQueryAttachment] {
    attachments.map { attachment in
      AgentQueryAttachment(
        attachmentId: attachment.id,
        displayName: attachment.fileName,
        mimeType: attachment.mimeType,
        sizeBytes: attachment.data?.count,
        uri: attachment.localFileURL?.absoluteString
      )
    }
  }

  private func warmupKernelQuerySession(_ session: AgentSurfaceSession) async {
    #if DEBUG
      if let warmupKernelQuerySessionForTests {
        await warmupKernelQuerySessionForTests(session)
        return
      }
    #endif
    await resolvedAgentClient().warmupSession(session)
  }

  private func performAgentQuery(
    _ invocation: ChatProviderAgentQueryInvocation,
    onTextDelta: @escaping AgentClient.TextDeltaHandler,
    onToolActivity: @escaping AgentClient.ToolActivityHandler,
    onThinkingDelta: @escaping AgentClient.ThinkingDeltaHandler,
    onToolResultDisplay: @escaping AgentClient.ToolResultDisplayHandler,
    onAuthRequired: @escaping AgentClient.AuthRequiredHandler,
    onAuthSuccess: @escaping AgentClient.AuthSuccessHandler
  ) async throws -> AgentClient.QueryResult {
    return try await resolvedAgentClient().query(
      prompt: invocation.prompt,
      session: invocation.session,
      surface: invocation.surface,
      mode: invocation.mode,
      imageData: invocation.imageData,
      attachments: invocation.attachments,
      producingTurnId: invocation.producingTurnId,
      expectedContext: invocation.expectedContext,
      reasoningEffort: invocation.reasoningEffort,
      onTextDelta: onTextDelta,
      onToolActivity: onToolActivity,
      onThinkingDelta: onThinkingDelta,
      onToolResultDisplay: onToolResultDisplay,
      onAuthRequired: onAuthRequired,
      onAuthSuccess: onAuthSuccess
    )
  }

  // MARK: - Session Management

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
      RealtimeHubController.shared.invalidateVoiceContextForChatSelectionChange()
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
    await rehydrateMissingArtifactResourcesFromKernel()
    guard isChatSelectionLeaseCurrent(selectionGeneration, ownerLease: ownerLease) else { return }
    if let ownerID = ownerLease.ownerID {
      chatSelectionStore.setSelectedChatID(session.id, ownerID: ownerID)
    }
    RealtimeHubController.shared.invalidateVoiceContextForChatSelectionChange()
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
      AgentRuntimeStatusStore.shared.clear(surface: surface)
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
      AgentRuntimeStatusStore.shared.clear(surface: surface)

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
  private func loadGoalsIfNeeded() async {
    let ownerLease = captureCatalogOwnerLease()
    do {
      let goals: [LocalGoal]
      #if DEBUG
        if let loadGoalsForTests {
          goals = try await loadGoalsForTests()
        } else {
          goals = try await GoalStorage.shared.getLocalGoals(activeOnly: true)
        }
      #else
        goals = try await GoalStorage.shared.getLocalGoals(activeOnly: true)
      #endif
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      cachedGoals = goals
      goalsLoaded = true
      log("ChatProvider loaded \(cachedGoals.count) goals from local DB")
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      logError("Failed to load goals for chat context", error: error)
    }
  }

  /// Formats goals into a prompt section
  private func formatGoalSection() -> String {
    guard !cachedGoals.isEmpty else { return "" }

    var lines: [String] = ["\n<user_goals>"]
    for goal in cachedGoals {
      var line = "- \(goal.title)"
      if let desc = goal.description, !desc.isEmpty {
        line += ": \(desc)"
      }
      lines.append(line)
    }
    lines.append("</user_goals>")
    return lines.joined(separator: "\n")
  }

  // MARK: - Load Tasks

  /// Refreshes the latest 20 active tasks for every prompt. This deliberately
  /// avoids a process-lifetime cache crossing local mutations or owner changes.
  private func loadTasksIfNeeded() async {
    let ownerLease = captureCatalogOwnerLease()
    do {
      let tasks: [TaskActionItem]
      #if DEBUG
        if let loadTasksForTests {
          tasks = try await loadTasksForTests()
        } else {
          tasks = try await ActionItemStorage.shared.getLocalActionItems(
            limit: 20,
            completed: false
          )
        }
      #else
        tasks = try await ActionItemStorage.shared.getLocalActionItems(
          limit: 20,
          completed: false
        )
      #endif
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      cachedTasks = tasks
      tasksLoaded = true
      log("ChatProvider loaded \(cachedTasks.count) tasks for context")
    } catch {
      guard isCatalogOwnerLeaseCurrent(ownerLease) else { return }
      logError("Failed to load tasks for chat context", error: error)
      tasksLoaded = true
    }
  }

  #if DEBUG
    func promptContextSectionsForTests() -> (goals: String, tasks: String) {
      (formatGoalSection(), formatTasksSection())
    }
  #endif

  /// Formats cached tasks into a prompt section
  private func formatTasksSection() -> String {
    guard !cachedTasks.isEmpty else { return "" }

    var lines: [String] = ["\n<user_tasks>", "Current tasks:"]
    for task in cachedTasks {
      var line = "- \(task.description)"
      if let priority = task.priority {
        line += " [priority: \(priority)]"
      }
      if let dueAt = task.dueAt {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        line += " [due: \(formatter.string(from: dueAt))]"
      }
      lines.append(line)
    }
    lines.append("</user_tasks>")
    return lines.joined(separator: "\n")
  }

  // MARK: - Load AI User Profile

  /// Fetches the latest AI-generated user profile from local database
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
  private func loadSchemaIfNeeded() async {
    guard !schemaLoaded else { return }

    guard let dbQueue = await RewindDatabase.shared.getDatabaseQueue() else {
      log("ChatProvider: database not available for schema introspection")
      schemaLoaded = true
      return
    }

    do {
      let tables = try await dbQueue.read { db -> [(name: String, sql: String)] in
        let rows = try Row.fetchAll(
          db,
          sql: """
                SELECT name, sql FROM sqlite_master
                WHERE type='table' AND sql IS NOT NULL
                ORDER BY name
            """)
        return rows.compactMap { row -> (name: String, sql: String)? in
          guard let name: String = row["name"],
            let sql: String = row["sql"]
          else { return nil }
          return (name: name, sql: sql)
        }
      }

      cachedDatabaseSchema = formatSchema(tables: tables)
      schemaLoaded = true
      log("ChatProvider loaded schema for \(tables.count) tables")
    } catch {
      logError("Failed to load database schema", error: error)
      schemaLoaded = true
    }
  }

  /// Formats raw DDL into a compact, LLM-friendly schema block
  private func formatSchema(tables: [(name: String, sql: String)]) -> String {
    var lines: [String] = ["**Database schema (\(DesktopProductIdentity.databaseFilename)):**", ""]

    for (name, sql) in tables {
      // Skip internal tables
      if ChatPrompts.excludedTables.contains(name) { continue }
      if ChatPrompts.excludedTablePrefixes.contains(where: { name.hasPrefix($0) }) { continue }
      // Skip FTS virtual and shadow tables — documented in schemaFooter with MATCH patterns instead
      if name.contains("_fts") { continue }

      // Extract column names only, stripping types, constraints, and infrastructure columns
      let columnNames = extractColumns(from: sql).compactMap { col -> String? in
        let name =
          col.components(separatedBy: .whitespaces).first?
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`")) ?? ""
        return ChatPrompts.excludedColumns.contains(name) ? nil : name
      }.filter { !$0.isEmpty }
      guard !columnNames.isEmpty else { continue }

      // Table header with annotation
      let annotation = ChatPrompts.tableAnnotations[name] ?? ""
      let header = annotation.isEmpty ? name : "\(name) — \(annotation)"
      lines.append(header)

      // Columns with annotations (key columns get descriptions, others are just names)
      let tableAnnotations = ChatPrompts.columnAnnotations[name] ?? [:]
      if tableAnnotations.isEmpty {
        lines.append("  \(columnNames.joined(separator: ", "))")
      } else {
        let annotated = columnNames.map { col in
          if let desc = tableAnnotations[col] {
            return "\(col) — \(desc)"
          }
          return col
        }
        lines.append("  \(annotated.joined(separator: ", "))")
      }
      lines.append("")
    }

    // Append FTS documentation, relationships, and footer
    lines.append(ChatPrompts.schemaFooter)

    return lines.joined(separator: "\n")
  }

  /// Extracts column definitions from a CREATE TABLE SQL statement
  /// Produces compact representations like: "id INTEGER PRIMARY KEY", "name TEXT NOT NULL"
  private func extractColumns(from sql: String) -> [String] {
    // Find content between first ( and last )
    guard let openParen = sql.firstIndex(of: "("),
      let closeParen = sql.lastIndex(of: ")")
    else { return [] }

    let body = String(sql[sql.index(after: openParen)..<closeParen])

    // Split by commas, but respect parentheses (for REFERENCES(...) etc.)
    var columns: [String] = []
    var current = ""
    var depth = 0
    for char in body {
      if char == "(" { depth += 1 } else if char == ")" { depth -= 1 }

      if char == "," && depth == 0 {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { columns.append(trimmed) }
        current = ""
      } else {
        current.append(char)
      }
    }
    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { columns.append(trimmed) }

    // Filter out table constraints (UNIQUE, CHECK, FOREIGN KEY, etc.) — keep only column defs
    return columns.filter { col in
      let upper = col.uppercased().trimmingCharacters(in: .whitespaces)
      return !upper.hasPrefix("UNIQUE") && !upper.hasPrefix("CHECK") && !upper.hasPrefix("FOREIGN")
        && !upper.hasPrefix("CONSTRAINT") && !upper.hasPrefix("PRIMARY KEY")
    }.map { col in
      // Normalize whitespace
      col.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
  }

  /// Initialize chat: fetch sessions and load messages
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
    await loadGoalsIfNeeded()
    await loadTasksIfNeeded()
    await loadAIProfileIfNeeded()
    await loadSchemaIfNeeded()
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
    RealtimeHubController.shared.invalidateVoiceContextForChatSelectionChange()
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
    await rehydrateMissingArtifactResourcesFromKernel()
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
    guard isSending else { return false }
    guard let activeTurnOwner, owner.canInterrupt(activeTurnOwner) else {
      log("ChatProvider: ignoring stop from non-owner turn")
      return false
    }
    isStopping = true
    let stoppedGen = sendGeneration
    activeStopReason = (generation: stoppedGen, reason: reason)
    if activeChatTurnLifecycle?.generation == stoppedGen {
      activeChatTurnLifecycle?.lifecycle.revoke(.stop(reason))
    }
    sendGeneration += 1
    let myGen = sendGeneration
    Task {
      let shouldInterruptBridge = await MainActor.run { () -> Bool in
        guard self.isSending,
          self.sendGeneration == myGen,
          self.activeBridgeSendGeneration == stoppedGen
        else {
          return false
        }
        self.activeBridgeSendGeneration = nil
        return true
      }
      if shouldInterruptBridge {
        await resolvedAgentClient().interrupt()
      }
      // Normal path: interrupt → bridge emits final result or .stopped.
      // Fallback: if the bridge drops the turn_end as "stray", force-release
      // after a short grace so the user's next query is not silently swallowed.
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      let shouldTerminalizeJournal = await MainActor.run { () -> Bool in
        guard self.isSending,
          self.sendGeneration == myGen,
          self.sendLockOwnership.generation == stoppedGen
        else { return false }
        log("ChatProvider: interrupt didn't close stream in 3s — force-resetting isSending")
        let activeClientTurnId = self.activeChatClientTurnId.flatMap {
          $0.generation == stoppedGen ? $0.id : nil
        }
        let partialResponse =
          activeClientTurnId.map { clientTurnId in
            self.messages.contains {
              $0.clientTurnId == clientTurnId
                && $0.sender == .ai
                && $0.isStreaming
                && (!$0.text.isEmpty || !$0.contentBlocks.isEmpty)
            }
          } ?? false
        self.finishActiveChatTelemetry(
          generation: stoppedGen,
          stopReason: reason,
          partialResponse: partialResponse
        )
        self.releaseSendLock(sendGeneration: stoppedGen)
        return true
      }
      if shouldTerminalizeJournal {
        _ = await self.finishJournalTarget(generation: stoppedGen, status: .failed)
      }
    }
    // Result flows back normally through the bridge with partial text
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
    messageSource: String
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
        ownerID: ownerID
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

  private func finishJournalTarget(
    generation: Int,
    queryResult: AgentClient.QueryResult,
    disposition: KernelJournalTerminalDisposition
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
    let message = messages.first(where: { $0.id == target.assistantMessageId })
    let resultResources =
      queryResult.artifacts.map(ChatResource.artifact)
      + queryResult.completionDeltaArtifacts.map(ChatResource.artifact)
    let accepted = await journalWriteCoordinator.retryTerminalization {
      await self.kernelTurnProjection.terminalizeTurn(
        surface: target.surface,
        turnId: target.assistantMessageId,
        message: message,
        producingRunId: queryResult.runId,
        producingAttemptId: queryResult.attemptId,
        disposition: disposition,
        acceptedContent: queryResult.text,
        acceptedResources: resultResources,
        ownerID: target.ownerID
      ) != nil
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

  /// Send a message and get a response through managed Pi.
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
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let managedModel = ModelQoS.Gemini.chat
    guard !trimmedText.isEmpty else { return nil }
    guard !isClearing, !isLoading else {
      errorMessage =
        isClearing
        ? "Wait for this chat to finish clearing before sending."
        : "Wait for this chat to finish loading before sending."
      return nil
    }
    guard !isCreatingSession else {
      errorMessage = "Wait for the new chat to finish opening before sending."
      return nil
    }
    guard deletingSessionIds.isEmpty else {
      errorMessage = "Wait for chat deletion to finish before sending."
      return nil
    }
    guard let turnAuthorizationSnapshot = authorizeTurn(for: runtimeOwnerId) else { return nil }
    let capturedRuntimeOwnerID = turnAuthorizationSnapshot.ownerID
    let usesMainComposer = turnOwner == .mainChat && surfaceRef == nil
    let submittedDraftKey = activeDraftKey
    let submittedIsDefaultChat = isInDefaultChat
    let submittedSessionID = currentSession?.id
    let submittedAttachments = usesMainComposer ? pendingAttachments : []
    let submittedAttachmentIDs = Set(submittedAttachments.map(\.id))

    // Guard against concurrent sendMessage calls.
    // The bridge uses a single message continuation, so concurrent queries
    // would cause responses to be consumed by the wrong caller.
    guard !isSending, !sendLockOwnership.isHeld else {
      log("ChatProvider: sendMessage called while already sending, ignoring")
      return nil
    }

    let usageLimiter = FloatingBarUsageLimiter.shared

    // QueryTracer: picked up from the TaskLocal context established by the
    // floating-bar / PTT entry points (nil for non-traced call sites).
    let tracer = QueryTracerContext.current

    sendGeneration += 1
    let sendGen = sendGeneration
    guard sendLockOwnership.acquire(generation: sendGen) else {
      log("ChatProvider: bridge send lock was held while isSending=false; rejecting send")
      return nil
    }
    isSending = true
    isStopping = false
    activeTurnOwner = turnOwner
    errorMessage = nil
    currentError = nil
    let telemetrySurface = Self.chatTelemetrySurface(
      turnOwner: turnOwner,
      isOnboarding: isOnboarding,
      systemPromptStyle: systemPromptStyle
    )
    let telemetryAttempt = ChatQueryTelemetryAttempt(
      attemptId: clientTurnId,
      surface: telemetrySurface,
      harness: AgentHarnessMode.piMono.rawValue,
      runtimeSurface: surfaceRef?.surfaceKind,
      inputLength: trimmedText.count,
      attachmentCount: submittedAttachments.count,
      hasImage: Self.chatTelemetryHasImage(
        explicitImagePresent: imageData != nil,
        stagedImageAttachmentPresent: submittedAttachments.contains(where: \.isImage)
      )
    )
    let turnLifecycle = ChatTurnLifecycle()
    let turnAttemptId = telemetryAttempt.context.attemptId
    activeChatTelemetryAttempt = (generation: sendGen, attempt: telemetryAttempt)
    activeChatTurnLifecycle = (generation: sendGen, lifecycle: turnLifecycle)
    activeChatClientTurnId = (generation: sendGen, id: turnAttemptId)
    activeSendChatID = submittedSessionID ?? "default"

    // Ensure bridge is running
    tracer?.begin("bridge_ensure")
    let bridgeStarted = await ensureBridgeStarted(authoritativeGeneration: sendGen)
    guard sendGeneration == sendGen, turnLifecycle.acceptsResult else {
      tracer?.end("bridge_ensure", metadata: ["status": "cancelled"])
      tracer?.finalize(tokenCount: 0, model: managedModel)
      telemetryAttempt.finish(stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen))
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    guard bridgeStarted else {
      tracer?.end("bridge_ensure", metadata: ["error": "bridge_failed"])
      tracer?.finalize(tokenCount: 0, model: managedModel)
      if currentError == nil, errorMessage?.isEmpty ?? true {
        errorMessage = "AI not available"
      }
      telemetryAttempt.fail(errorClass: .bridgeUnavailable)
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    tracer?.end("bridge_ensure", metadata: ["status": "ok"])

    // Determine session ID based on mode
    // In default chat mode (isInDefaultChat=true): no session ID (compatible with Flutter)
    // In session mode: require session ID
    var sessionId: String? = nil
    if !submittedIsDefaultChat {
      guard let sid = submittedSessionID else {
        errorMessage = "Failed to create chat session"
        tracer?.finalize(tokenCount: 0, model: managedModel)
        telemetryAttempt.fail(errorClass: .sessionSetup)
        clearChatTelemetryState(for: sendGen)
        releaseSendLock(sendGeneration: sendGen)
        return nil
      }
      sessionId = sid
    }
    guard sendGeneration == sendGen else {
      tracer?.finalize(tokenCount: 0, model: managedModel)
      telemetryAttempt.finish(stopReason: stopReason(for: sendGen))
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }

    let resolvedSurface = querySurface(
      surfaceRef: surfaceRef,
      sessionId: sessionId,
      systemPromptStyle: systemPromptStyle
    )
    let pinnedSession: AgentSurfaceSession
    do {
      pinnedSession = try await resolveKernelQuerySession(
        surface: resolvedSurface,
        requestedModelProfile: managedModel
      )
    } catch {
      tracer?.finalize(tokenCount: 0, model: managedModel)
      if ChatQueryResultAuthority.acceptsContinuation(
        currentGeneration: sendGeneration,
        turnGeneration: sendGen,
        turnAcceptsResult: turnLifecycle.acceptsResult
      ) {
        errorMessage = "Could not prepare this chat session. Try again."
        telemetryAttempt.fail(errorClass: .sessionSetup)
      } else {
        telemetryAttempt.finish(
          stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen)
        )
      }
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    if usageLimiter.serverQuota == nil {
      await usageLimiter.syncQuota()
    }
    guard
      ChatQueryResultAuthority.acceptsContinuation(
        currentGeneration: sendGeneration,
        turnGeneration: sendGen,
        turnAcceptsResult: turnLifecycle.acceptsResult
      )
    else {
      tracer?.finalize(tokenCount: 0, model: managedModel)
      telemetryAttempt.finish(
        stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen)
      )
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    if usageLimiter.isLimitReached {
      log("ChatProvider: pinned Omi session blocked by free-tier monthly limit")
      errorMessage = "You've reached \(usageLimiter.limitDescription). Upgrade to keep chatting."
      NotificationCenter.default.post(
        name: .showUsageLimitPopup,
        object: nil,
        userInfo: ["reason": "chat"]
      )
      tracer?.finalize(tokenCount: 0, model: managedModel)
      telemetryAttempt.fail(errorClass: .quota)
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    // The generic watchdog owns only a silent bridge with no active tool.
    // Active tools must reach their 90s no-progress watchdog first so their
    // terminal cause and correlation survive the bridge interruption.
    let turnStartMs = ChatProvider.monotonicNowMs()
    let stallDetector = StallDetector(thresholds: .v1Defaults, startedAtMs: turnStartMs)
    let watchdogAIMessageId = Self.messageIds(forAttemptId: turnAttemptId).assistant
    let genericWatchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: UInt64(Self.genericWatchdogPollMs) * 1_000_000)
        } catch {
          return
        }
        let nowMs = ChatProvider.monotonicNowMs()
        let canFire = await stallDetector.isSilentWithoutActiveTools(
          durationMs: Self.genericWatchdogInactivityMs,
          atMs: nowMs
        )
        guard canFire, let self else { continue }
        let stillStuck = await MainActor.run { () -> Bool in
          guard
            self.isSending,
            self.sendGeneration == sendGen,
            self.activeBridgeSendGeneration == sendGen
          else { return false }
          log("ChatProvider: generic watchdog fired after 60s of silence — bridge is stuck; force-resetting")
          // Mark this generation before interrupting: interrupt() resumes the
          // in-flight request with `.stopped`, and the catch below uses this
          // marker to surface the timeout instead of silently dropping the turn.
          if turnLifecycle.revoke(.watchdogTimeout) {
            self.sendWatchdogFiredGeneration = sendGen
          } else if turnLifecycle.revocationReason == .toolStall {
            log("ChatProvider: send watchdog preserving earlier tool-stall terminal cause")
          }
          return true
        }
        guard stillStuck else { return }
        await self.resolvedAgentClient().interrupt()
        // Fallback for the "stray turn_end" case where interrupt() does not
        // route through the catch (no active request to resume): if the lock is
        // somehow still held, force-release it and surface the timeout here.
        // Deliberately does NOT clear sendWatchdogFiredGeneration — only the
        // catch clears it, so if this fallback wins the race with the catch, the
        // catch still sees the marker and surfaces the timeout instead of
        // re-silencing the turn. A stale marker is harmless: generations only
        // increase, so it never matches a later send.
        let shouldTerminalizeJournal = await MainActor.run { () -> Bool in
          guard self.isSending, self.sendGeneration == sendGen else { return false }
          let revocationReason = turnLifecycle.revocationReason
          let toolStallAbortFired =
            self.sendToolStallAbortGeneration == sendGen
            || revocationReason == .toolStall
          let watchdogFired =
            self.sendWatchdogFiredGeneration == sendGen
            || revocationReason == .watchdogTimeout

          // Preserve already-delivered output, but make every visible row
          // terminal before releasing the provider for another send.
          self.streamingBuffer.cancelPendingFlush()
          self.flushStreamingBuffer()
          var partialResponse = false
          if let index = self.messages.firstIndex(where: { $0.id == watchdogAIMessageId }) {
            partialResponse =
              !self.messages[index].text.isEmpty
              || !self.messages[index].contentBlocks.isEmpty
            if partialResponse {
              self.messages[index].isStreaming = false
              ToolCallBlockUpdater.completeRemainingToolCalls(
                in: &self.messages[index].contentBlocks,
                terminalStatus: ChatProvider.lateResultToolStatus(
                  watchdogFired: watchdogFired,
                  toolStallAbortFired: toolStallAbortFired,
                  stopReason: turnLifecycle.stopReason
                )
              )
            } else {
              self.messages.remove(at: index)
            }
          }

          let traceReason = toolStallAbortFired ? "tool_stall" : "watchdog_timeout"
          tracer?.mark("forced_terminal_fallback", metadata: ["reason": traceReason])
          tracer?.end("ttft")
          tracer?.end("generation")
          tracer?.end("llm_request")
          tracer?.finalize(tokenCount: 0, model: managedModel)

          if let terminalMessage = ChatProvider.stoppedTurnErrorMessage(
            watchdogFired: watchdogFired,
            toolStallAbortFired: toolStallAbortFired
          ) {
            self.currentError = nil
            self.errorMessage = terminalMessage
          }
          if !telemetryAttempt.isTerminal {
            if toolStallAbortFired {
              telemetryAttempt.fail(errorClass: .toolStall, partialResponse: partialResponse)
            } else if watchdogFired {
              telemetryAttempt.fail(
                errorClass: .timeout,
                partialResponse: partialResponse,
                watchdogFired: true
              )
            } else {
              telemetryAttempt.finish(
                stopReason: turnLifecycle.stopReason ?? self.stopReason(for: sendGen),
                partialResponse: partialResponse
              )
            }
          }
          self.clearChatTelemetryState(for: sendGen)
          _ = self.releaseSendLock(sendGeneration: sendGen)
          return true
        }
        if shouldTerminalizeJournal {
          _ = await self.finishJournalTarget(generation: sendGen, status: .failed)
        }
        return
      }
    }
    defer { genericWatchdogTask.cancel() }

    // A journal turn may reference only an app-managed local copy.
    var attachmentsForMessage: [ChatAttachment] = []
    if !submittedAttachmentIDs.isEmpty {
      let materializedAttachments = await awaitPendingAttachmentMaterialization(
        targetKey: submittedDraftKey,
        attachmentIDs: submittedAttachmentIDs
      )
      guard
        ChatQueryResultAuthority.acceptsContinuation(
          currentGeneration: sendGeneration,
          turnGeneration: sendGen,
          turnAcceptsResult: turnLifecycle.acceptsResult
        )
      else {
        tracer?.finalize(tokenCount: 0, model: managedModel)
        telemetryAttempt.finish(stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen))
        clearChatTelemetryState(for: sendGen)
        releaseSendLock(sendGeneration: sendGen)
        return nil
      }
      guard let materializedAttachments else {
        errorMessage = "Some attachments could not be copied. Remove them and try again."
        tracer?.finalize(tokenCount: 0, model: managedModel)
        telemetryAttempt.fail(errorClass: .attachmentUpload)
        clearChatTelemetryState(for: sendGen)
        releaseSendLock(sendGeneration: sendGen)
        return nil
      }
      attachmentsForMessage = materializedAttachments
    }
    usageLimiter.recordQuery()

    // Attempt-derived IDs are the canonical local journal identities. No
    // backend delivery may mint or preserve a second writer identity.
    let turnMessageIds = Self.messageIds(forAttemptId: turnAttemptId)
    let userMessageId = turnMessageIds.user
    let capturedSessionId = sessionId
    let journalOrigin = journalOrigin(for: resolvedSurface)
    let userMessage = ChatMessage(
      id: userMessageId,
      clientTurnId: turnAttemptId,
      text: trimmedText,
      sender: .user,
      attachments: attachmentsForMessage,
      turnOwner: turnOwner
    )
    let aiMessageId = turnMessageIds.assistant
    let aiMessage = ChatMessage(
      id: aiMessageId,
      clientTurnId: turnAttemptId,
      text: "",
      sender: .ai,
      isStreaming: true,
      turnOwner: turnOwner
    )
    // Both visible halves enter the journal under one SQLite transaction.
    // If either identity/payload is rejected, neither row can project.
    attachmentsAwaitingJournalAdmission.formUnion(submittedAttachmentIDs)
    let recordedExchange = await recordStreamingJournalExchange(
      surface: resolvedSurface,
      ownerID: capturedRuntimeOwnerID,
      continuityKey: turnAttemptId,
      userMessage: userMessage,
      assistantMessage: aiMessage,
      origin: journalOrigin,
      sessionId: capturedSessionId,
      messageSource: journalOrigin
    )
    attachmentsAwaitingJournalAdmission.subtract(submittedAttachmentIDs)
    let shouldRegisterJournalTerminalTarget: Bool
    #if DEBUG
      shouldRegisterJournalTerminalTarget = recordStreamingJournalExchangeForTests == nil
    #else
      shouldRegisterJournalTerminalTarget = true
    #endif
    if recordedExchange, shouldRegisterJournalTerminalTarget {
      journalOwnerByMessageID[aiMessageId] = capturedRuntimeOwnerID
      journalTerminalTargets.register(
        ChatJournalTerminalTarget(
          surface: resolvedSurface,
          assistantMessageId: aiMessageId,
          ownerID: capturedRuntimeOwnerID,
          onFinalized: onJournalFinalized
        ), generation: sendGen)
    }
    if multiChatEnabled {
      await fetchSessions()
    }
    guard
      ChatQueryResultAuthority.acceptsContinuation(
        currentGeneration: sendGeneration,
        turnGeneration: sendGen,
        turnAcceptsResult: turnLifecycle.acceptsResult
      )
    else {
      if recordedExchange {
        _ = await finishJournalTarget(generation: sendGen, status: .failed)
      }
      telemetryAttempt.finish(
        stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen)
      )
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    guard recordedExchange else {
      errorMessage = "Could not save this message. Try again."
      telemetryAttempt.fail(errorClass: .sessionSetup)
      clearChatTelemetryState(for: sendGen)
      releaseSendLock(sendGeneration: sendGen)
      return nil
    }
    if !submittedAttachmentIDs.isEmpty {
      for attachment in attachmentsForMessage {
        pendingAttachmentScopes.removeValue(forKey: attachment.id)
      }
      var remaining = pendingAttachmentsByDraftKey[submittedDraftKey] ?? []
      remaining.removeAll { submittedAttachmentIDs.contains($0.id) }
      pendingAttachmentsByDraftKey[submittedDraftKey] = remaining
      ChatDraftStore.shared.setAttachments(remaining, for: submittedDraftKey)
      if activeDraftKey == submittedDraftKey {
        isRestoringPendingAttachments = true
        pendingAttachments = remaining
        isRestoringPendingAttachments = false
      }
    }
    // Signal to ChatMessagesView only after the complete exchange exists so
    // anchoring can never expose a user row without its response target.
    localSendToken = LocalSendToken(generation: sendGen)
    onAccepted?()

    // Track onboarding user-message shape without content.
    if isOnboarding {
      AnalyticsManager.shared.onboardingChatMessageDetailed(
        role: "user", text: trimmedText, step: "chat"
      )
    }

    // Analytics: track tool usage; the telemetry attempt owns wall-clock timing.
    let toolTiming = ChatToolTimingState()
    let responseMetrics = ChatResponseMetrics()
    var completedResponseText: String?
    var screenContextEligibleForTurn = false
    var correlatedTerminalResult: AgentClient.QueryResult?
    var agentQueryStarted = false

    // Refresh data inputs each turn. The kernel renders these sources under
    // its own pinned policy; Swift never supplies a system instruction.
    await refreshMemoriesForPrompt()
    do {
      // If the caller didn't provide explicit imageData (e.g. screen-capture
      // assistant), fall back to the first image attached by the user.
      var effectiveImageData = imageData
      if effectiveImageData == nil {
        effectiveImageData = attachmentsForMessage.first(where: { $0.isImage })?.data
      }
      var notificationContext: String?
      if systemPromptSuffix == nil {
        let aiMessages = messages.filter { $0.sender == .ai && !$0.isStreaming }
        if let lastAI = aiMessages.last, let ctx = lastAI.notificationContext {
          notificationContext = ctx
          if effectiveImageData == nil, let screenshotData = lastAI.notificationScreenshot {
            effectiveImageData = screenshotData
          }
        }
      }
      var screenPayload: [String: Any]?
      if effectiveImageData == nil,
        let screenContextReason = ScreenContextAutoIncludePolicy.reason(
          userText: trimmedText,
          systemPromptStyle: systemPromptStyle,
          turnOwner: turnOwner,
          onboardingActive: !UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedOnboarding)
        )
      {
        let screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted && !screenContextReason.isExplicitScreenRequest {
          // Ambient floating turns are allowed to use screen context when already granted,
          // but they must not manufacture a screen-permission request for generic utterances.
          // Still tell the model WHY there is no screen context, so a
          // screen-dependent question gets an honest "enable Screen
          // Recording" lead-in instead of a silently blind answer.
          screenPayload = [
            "permission": [
              "screen_recording": "not_granted"
            ],
            "reason": "ambient_surface_context",
            "context": ScreenContextWorkContextBuilder.ambientPermissionUnavailablePayload(),
          ]
        } else {
          screenContextEligibleForTurn = true
          let screenContextPayload: [String: Any]
          if screenContextReason.isExplicitScreenRequest {
            // An explicit current-screen question gets one capture
            // scoped to this exact turn. Never let a Rewind frame or
            // OCR summary impersonate the image the model receives.
            if screenRecordingGranted {
              effectiveImageData = await Task.detached(priority: .userInitiated) {
                ScreenCaptureManager.captureScreenData()
              }.value
            }
            screenContextPayload = ScreenContextWorkContextBuilder.explicitCurrentScreenPayload(
              screenRecordingGranted: screenRecordingGranted,
              imageAttached: effectiveImageData != nil
            )
          } else {
            let rawScreenContextPayloadBox = await ScreenContextWorkContextBuilder.payloadBox(
              arguments: RuntimeJSONPayloadBox(["minutes": 10]),
              authorizationSnapshot: turnAuthorizationSnapshot
            )
            let rawScreenContextPayload = rawScreenContextPayloadBox.value
            screenContextPayload = ScreenContextWorkContextBuilder.ambientPayload(from: rawScreenContextPayload)
          }
          screenPayload = [
            "permission": [
              "screen_recording": screenRecordingGranted ? "granted" : "not_granted"
            ],
            "reason": screenContextReason.isExplicitScreenRequest
              ? "explicit_screen_request"
              : "ambient_surface_context",
            "context": screenContextPayload,
          ]
          responseMetrics.recordToolRequested(name: "get_work_context")
          if let contextData = try? JSONSerialization.data(
            withJSONObject: screenContextPayload,
            options: [.sortedKeys]
          ), let contextJSON = String(data: contextData, encoding: .utf8) {
            responseMetrics.recordToolResult(name: "get_work_context", result: contextJSON)
          }
        }
      }
      let kernelContext = try await prepareKernelQueryContext(
        surface: resolvedSurface,
        systemPromptStyle: systemPromptStyle,
        systemPromptPrefix: systemPromptPrefix,
        systemPromptSuffix: systemPromptSuffix,
        notificationContext: notificationContext,
        screenPayload: screenPayload,
        requestedModelProfile: managedModel,
        pinnedSession: pinnedSession
      )
      await warmupKernelQuerySession(kernelContext.session)
      let effectiveRequestModel = kernelContext.session.profile.modelProfile

      // Callbacks for agent bridge
      //
      // QueryTracer: responseMetrics marks TTFT on the very first output of
      // any kind (text delta OR tool_use start). It also brackets the
      // text-streaming window so the `generation` span excludes tool time.
      // Kernel control tools (spawn_agent, list_agent_sessions, …) execute in
      // the Node runtime and only surface via tool_activity + tool_result_display.
      // Pair started input with completed output for QueryTracer.tool_executions.
      let pendingToolTraceInputs = ChatToolTraceInputStore()
      let callbackQueue = ChatTurnCallbackQueue(
        generation: sendGen,
        lifecycle: turnLifecycle,
        currentGeneration: { [weak self] in self?.sendGeneration ?? .min }
      )
      let textDeltaHandler: AgentClient.TextDeltaHandler = { [weak self] delta in
        callbackQueue.submit { @MainActor [weak self] in
          guard let self else { return }
          let nowMs = ChatProvider.monotonicNowMs()
          if responseMetrics.markFirstOutputIfNeeded() {
            tracer?.end("ttft")
            tracer?.markTTFT()
          }
          if responseMetrics.markGenerationStartedIfNeeded() {
            tracer?.begin("generation")
          }
          self.appendToMessage(id: aiMessageId, text: delta)
          let transitions = await stallDetector.step(kind: .other, atMs: nowMs)
          self.applyStallTransitions(messageId: aiMessageId, transitions: transitions)
        }
      }
      let toolActivityHandler: AgentClient.ToolActivityHandler = { [weak self] name, status, toolUseId, input in
        let inputBox = input.map { ChatProviderSendableBox(value: $0) }
        callbackQueue.submit { @MainActor [weak self] in
          guard let self else { return }
          let input = inputBox?.value
          let nowMs = ChatProvider.monotonicNowMs()
          // Tools without a toolUseId still get tracked under a
          // synthetic key so the detector's per-tool timer fires.
          let trackedId = ChatProvider.stallTrackingId(toolUseId: toolUseId, name: name)
          let toolStatus = ChatProvider.mapBridgeToolStatus(status)
          let detectorKind: StallDetector.EventKind
          switch status {
          case "started":
            detectorKind = .toolStarted(id: trackedId)
          case "progress":
            detectorKind = .toolProgress(id: trackedId)
          default:
            detectorKind = .toolCompleted(id: trackedId)
          }
          // Trace mutation is admitted through the same generation gate
          // as UI mutation, so a revoked callback cannot extend a turn.
          let traceToolName =
            tracer?.toolNameForTrace(name)
            ?? ChatTelemetryDimension.toolName(name)
          let spanKey = "tool:\(toolUseId ?? traceToolName)"
          if status == "started" {
            if responseMetrics.markFirstOutputIfNeeded() {
              tracer?.end("ttft")
              tracer?.markTTFT()
            }
            tracer?.begin(spanKey, metadata: ["tool": traceToolName])
            if let input {
              let inputJson =
                (try? String(
                  data: JSONSerialization.data(withJSONObject: input),
                  encoding: .utf8
                )) ?? "\(input)"
              pendingToolTraceInputs.record(id: trackedId, inputJson: inputJson)
            }
          } else if toolStatus != .running {
            tracer?.end(spanKey)
          }
          self.addToolActivity(
            messageId: aiMessageId,
            toolName: name,
            status: toolStatus,
            toolUseId: toolUseId,
            input: input
          )
          if status == "started" {
            toolTiming.toolNames.append(name)
            responseMetrics.recordToolRequested(name: name)
            toolTiming.toolStartTimes[trackedId] = Date()
          } else if toolStatus != .running,
            let startTime = toolTiming.toolStartTimes.removeValue(forKey: trackedId)
          {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AnalyticsManager.shared.chatToolCallCompleted(
              toolName: name, durationMs: durationMs, outcome: status)
          }
          let transitions = await stallDetector.step(kind: detectorKind, atMs: nowMs)
          self.applyStallTransitions(messageId: aiMessageId, transitions: transitions)
        }
      }
      let thinkingDeltaHandler: AgentClient.ThinkingDeltaHandler = { [weak self] text in
        callbackQueue.submit { @MainActor [weak self] in
          guard let self else { return }
          let nowMs = ChatProvider.monotonicNowMs()
          self.appendThinking(messageId: aiMessageId, text: text)
          let transitions = await stallDetector.step(kind: .other, atMs: nowMs)
          self.applyStallTransitions(messageId: aiMessageId, transitions: transitions)
        }
      }
      let toolResultDisplayHandler: AgentClient.ToolResultDisplayHandler = { [weak self] toolUseId, name, output in
        callbackQueue.submit { @MainActor [weak self] in
          guard let self else { return }
          let nowMs = ChatProvider.monotonicNowMs()
          if let tracer {
            let trackedId = ChatProvider.stallTrackingId(toolUseId: toolUseId, name: name)
            let pending = pendingToolTraceInputs.take(id: trackedId)
            let inputJson = pending?.inputJson ?? ""
            let durationMs = pending.map { (ContinuousClock.now - $0.started).milliseconds }
            tracer.captureToolExecution(
              toolUseId: toolUseId.isEmpty ? nil : toolUseId,
              name: name,
              input: inputJson,
              output: output,
              durationMs: durationMs
            )
          }
          self.addToolResult(messageId: aiMessageId, toolUseId: toolUseId, name: name, output: output)
          responseMetrics.recordToolResult(name: name, result: output)
          let transitions = await stallDetector.step(kind: .other, atMs: nowMs)
          self.applyStallTransitions(messageId: aiMessageId, transitions: transitions)
        }
      }

      // Periodic tick task surfaces stall promotions during silent
      // gaps when no bridge events arrive. Cancelled via defer on
      // scope exit (success or throw).
      let stallTickTask = Task { [weak self] in
        var issuedToolStallAbort = false
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
          if Task.isCancelled { break }
          let nowMs = ChatProvider.monotonicNowMs()
          let transitions = await stallDetector.tick(atMs: nowMs)
          if !transitions.isEmpty {
            await MainActor.run { [weak self] in
              guard let self,
                self.sendGeneration == sendGen,
                turnLifecycle.acceptsResult
              else { return }
              self.applyStallTransitions(messageId: aiMessageId, transitions: transitions)
            }
          }
          if !issuedToolStallAbort {
            let overdueToolIds = await stallDetector.toolIdsWithoutProgress(
              durationMs: Self.perToolStallAbortMs,
              atMs: nowMs
            )
            if !overdueToolIds.isEmpty {
              issuedToolStallAbort = true
              let shouldInterrupt = await MainActor.run { () -> Bool in
                guard let self, self.isSending, self.sendGeneration == sendGen else { return false }
                self.sendToolStallAbortGeneration = sendGen
                turnLifecycle.revoke(.toolStall)
                log(
                  "ChatProvider: tool no-progress guard fired at \(Self.perToolStallAbortMs / 1_000)s "
                    + "(active_tools=\(overdueToolIds.count)); interrupting bridge"
                )
                return true
              }
              if shouldInterrupt {
                await self?.resolvedAgentClient().interrupt()
              }
            }
          }
        }
      }
      defer { stallTickTask.cancel() }

      // QueryTracer records the kernel snapshot identity, not a Swift-built
      // policy string. The clock starts here so ttft measures input to first output.
      if let tracer {
        let tracedModel = effectiveRequestModel ?? "unknown"
        tracer.captureRequest(
          systemPrompt:
            "kernel-context:\(kernelContext.snapshot.version):\(kernelContext.snapshot.snapshotGeneration):\(kernelContext.snapshot.rendererPolicyVersion):\(kernelContext.snapshot.rendererFingerprint)",
          messages: Array(messages.suffix(40)).map {
            ["role": $0.sender == .user ? "user" : "assistant", "content": $0.text]
          },
          hasScreenshot: effectiveImageData != nil
        )
        tracer.begin("llm_request", metadata: ["model": tracedModel])
        tracer.begin("ttft")
      }

      // Stop can arrive while prompt context/backfill is still awaiting.
      // Do not launch a bridge query after ownership was revoked.
      guard
        ChatQueryResultAuthority.acceptsContinuation(
          currentGeneration: sendGeneration,
          turnGeneration: sendGen,
          turnAcceptsResult: turnLifecycle.acceptsResult
        )
      else {
        tracer?.end("ttft")
        tracer?.end("llm_request")
        tracer?.finalize(tokenCount: 0, model: managedModel)
        if let index = messages.firstIndex(where: { $0.id == aiMessageId }),
          messages[index].text.isEmpty,
          messages[index].contentBlocks.isEmpty
        {
          messages.remove(at: index)
        }
        telemetryAttempt.finish(stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen))
        clearChatTelemetryState(for: sendGen)
        _ = await finishJournalTarget(generation: sendGen, status: .failed)
        releaseSendLock(sendGeneration: sendGen)
        return nil
      }

      _ = await stallDetector.step(kind: .other, atMs: ChatProvider.monotonicNowMs())
      activeBridgeSendGeneration = sendGen
      agentQueryStarted = true
      let queryResult: AgentClient.QueryResult
      do {
        let invocation = ChatProviderAgentQueryInvocation(
          prompt: trimmedText,
          session: kernelContext.session,
          surface: resolvedSurface,
          mode: chatMode.rawValue,
          imageData: effectiveImageData,
          attachments: Self.queryAttachments(attachmentsForMessage),
          producingTurnId: aiMessageId,
          expectedContext: kernelContext.snapshot.freshness,
          reasoningEffort: turnOwner.reasoningEffort
        )
        queryResult = try await performAgentQuery(
          invocation,
          onTextDelta: textDeltaHandler,
          onToolActivity: toolActivityHandler,
          onThinkingDelta: thinkingDeltaHandler,
          onToolResultDisplay: toolResultDisplayHandler,
          onAuthRequired: { [weak self] _, _ in
            callbackQueue.submit { @MainActor [weak self] in
              guard let self else { return }
              self.errorMessage = "Omi authentication is required for managed AI. Sign in, then try again."
            }
          },
          onAuthSuccess: { [weak self] in
            callbackQueue.submit { @MainActor [weak self] in
              guard let self else { return }
              self.errorMessage = nil
            }
          }
        )
      } catch {
        await callbackQueue.drain()
        throw error
      }
      await callbackQueue.drain()
      correlatedTerminalResult = queryResult
      if activeBridgeSendGeneration == sendGen {
        activeBridgeSendGeneration = nil
      }
      try Self.requireSuccessfulQueryResult(queryResult)

      let watchdogFiredBeforeResult = sendWatchdogFiredGeneration == sendGen
      let toolStallAbortFiredBeforeResult = sendToolStallAbortGeneration == sendGen
      guard
        ChatQueryResultAuthority.accepts(
          currentGeneration: sendGeneration,
          resultGeneration: sendGen,
          turnAcceptsResult: turnLifecycle.acceptsResult,
          watchdogFired: watchdogFiredBeforeResult,
          toolStallAbortFired: toolStallAbortFiredBeforeResult
        )
      else {
        // A stopped/timed-out bridge may still deliver a late success.
        // Never let it resurrect the old bubble, overwrite a newer
        // turn's bridge ownership, or persist a response the user did
        // not accept. Remove only this turn's buffered segments.
        streamingBuffer.discardPendingSegments(messageId: aiMessageId)
        var hadPartialResponse = false
        if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
          hadPartialResponse =
            !messages[index].text.isEmpty
            || !messages[index].contentBlocks.isEmpty
          if messages[index].text.isEmpty && messages[index].contentBlocks.isEmpty {
            messages.remove(at: index)
          } else {
            messages[index].isStreaming = false
            ToolCallBlockUpdater.completeRemainingToolCalls(
              in: &messages[index].contentBlocks,
              terminalStatus: ChatProvider.lateResultToolStatus(
                watchdogFired: watchdogFiredBeforeResult,
                toolStallAbortFired: toolStallAbortFiredBeforeResult,
                stopReason: turnLifecycle.stopReason
              )
            )
          }
        }

        let stopProvenance: String
        switch turnLifecycle.revocationReason {
        case .stop(.browserExtensionMissing): stopProvenance = "browser_extension_missing"
        case .stop(.superseded): stopProvenance = "superseded"
        case .stop(.userStop): stopProvenance = "user_stop"
        case .toolStall: stopProvenance = "tool_stall"
        case .watchdogTimeout: stopProvenance = "watchdog_timeout"
        case nil: stopProvenance = "generation_superseded"
        }
        tracer?.mark("late_result_discarded", metadata: ["reason": stopProvenance])
        tracer?.end("ttft")
        tracer?.end("generation")
        tracer?.end("llm_request")
        // A revoked adapter result is not product-authoritative. Do not
        // copy even its result metrics into the accepted-turn trace.
        tracer?.finalize(tokenCount: 0, model: effectiveRequestModel)

        if !telemetryAttempt.isTerminal {
          if toolStallAbortFiredBeforeResult {
            telemetryAttempt.fail(
              errorClass: .toolStall,
              partialResponse: hadPartialResponse
            )
          } else if watchdogFiredBeforeResult {
            telemetryAttempt.fail(
              errorClass: .timeout,
              partialResponse: hadPartialResponse,
              watchdogFired: true
            )
          } else {
            telemetryAttempt.finish(
              stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen),
              partialResponse: hadPartialResponse
            )
          }
        }
        clearChatTelemetryState(for: sendGen)

        // The projection may have removed an empty placeholder already.
        // finishJournalUpdate falls back to a status-only kernel update,
        // which terminalizes the canonical row without late result data.
        _ = await finishJournalTarget(
          generation: sendGen,
          queryResult: queryResult,
          disposition: .discard
        )

        if sendGeneration == sendGen {
          if let timeoutMessage = ChatProvider.stoppedTurnErrorMessage(
            watchdogFired: watchdogFiredBeforeResult,
            toolStallAbortFired: toolStallAbortFiredBeforeResult
          ) {
            errorMessage = timeoutMessage
          }
        }
        releaseSendLock(sendGeneration: sendGen)
        log("ChatProvider: discarded late result for revoked generation \(sendGen)")
        return nil
      }

      // Flush any remaining buffered streaming text before finalizing
      streamingBuffer.cancelPendingFlush()
      flushStreamingBuffer()

      // Determine the final text to display and save
      let messageText: String
      let metricsSnapshot = responseMetrics.snapshot()
      if screenContextEligibleForTurn, !metricsSnapshot.screenContext.screenToolRequested {
        ScreenContextToolTelemetry.trackInvariant(
          "eligible_run_missing_get_work_context",
          context: ScreenContextTelemetryContext.from(surfaceRef: resolvedSurface),
          toolName: "get_work_context"
        )
      }
      if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
        // Message still in memory — update it in-place
        messageText = messages[index].text.isEmpty ? queryResult.text : messages[index].text
        messages[index].text = messageText
        messages[index].isStreaming = false
        // Merge the parent agent's own artifacts with any produced by
        // sub-agents that completed since the last coordinator check, so
        // a finished sub-agent's file surfaces as a card on this response.
        let deltaResources = queryResult.completionDeltaArtifacts.map(ChatResource.artifact)
        messages[index].resources = mergedResources(
          existing: messages[index].resources,
          adding: queryResult.artifacts.map(ChatResource.artifact) + deltaResources
        )
        messages[index].metadata = MessageMetadata(
          model: effectiveRequestModel,
          inputTokens: queryResult.inputTokens,
          outputTokens: queryResult.outputTokens,
          cacheReadTokens: queryResult.cacheReadTokens,
          cacheWriteTokens: queryResult.cacheWriteTokens,
          costUsd: queryResult.costUsd,
          systemPrompt: "kernel-context:\(kernelContext.snapshot.version):\(kernelContext.snapshot.snapshotGeneration)",
          hasScreenshot: effectiveImageData != nil,
          screenshotSizeBytes: effectiveImageData?.count,
          toolNames: toolTiming.toolNames,
          sqlRowsReturned: metricsSnapshot.sqlRowsReturned,
          sqlQueryCount: metricsSnapshot.sqlQueryCount
        )
        completeRemainingToolCalls(
          messageId: aiMessageId,
          terminalStatus: .completed,
          scheduleJournal: false
        )
      } else {
        // Message no longer in memory (user switched away from this session).
        messageText = queryResult.text
        log("Chat response arrived after session switch")
      }

      // QueryTracer: success path — record the response, close the remaining
      // spans (end calls are no-ops if already closed), and write the trace
      // with real token / cache / cost numbers from the bridge result.
      tracer?.captureResponse(text: messageText)
      tracer?.end("ttft")
      tracer?.end("generation")
      tracer?.end("llm_request")
      tracer?.finalize(
        tokenCount: queryResult.outputTokens,
        model: effectiveRequestModel,
        inputTokens: queryResult.inputTokens,
        outputTokens: queryResult.outputTokens,
        cacheReadTokens: queryResult.cacheReadTokens,
        cacheWriteTokens: queryResult.cacheWriteTokens,
        costUsd: queryResult.costUsd
      )

      // The user-visible query is complete as soon as the final response
      // is in the timeline. Persistence and title generation are separate
      // background reliability concerns and must not inflate query latency
      // or turn a successful answer into a failed attempt.
      let completionMetrics = ChatQueryCompletionMetrics(
        toolCallCount: toolTiming.toolNames.count,
        toolNames: toolTiming.toolNames,
        costUsd: queryResult.costUsd,
        responseLength: messageText.count,
        screenToolRequested: metricsSnapshot.screenContext.screenToolRequested,
        screenToolSucceeded: metricsSnapshot.screenContext.screenToolSucceeded,
        screenToolApprovalRequired: metricsSnapshot.screenContext.screenToolApprovalRequired,
        screenToolFailureCodes: metricsSnapshot.screenContext.screenToolFailureCodes,
        runtimeRunId: queryResult.runId,
        runtimeAttemptId: queryResult.attemptId
      )
      let journalAccepted = await ChatVisibleTurnCompletion.finish(
        lifecycle: turnLifecycle,
        telemetryAttempt: telemetryAttempt,
        metrics: completionMetrics,
        afterTerminal: { [weak self] in
          self?.clearChatTelemetryState(for: sendGen)
        },
        journalCommit: { [weak self] in
          guard let self else { return false }
          return await self.finishJournalTarget(
            generation: sendGen,
            queryResult: queryResult,
            disposition: .accept
          )
        }
      )

      // The kernel journal commit releases the turn.
      releaseSendLock(sendGeneration: sendGen)

      // Auto-generate title after first exchange (user message + AI response)
      if journalAccepted, multiChatEnabled {
        await fetchSessions()
      }

      log("Chat response complete")

      // Track onboarding response shape and bounded tool dimensions without content.
      if isOnboarding {
        let aiText = messages.first(where: { $0.id == aiMessageId })?.text ?? queryResult.text
        AnalyticsManager.shared.onboardingChatMessageDetailed(
          role: "assistant",
          text: aiText,
          step: "chat",
          toolCalls: toolTiming.toolNames.isEmpty ? nil : toolTiming.toolNames,
          model: effectiveRequestModel
        )
      }

      // Skip client-side cost telemetry because the native managed Gemini route
      // already logs Omi-account token/cost usage server-side. Question
      // quota is recorded by the transient inference endpoint, so model calls
      // and helper calls cannot double-count.
      completedResponseText = messageText
    } catch {
      if activeBridgeSendGeneration == sendGen {
        activeBridgeSendGeneration = nil
      }
      // QueryTracer: error path — close spans and write the (partial) trace
      // so failed/timed-out queries still show up in benchmarks.
      tracer?.end("ttft")
      tracer?.end("generation")
      tracer?.end("llm_request")
      tracer?.finalize(tokenCount: 0, model: managedModel)

      // A stop, timeout, or superseding send revokes product authority even
      // if its telemetry fallback has not fired yet. Handle that before
      // touching shared presentation/error state or the send lock.
      if !ChatQueryResultAuthority.acceptsContinuation(
        currentGeneration: sendGeneration,
        turnGeneration: sendGen,
        turnAcceptsResult: turnLifecycle.acceptsResult
      ) {
        streamingBuffer.discardPendingSegments(messageId: aiMessageId)
        let watchdogFired =
          sendWatchdogFiredGeneration == sendGen
          || turnLifecycle.revocationReason == .watchdogTimeout
        let toolStallAbortFired =
          sendToolStallAbortGeneration == sendGen
          || turnLifecycle.revocationReason == .toolStall
        var hadPartialResponse = false
        if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
          hadPartialResponse =
            !messages[index].text.isEmpty
            || !messages[index].contentBlocks.isEmpty
          if messages[index].text.isEmpty && messages[index].contentBlocks.isEmpty {
            messages.remove(at: index)
          } else {
            messages[index].isStreaming = false
            ToolCallBlockUpdater.completeRemainingToolCalls(
              in: &messages[index].contentBlocks,
              terminalStatus: ChatProvider.lateResultToolStatus(
                watchdogFired: watchdogFired,
                toolStallAbortFired: toolStallAbortFired,
                stopReason: turnLifecycle.stopReason
              )
            )
          }
        }
        if !telemetryAttempt.isTerminal {
          if toolStallAbortFired {
            telemetryAttempt.fail(
              errorClass: .toolStall,
              partialResponse: hadPartialResponse
            )
          } else if watchdogFired {
            telemetryAttempt.fail(
              errorClass: .timeout,
              partialResponse: hadPartialResponse,
              watchdogFired: true
            )
          } else {
            telemetryAttempt.finish(
              stopReason: turnLifecycle.stopReason ?? stopReason(for: sendGen),
              partialResponse: hadPartialResponse
            )
          }
        }
        clearChatTelemetryState(for: sendGen)
        if let correlatedTerminalResult {
          _ = await finishJournalTarget(
            generation: sendGen,
            queryResult: correlatedTerminalResult,
            disposition: .discard
          )
        } else {
          _ = await finishJournalTarget(generation: sendGen, status: .failed)
        }
        releaseSendLock(sendGeneration: sendGen)
        log("ChatProvider: discarded late failure for revoked generation \(sendGen)")
        return nil
      }

      // Kernel context readiness happens before the model query. Never
      // interrupt a session that has not been queried yet: doing so turns
      // a recoverable setup timeout into a misleading query failure.
      if let bridgeError = error as? BridgeError, case .timeout = bridgeError {
        if Self.shouldInterruptTimedOutAgentQuery(queryStarted: agentQueryStarted) {
          log("ChatProvider: agent query timed out, sending interrupt to cancel stuck session")
          await resolvedAgentClient().interrupt()
        } else {
          log("ChatProvider: kernel context preparation timed out before an agent query started")
        }
      }

      // Flush any remaining buffered streaming text before handling the error
      streamingBuffer.cancelPendingFlush()
      flushStreamingBuffer()
      let watchdogFired = (sendWatchdogFiredGeneration == sendGen)
      let toolStallAbortFired = (sendToolStallAbortGeneration == sendGen)
      let explicitStopReason = turnLifecycle.stopReason
      let hadPartialResponse =
        messages.first(where: { $0.id == aiMessageId }).map {
          !$0.text.isEmpty || !$0.contentBlocks.isEmpty
        } ?? false

      // Only remove the AI message if it's still empty (no streamed text yet).
      // If text was already streamed and visible, keep it and just stop streaming.
      if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
        if messages[index].text.isEmpty && messages[index].contentBlocks.isEmpty {
          messages[index].isStreaming = false
        } else {
          messages[index].isStreaming = false
          completeRemainingToolCalls(
            messageId: aiMessageId,
            terminalStatus: ChatProvider.remainingToolStatusAfterPartialResponseError(
              error,
              watchdogFired: watchdogFired,
              toolStallAbortFired: toolStallAbortFired,
              stopReason: explicitStopReason
            ),
            scheduleJournal: false
          )
          log("Bridge error after partial response — keeping \(messages[index].text.count) chars of streamed text")
        }
      }

      if !watchdogFired, !toolStallAbortFired, let explicitStopReason {
        telemetryAttempt.finish(
          stopReason: explicitStopReason,
          partialResponse: hadPartialResponse
        )
        if explicitStopReason == .browserExtensionMissing {
          logError(
            "Failed to get AI response attempt_id=\(telemetryAttempt.context.attemptId) error_class=\(ChatQueryErrorClass.browserExtensionMissing.rawValue)",
            error: error
          )
        } else {
          log(
            "Chat query cancelled attempt_id=\(telemetryAttempt.context.attemptId) reason=\(explicitStopReason)"
          )
        }
      } else {
        let telemetryDisposition = ChatQueryFailureDisposition.classify(
          error,
          watchdogFired: watchdogFired,
          toolStallAbortFired: toolStallAbortFired
        )
        switch telemetryDisposition {
        case .failed(let errorClass):
          telemetryAttempt.fail(
            errorClass: errorClass,
            partialResponse: hadPartialResponse,
            detail: .from(error),
            watchdogFired: watchdogFired
          )
          logError(
            "Failed to get AI response attempt_id=\(telemetryAttempt.context.attemptId) error_class=\(errorClass.rawValue)",
            error: error
          )
        case .cancelled(let reason):
          telemetryAttempt.cancel(reason: reason, partialResponse: hadPartialResponse)
          log(
            "Chat query cancelled attempt_id=\(telemetryAttempt.context.attemptId) reason=\(reason.rawValue)"
          )
        }
      }
      clearChatTelemetryState(for: sendGen)
      if let correlatedTerminalResult {
        let disposition: KernelJournalTerminalDisposition
        if case .invalid = correlatedTerminalResult.terminalStatus {
          disposition = .discard
        } else {
          disposition = .accept
        }
        _ = await finishJournalTarget(
          generation: sendGen,
          queryResult: correlatedTerminalResult,
          disposition: disposition
        )
      } else {
        _ = await finishJournalTarget(generation: sendGen, status: .failed)
      }

      // Preserve only a bounded error class in analytics. Raw details stay
      // in the local log and Sentry error above.
      if isOnboarding {
        let messageOutcome: String
        if !watchdogFired, !toolStallAbortFired, let explicitStopReason {
          messageOutcome = explicitStopReason == .browserExtensionMissing ? "error" : "cancelled"
        } else {
          messageOutcome =
            ChatQueryFailureDisposition.classify(
              error,
              watchdogFired: watchdogFired,
              toolStallAbortFired: toolStallAbortFired
            ).presentsUserError ? "error" : "cancelled"
        }
        AnalyticsManager.shared.onboardingChatMessageDetailed(
          role: messageOutcome,
          text: trimmedText,
          step: "chat",
          error: messageOutcome == "error" ? String(describing: error) : nil
        )
      }

      // Show error to user (unless they intentionally stopped).
      //
      // Prefer the structured ChatErrorState card when the error
      // maps cleanly. Falls through to the legacy errorMessage
      // banner for unmappable BridgeError cases (encodingError,
      // quotaExceeded, .agentError with a free-form message).
      // Both surfaces coexist — only one is active at a time per
      // turn.
      if let bridgeError = error as? BridgeError, case .stopped = bridgeError {
        // `.stopped` normally means the user pressed Stop (silent). But if the
        // 180s watchdog fired for THIS send, the `.stopped` came from the
        // watchdog's own interrupt() — the turn timed out, so surface it
        // instead of letting the turn vanish (the watchdog's own error-set
        // races this catch and bails once `isSending` is released here).
        sendWatchdogFiredGeneration = nil
        sendToolStallAbortGeneration = nil
        if let timeoutMessage = ChatProvider.stoppedTurnErrorMessage(
          watchdogFired: watchdogFired,
          toolStallAbortFired: toolStallAbortFired
        ) {
          currentError = nil
          errorMessage = timeoutMessage
        } else if stopReason(for: sendGen) == .userStop, hadPartialResponse {
          currentError = .interrupted
          lastFailedPrompt = nil
          errorMessage = nil
        } else {
          currentError = nil
          lastFailedPrompt = nil
          errorMessage = nil
        }
      } else if !ChatQueryFailureDisposition.classify(
        error,
        watchdogFired: watchdogFired,
        toolStallAbortFired: toolStallAbortFired
      ).presentsUserError {
        lastFailedPrompt = nil
        currentError = nil
        errorMessage = nil
      } else if let bridgeError = error as? BridgeError,
        case .agentRuntimeFailure(let failure) = bridgeError,
        failure.failureCode == .authentication
      {
        currentError = nil
        errorMessage = "Omi authentication is required for managed AI. Sign in, then try again."
        lastFailedPrompt = trimmedText
      } else if let bridgeError = error as? BridgeError,
        let card = ChatErrorState.from(bridgeError)
      {
        currentError = card
        lastFailedPrompt = trimmedText
        errorMessage = nil
      } else {
        errorMessage = error.localizedDescription
        currentError = nil  // ensure the card is dismissed if it was up
      }
    }

    releaseSendLock(sendGeneration: sendGen)

    return completedResponseText
  }

  // MARK: - Post-onboarding opener

  /// Compose and present the personalized opener the instant the Chat tab
  /// appears after onboarding. Composed synchronously from locally-known
  /// facts (name, listening mode, normal Home suggestion chips) so it is instant
  /// and never blank.
  func presentOnboardingOpener() {
    let name = Self.firstName(AuthService.shared.givenName)
    let mode: OnboardingOpenerComposer.ListeningMode =
      AssistantSettings.shared.systemAudioCaptureMode == .always ? .always : .meetingsOnly
    let baseStarters = HomeSuggestionComposer.compose(
      personalized: HomeSuggestionsStore.shared.personalizedQuestions)

    onboardingOpener = OnboardingOpenerComposer.compose(
      name: name, mode: mode, now: Date(), baseStarters: baseStarters)

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

  nonisolated static func chatTelemetrySurface(
    turnOwner: ChatTurnOwner,
    isOnboarding: Bool,
    systemPromptStyle: ChatSystemPromptStyle
  ) -> String {
    if isOnboarding { return "onboarding" }
    switch turnOwner {
    case .floatingDefault: return "floating_text"
    case .floatingVoice: return "floating_voice"
    case .agentPill: return "agent_pill"
    case .mainChat:
      return systemPromptStyle == .floating ? "floating_text" : "main_chat"
    }
  }

  nonisolated static func chatTelemetryHasImage(
    explicitImagePresent: Bool,
    stagedImageAttachmentPresent: Bool
  ) -> Bool {
    explicitImagePresent || stagedImageAttachmentPresent
  }

  nonisolated static func messageIds(forAttemptId attemptId: String) -> (
    user: String,
    assistant: String
  ) {
    (user: attemptId, assistant: "\(attemptId)-assistant")
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

  private func addToolActivity(
    messageId: String, toolName: String, status: ToolCallStatus, toolUseId: String? = nil, input: [String: Any]? = nil
  ) {
    guard
      let index = streamingBuffer.applyToolActivity(
        messageId: messageId,
        toolName: toolName,
        status: status,
        toolUseId: toolUseId,
        input: input,
        messages: &messages,
        normalizeText: { message, text in
          if message.sender == .ai {
            return Self.normalizeAssistantSentenceSpacing(text)
          }
          return text
        }
      )
    else { return }
    if status == .completed {
      attachGeneratedFileResources(
        messageIndex: index,
        toolName: toolName,
        toolUseId: toolUseId,
        extraTexts: []
      )
    }
    scheduleJournalUpdate(messageId: messageId, status: .streaming)
  }

  /// Add tool result output to an existing tool call block
  private func addToolResult(messageId: String, toolUseId: String, name: String, output: String) {
    guard
      let index = streamingBuffer.applyToolResult(
        messageId: messageId,
        toolUseId: toolUseId,
        name: name,
        output: output,
        messages: &messages,
        normalizeText: { message, text in
          if message.sender == .ai {
            return Self.normalizeAssistantSentenceSpacing(text)
          }
          return text
        }
      )
    else { return }
    attachGeneratedFileResources(
      messageIndex: index,
      toolName: name,
      toolUseId: toolUseId,
      extraTexts: [output]
    )
    if let spawnedAgent = Self.materializeAgentSpawnBlockIfNeeded(
      in: &messages[index].contentBlocks,
      toolUseId: toolUseId,
      toolName: name
    ), !spawnedAgent.sessionID.isEmpty, !spawnedAgent.runID.isEmpty {
      // The transcript and notch must project the same accepted kernel
      // run. Without this handoff, main-chat spawn receipts render a
      // structured card while the compact notch still sees an empty
      // AgentPillsManager (white mark and no hover row).
      AgentPillsManager.shared.upsertSpawnedPill(
        id: spawnedAgent.pillID,
        query: spawnedAgent.objective,
        title: spawnedAgent.title,
        sessionId: spawnedAgent.sessionID,
        runId: spawnedAgent.runID,
        attemptId: nil,
        producingJournalSurface: mainChatSurfaceReference()
      )
    }
    scheduleJournalUpdate(messageId: messageId, status: .streaming)
  }

  struct SpawnedAgentPillProjection: Equatable, Sendable {
    let pillID: UUID
    let sessionID: String
    let runID: String
    let title: String
    let objective: String
  }

  /// When `spawn_agent` completes, append a structured `.agentSpawn` block so
  /// cross-surface identity does not depend on tool-output text alone (INV-6 #4),
  /// then return the same receipt for the floating pill projection.
  @discardableResult
  nonisolated static func materializeAgentSpawnBlockIfNeeded(
    in blocks: inout [ChatContentBlock],
    toolUseId: String?,
    toolName: String
  ) -> SpawnedAgentPillProjection? {
    let cleanName: String
    if toolName.hasPrefix("mcp__") {
      cleanName = String(toolName.split(separator: "__").last ?? Substring(toolName))
    } else {
      cleanName = toolName
    }
    guard cleanName == "spawn_agent" else { return nil }

    guard
      let toolIndex = blocks.lastIndex(where: { block in
        guard case .toolCall(_, let name, let status, let existingToolUseId, _, let output) = block,
          !status.isInFlight,
          output != nil
        else { return false }
        let blockName: String
        if name.hasPrefix("mcp__") {
          blockName = String(name.split(separator: "__").last ?? Substring(name))
        } else {
          blockName = name
        }
        guard blockName == "spawn_agent" else { return false }
        if let toolUseId, !toolUseId.isEmpty {
          return existingToolUseId == toolUseId || existingToolUseId == nil
        }
        return true
      })
    else { return nil }

    guard case .toolCall(_, _, _, _, let input, _) = blocks[toolIndex] else { return nil }
    let spawnSource = blocks[toolIndex]
    guard let pillId = spawnSource.spawnedAgentID else { return nil }
    let sessionId = spawnSource.spawnedAgentSessionID ?? ""
    let runId = spawnSource.spawnedAgentRunID ?? ""

    // Idempotent: do not append a second spawn card for the same pill/run.
    let alreadyPresent = blocks.contains { block in
      if case .agentSpawn(_, let existingPill, _, let existingRun, _, _) = block {
        if let existingPill, existingPill == pillId { return true }
        if !runId.isEmpty, existingRun == runId { return true }
      }
      return false
    }
    let titleFromOutput = spawnSource.spawnedAgentTitle
    let title =
      (titleFromOutput?.isEmpty == false)
      ? (titleFromOutput ?? "Background agent")
      : (input?.summary.isEmpty == false ? input!.summary : "Background agent")
    let objective =
      (input?.details?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      ? (input?.details ?? "")
      : (input?.summary ?? "")
    let projection = SpawnedAgentPillProjection(
      pillID: pillId,
      sessionID: sessionId,
      runID: runId,
      title: title,
      objective: objective
    )

    // A repeat display event must still restore the matching notch pill if
    // its in-memory projection was evicted, but must not add a duplicate
    // transcript block.
    guard !alreadyPresent else { return projection }

    let stableSpawnIdentity = !runId.isEmpty ? runId : pillId.uuidString.lowercased()
    let spawnBlock = ChatContentBlock.agentSpawn(
      id: "agent_spawn_\(stableSpawnIdentity)",
      pillId: pillId,
      sessionId: sessionId,
      runId: runId,
      title: title,
      objective: objective
    )
    // Keep the tool block for in-session progress; insert structured spawn
    // immediately after it so reload/metadata durability has a first-class card.
    let insertAt = min(toolIndex + 1, blocks.count)
    blocks.insert(spawnBlock, at: insertAt)
    return projection
  }

  private func attachGeneratedFileResources(
    messageIndex index: Int,
    toolName: String,
    toolUseId: String?,
    extraTexts: [String]
  ) {
    let discoveredResources = localFileResources(
      fromToolName: toolName,
      texts: toolResourceCandidateTexts(
        in: messages[index].contentBlocks,
        toolName: toolName,
        toolUseId: toolUseId,
        extraTexts: extraTexts
      )
    )
    if !discoveredResources.isEmpty {
      messages[index].resources = mergedResources(
        existing: messages[index].resources,
        adding: discoveredResources
      )
    }
  }

  private func mergedResources(existing: [ChatResource], adding newResources: [ChatResource]) -> [ChatResource] {
    guard !newResources.isEmpty else { return existing }
    var seen = Set(existing.map(\.id))
    var merged = existing
    for resource in newResources where !seen.contains(resource.id) {
      seen.insert(resource.id)
      merged.append(resource)
    }
    return merged
  }

  private func toolResourceCandidateTexts(
    in blocks: [ChatContentBlock],
    toolName: String,
    toolUseId: String?,
    extraTexts: [String]
  ) -> [String] {
    let normalizedToolUseId = toolUseId?.isEmpty == false ? toolUseId : nil
    var texts = extraTexts
    for block in blocks {
      guard case .toolCall(_, let blockName, _, let blockToolUseId, let input, let output) = block else {
        continue
      }
      let idsMatch = normalizedToolUseId != nil && blockToolUseId == normalizedToolUseId
      let namesMatch = Self.normalizedToolNameHead(blockName) == Self.normalizedToolNameHead(toolName)
      guard idsMatch || (normalizedToolUseId == nil && namesMatch) else {
        continue
      }
      if let summary = input?.summary {
        texts.append(summary)
      }
      if let details = input?.details {
        texts.append(details)
      }
      if let output {
        texts.append(output)
      }
    }
    return texts
  }

  private func localFileResources(fromToolName name: String, texts: [String]) -> [ChatResource] {
    let normalizedName = Self.normalizedToolNameHead(name)
    guard ["write", "edit", "multiedit"].contains(normalizedName) else { return [] }
    return localFileURLs(from: texts.joined(separator: "\n")).map { url in
      let mimeType = mimeType(forLocalFile: url)
      return ChatResource.localGeneratedFile(
        id: "generated-file:\(url.path)",
        title: url.lastPathComponent,
        subtitle: localFileSubtitle(url: url, mimeType: mimeType),
        mimeType: mimeType,
        uri: url.absoluteString
      )
    }
  }

  private func localFileURLs(from output: String) -> [URL] {
    let pattern = #"(?:"file://)?(/[^\n"`]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
    var urls: [URL] = []
    var seen = Set<String>()
    for match in regex.matches(in: output, range: nsRange) {
      guard match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: output)
      else { continue }
      let rawPath = String(output[range])
        .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.。,:;)'\"]"))
      let url = URL(fileURLWithPath: rawPath)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        !isDirectory.boolValue,
        !seen.contains(url.path)
      else { continue }
      seen.insert(url.path)
      urls.append(url)
    }
    return urls
  }

  private static func normalizedToolNameHead(_ name: String) -> String {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.split(separator: ":", maxSplits: 1).first.map(String.init) ?? normalized
  }

  private func mimeType(forLocalFile url: URL) -> String {
    if let type = UTType(filenameExtension: url.pathExtension),
      let mime = type.preferredMIMEType
    {
      return mime
    }
    return "application/octet-stream"
  }

  private func localFileSubtitle(url: URL, mimeType: String) -> String {
    var parts = [mimeType]
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? NSNumber
    {
      parts.append(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))
    }
    return parts.joined(separator: " • ")
  }

  /// Append thinking text to the streaming message via the shared buffer.
  private func appendThinking(messageId: String, text: String) {
    streamingBuffer.appendThinking(messageId: messageId, text: text) { [weak self] in
      self?.flushStreamingBuffer()
    }
  }

  /// Mark any remaining in-flight tool call blocks as terminal in a message.
  /// Called when a query finishes (success or interrupt) so spinners don't spin forever.
  /// Matches `.running`, `.slow`, and `.stalled` (any state where `isInFlight` is true)
  /// so detector-promoted blocks resolve when the turn ends.
  private func completeRemainingToolCalls(
    messageId: String,
    terminalStatus: ToolCallStatus = .completed,
    scheduleJournal: Bool = true
  ) {
    streamingBuffer.completeRemainingToolCalls(
      messageId: messageId,
      terminalStatus: terminalStatus,
      messages: &messages,
      normalizeText: { message, text in
        if message.sender == .ai {
          return Self.normalizeAssistantSentenceSpacing(text)
        }
        return text
      }
    )
    if scheduleJournal {
      scheduleJournalUpdate(messageId: messageId)
    }
  }

  /// Monotonic millisecond timestamp for elapsed-time stall detection.
  /// Unlike wall-clock time, system uptime is unaffected by NTP or
  /// manual clock changes.
  nonisolated private static func monotonicNowMs() -> Int {
    Int(ProcessInfo.processInfo.systemUptime * 1000)
  }

  /// The key the `StallDetector` tracks a tool under. Tools that arrive
  /// without a real `toolUseId` fall back to a name-derived synthetic
  /// key so their per-tool timer still fires. Registration (in the tool
  /// activity handler) and the transition match in `applyStallTransitions`
  /// MUST derive the key identically — routing both through this single
  /// helper keeps them from diverging (a mismatch silently drops every
  /// stall transition for `toolUseId`-less tools).
  nonisolated static func stallTrackingId(toolUseId: String?, name: String) -> String {
    toolUseId ?? "untracked-\(name)"
  }

  nonisolated static func mapBridgeToolStatus(_ status: String) -> ToolCallStatus {
    ToolCallStatus.fromBridgeStatus(status)
  }

  /// Intentional user stops should not make in-flight tool rows look
  /// like execution errors. Real bridge failures still surface as failed.
  nonisolated static func remainingToolStatusAfterPartialResponseError(
    _ error: Error,
    watchdogFired: Bool = false,
    toolStallAbortFired: Bool = false,
    stopReason: ChatTurnStopReason? = nil
  ) -> ToolCallStatus {
    if watchdogFired || toolStallAbortFired || stopReason == .browserExtensionMissing {
      return .failed
    }
    if let bridgeError = error as? BridgeError, case .stopped = bridgeError {
      return .completed
    }
    return .failed
  }

  nonisolated static func lateResultToolStatus(
    watchdogFired: Bool,
    toolStallAbortFired: Bool,
    stopReason: ChatTurnStopReason? = nil
  ) -> ToolCallStatus {
    watchdogFired || toolStallAbortFired || stopReason == .browserExtensionMissing ? .failed : .completed
  }

  /// The banner text to show when a turn ends with `BridgeError.stopped`.
  /// A user-initiated Stop is silent (`nil`). But when the 60s send watchdog
  /// fired for the turn, the `.stopped` came from the watchdog's own interrupt —
  /// the turn timed out, so surface "Response took too long" rather than letting
  /// it vanish. Extracted so the watchdog-vs-user-stop distinction is unit-tested.
  nonisolated static func stoppedTurnErrorMessage(
    watchdogFired: Bool,
    toolStallAbortFired: Bool = false
  ) -> String? {
    if toolStallAbortFired {
      return "A tool stopped reporting progress. Try again."
    }
    return watchdogFired ? "Response took too long. Try again." : nil
  }

  /// Map a `StallDetector.State` to the matching `ToolCallStatus`.
  /// The two enums are deliberately separate — the detector tracks a
  /// 3-state lifecycle independent of UI/persistence concerns.
  private func mapDetectorState(_ state: StallDetector.State) -> ToolCallStatus {
    switch state {
    case .running: return .running
    case .slow: return .slow
    case .stalled: return .stalled
    }
  }

  /// Apply detector transitions to the message's tool-call blocks.
  /// Only `.tool(id:from:to:)` transitions are surfaced in the UI;
  /// `.interEvent` transitions are observed but not rendered here.
  private func applyStallTransitions(
    messageId: String,
    transitions: [StallDetector.Transition]
  ) {
    guard !transitions.isEmpty,
      let index = messages.firstIndex(where: { $0.id == messageId })
    else { return }

    for transition in transitions {
      guard case .tool(let id, _, let to) = transition else { continue }
      for i in messages[index].contentBlocks.indices {
        if case .toolCall(let blockId, let name, let oldStatus, let tuid, let input, let output) = messages[index]
          .contentBlocks[i],
          ChatProvider.stallTrackingId(toolUseId: tuid, name: name) == id,
          oldStatus.isInFlight
        {
          messages[index].contentBlocks[i] = .toolCall(
            id: blockId, name: name, status: mapDetectorState(to),
            toolUseId: tuid, input: input, output: output
          )
        }
      }
    }
    scheduleJournalUpdate(messageId: messageId, status: .streaming)
  }

  /// Re-resolve artifact cards whose persisted file paths are missing by asking the kernel.
  private func rehydrateMissingArtifactResourcesFromKernel() async {
    var runIds = Set<String>()
    for message in messages {
      for resource in message.resources where resource.artifactId != nil {
        guard let fileURL = resource.fileURL else {
          if let runId = resource.runId { runIds.insert(runId) }
          continue
        }
        if !FileManager.default.fileExists(atPath: fileURL.path),
          let runId = resource.runId
        {
          runIds.insert(runId)
        }
      }
    }
    guard !runIds.isEmpty else { return }

    var artifactsByRunId: [String: [String: AgentArtifactProjection]] = [:]
    for runId in runIds {
      guard let artifacts = try? await DesktopCoordinatorService.shared.inspectArtifactsForRun(runId: runId)
      else { continue }
      // Guard against duplicate artifact ids from the runtime (last-write-wins).
      artifactsByRunId[runId] = Dictionary(lastWriteWins: artifacts.map { ($0.artifactId, $0) })
    }
    guard !artifactsByRunId.isEmpty else { return }

    for messageIndex in messages.indices {
      var updatedResources = messages[messageIndex].resources
      var changed = false
      for resourceIndex in updatedResources.indices {
        let resource = updatedResources[resourceIndex]
        guard let artifactId = resource.artifactId,
          let runId = resource.runId,
          let artifact = artifactsByRunId[runId]?[artifactId]
        else { continue }

        let refreshed = resource.refreshedFromKernelArtifact(artifact)
        if refreshed != resource {
          updatedResources[resourceIndex] = refreshed
          changed = true
        }
      }
      if changed {
        messages[messageIndex].resources = updatedResources
        scheduleJournalUpdate(messageId: messages[messageIndex].id)
      }
    }
  }

  // MARK: - ChatErrorState recovery dispatch

  /// User tapped the primary CTA on a `ChatErrorCard`. Dispatches to
  /// the matching recovery action and clears `currentError`.
  ///
  /// Every `ChatErrorRecoveryAction` case is wired to a concrete
  /// handler. Implementations are deliberately minimal: each one
  /// performs the smallest useful action that points the user at the
  /// fix path.
  ///
  /// - `.retry`: re-issue the last failed prompt.
  /// - `.dismiss`: clear without further action.
  /// - `.signIn`: start the same desktop Google OAuth flow used by the
  ///   normal sign-in screen, then refresh account-scoped usage gates.
  /// - `.installRuntime`: open `https://nodejs.org/` so the user can
  ///   install Node before the bridge can spawn.
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

    let tracer = QueryTracer(query: trimmedQuery, inputMode: .text)
    tracer.captureRequest(
      systemPrompt: "Non-production owner-isolation kernel control probe.",
      messages: [["role": "user", "content": trimmedQuery]])
    tracer.begin("bridge_ensure", metadata: ["mode": "control_only_kernel_probe"])
    let runtime = AgentRuntimeProcess.shared
    let probeClientID = "owner-isolation-probe-\(UUID().uuidString.lowercased())"
    guard
      let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot(
        expectedOwnerID: trimmedOwnerB)
    else {
      tracer.end("bridge_ensure", metadata: ["error": "owner_authorization_missing"])
      tracer.finalize(tokenCount: 0, model: "kernel-control-probe")
      return ["error": "owner B authorization is unavailable"]
    }
    do {
      let surface = mainChatSurfaceReference()
      let receipt = try await OwnerIsolationKernelProbe.run(
        ownerID: trimmedOwnerB,
        query: trimmedQuery,
        response: "PROBE",
        registerControlOnlyRuntime: {
          try await runtime.registerClient(
            clientId: probeClientID,
            harnessMode: "piMono",
            authorizationSnapshot: authorization)
        },
        synchronizeOwner: {
          await runtime.refreshRuntimeOwner(
            expectedOwnerId: trimmedOwnerB,
            authorizationSnapshot: authorization)
        },
        resolveSurface: {
          let resolved = try await runtime.resolveSurfaceSession(
            clientId: probeClientID,
            surface: surface,
            title: nil,
            authorizationSnapshot: authorization)
          return (resolved.conversationId, resolved.sessionId)
        },
        recordExchange: { turns in
          try await runtime.recordJournalExchange(
            clientId: probeClientID,
            surface: surface,
            ownerID: trimmedOwnerB,
            turns: turns,
            authorizationSnapshot: authorization
          ).turns
        }
      )
      for turn in receipt.turns { projectJournalTurn(turn) }
      tracer.end("bridge_ensure")
      tracer.captureResponse(text: "PROBE")
      tracer.finalize(tokenCount: 0, model: "kernel-control-probe")
      currentError = nil
      errorMessage = nil
      await runtime.unregisterClient(clientId: probeClientID)

      var detail = automationMainChatSnapshot(limit: 20)
      detail["owner_a"] = ownerA
      detail["owner_b"] = trimmedOwnerB
      detail["probe_query"] = trimmedQuery
      detail["auth_user_id"] = UserDefaults.standard.string(forKey: .authUserId) ?? ""
      detail["owner_override"] = UserDefaults.standard.string(forKey: .automationOwnerOverride) ?? ""
      detail["conversation_id"] = receipt.conversationID
      detail["agent_session_id"] = receipt.sessionID
      return detail
    } catch {
      await runtime.unregisterClient(clientId: probeClientID)
      tracer.end("bridge_ensure", metadata: ["error": "kernel_control_probe_failed"])
      tracer.finalize(tokenCount: 0, model: "kernel-control-probe")
      return ["error": "owner B kernel probe failed: \(error.localizedDescription)"]
    }
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

  /// Snapshot for `main_chat_snapshot` / `wait_main_chat_idle` harness actions.
  func automationMainChatSnapshot(limit: Int) -> [String: String] {
    automationChatSnapshot(limit: limit)
  }

  /// Snapshot for the floating-bar chat. It intentionally returns the same
  /// canonical Omi chat timeline as main chat so typed notch, PTT, and
  /// spawned-agent links can be verified from either surface.
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
