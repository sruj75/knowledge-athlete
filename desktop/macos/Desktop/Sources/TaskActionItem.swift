import Foundation

enum LocalTaskPriority: String, CaseIterable, Codable, Sendable {
  case high
  case medium
  case low

  init?(input: String) {
    self.init(rawValue: input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}

enum LocalTaskRecurrence: String, CaseIterable, Codable, Sendable {
  case daily
  case weekdays
  case weekly
  case biweekly
  case monthly

  init?(input: String) {
    self.init(rawValue: input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}

enum TaskEvidenceKind: String, Codable, CaseIterable, Sendable {
  case conversation
  case memoryItem = "memory_item"
  case artifact
  case chatMessage = "chat_message"
  case localScreen = "local_screen"
  case external
  case unknown = "__unknown__"

  init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: rawValue) ?? .unknown
  }
}

enum TaskEvidenceScope: String, Codable, CaseIterable, Sendable {
  case canonical
  case deviceLocal = "device_local"
  case unknown = "__unknown__"

  init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: rawValue) ?? .unknown
  }
}

/// Typed local provenance retained after the task-intelligence wire API is removed.
struct TaskEvidenceRef: Codable, Equatable, Sendable {
  let deviceId: String?
  let excerptHash: String?
  let id: String
  let kind: TaskEvidenceKind
  let scope: TaskEvidenceScope
  let version: String?

  private enum CodingKeys: String, CodingKey {
    case deviceId = "device_id"
    case excerptHash = "excerpt_hash"
    case id
    case kind
    case scope
    case version
  }
}

/// Durable policy facts for an automatically captured task. They remain
/// internal provenance and are never rendered by the task details catch-all.
struct TaskCapturePolicyFacts: Codable, Equatable, Sendable {
  let captureKind: String?
  let owner: String?
  let concreteDeliverable: Bool?
  let publicBroadcast: Bool?
  let directMention: Bool?
  let ownershipConfidence: Double?

  private enum CodingKeys: String, CodingKey {
    case captureKind = "capture_kind"
    case owner
    case concreteDeliverable = "concrete_deliverable"
    case publicBroadcast = "public_broadcast"
    case directMention = "direct_mention"
    case ownershipConfidence = "ownership_confidence"
  }
}

struct StoredTaskProvenance: Codable, Equatable, Sendable {
  let evidence: [TaskEvidenceRef]
  let capturePolicy: TaskCapturePolicyFacts?

  private enum CodingKeys: String, CodingKey {
    case evidence
    case capturePolicy = "capture_policy"
  }
}

/// The one local task projection surfaced to product code.
///
/// Its identifier is always `local_<rowid>` from the current owner's GRDB
/// database. No server identity, synchronization state, generic metadata, rank,
/// task-agent, goal, or workstream fields exist in this shape.
struct TaskActionItem: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let description: String
  let completed: Bool
  let createdAt: Date
  let updatedAt: Date?
  let dueAt: Date?
  let completedAt: Date?
  let conversationId: String?
  let source: String?
  let priority: String?
  let deleted: Bool?
  let deletedBy: String?
  let recurrenceRule: String?
  let recurrenceParentId: String?
  let provenance: [TaskEvidenceRef]?
  var sortOrder: Int?
  let screenshotId: Int64?
  let confidence: Double?
  let sourceApp: String?
  let windowTitle: String?
  let contextSummary: String?
  let currentActivity: String?

  static func == (lhs: TaskActionItem, rhs: TaskActionItem) -> Bool {
    lhs.id == rhs.id && lhs.description == rhs.description && lhs.completed == rhs.completed
      && lhs.createdAt == rhs.createdAt && lhs.updatedAt == rhs.updatedAt && lhs.dueAt == rhs.dueAt
      && lhs.completedAt == rhs.completedAt && lhs.conversationId == rhs.conversationId
      && lhs.source == rhs.source && lhs.priority == rhs.priority && lhs.deleted == rhs.deleted
      && lhs.deletedBy == rhs.deletedBy && lhs.recurrenceRule == rhs.recurrenceRule
      && lhs.recurrenceParentId == rhs.recurrenceParentId && lhs.sortOrder == rhs.sortOrder
      && lhs.screenshotId == rhs.screenshotId && lhs.confidence == rhs.confidence
      && lhs.sourceApp == rhs.sourceApp && lhs.windowTitle == rhs.windowTitle
      && lhs.contextSummary == rhs.contextSummary && lhs.currentActivity == rhs.currentActivity
      && (lhs.provenance ?? []).count == (rhs.provenance ?? []).count
  }

  init(
    id: String,
    description: String,
    completed: Bool,
    createdAt: Date,
    updatedAt: Date? = nil,
    dueAt: Date? = nil,
    completedAt: Date? = nil,
    conversationId: String? = nil,
    source: String? = nil,
    priority: String? = nil,
    deleted: Bool? = nil,
    deletedBy: String? = nil,
    recurrenceRule: String? = nil,
    recurrenceParentId: String? = nil,
    provenance: [TaskEvidenceRef]? = nil,
    sortOrder: Int? = nil,
    screenshotId: Int64? = nil,
    confidence: Double? = nil,
    sourceApp: String? = nil,
    windowTitle: String? = nil,
    contextSummary: String? = nil,
    currentActivity: String? = nil
  ) {
    self.id = id
    self.description = description
    self.completed = completed
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.dueAt = dueAt
    self.completedAt = completedAt
    self.conversationId = conversationId
    self.source = source
    self.priority = priority
    self.deleted = deleted
    self.deletedBy = deletedBy
    self.recurrenceRule = recurrenceRule
    self.recurrenceParentId = recurrenceParentId
    self.provenance = provenance
    self.sortOrder = sortOrder
    self.screenshotId = screenshotId
    self.confidence = confidence
    self.sourceApp = sourceApp
    self.windowTitle = windowTitle
    self.contextSummary = contextSummary
    self.currentActivity = currentActivity
  }

  var isRecurring: Bool {
    guard let recurrenceRule else { return false }
    return !recurrenceRule.isEmpty
  }

  var isRetired: Bool { deleted == true }

  var hasDetailMetadata: Bool {
    (source != nil && source != "manual") || sourceApp != nil || windowTitle != nil || confidence != nil
      || contextSummary != nil || currentActivity != nil || !(provenance ?? []).isEmpty
  }

  var sourceLabel: String {
    switch source {
    case "screenshot": return "Screen"
    case "transcription:omi": return "omi"
    case "transcription:desktop": return "Desktop"
    case "transcription:phone": return "Phone"
    case "manual": return "Manual"
    case "recurring": return "Recurring"
    default: return "Task"
    }
  }

  var sourceAppLabel: String {
    if source == "screenshot", let sourceApp { return sourceApp }
    return sourceLabel
  }

  var sourceIcon: String {
    switch source {
    case "screenshot": return "camera.fill"
    case "transcription:omi": return "waveform"
    case "transcription:desktop": return "desktopcomputer"
    case "transcription:phone": return "iphone"
    case "manual": return "square.and.pencil"
    case "recurring": return "repeat"
    default: return "list.bullet"
    }
  }

  /// Explicit retained fields only. Raw local relationship IDs stay private.
  var chatContext: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    var lines = ["Task: \(description)", "Status: \(completed ? "completed" : "active")"]
    if let priority { lines.append("Priority: \(priority)") }
    lines.append("Created: \(formatter.string(from: createdAt))")
    if let dueAt { lines.append("Due: \(formatter.string(from: dueAt))") }
    if let completedAt { lines.append("Completed: \(formatter.string(from: completedAt))") }
    if let source { lines.append("Source: \(sourceLabel) (\(source))") }
    if let sourceApp { lines.append("Source app: \(sourceApp)") }
    if let windowTitle { lines.append("Window title: \(windowTitle)") }
    if let confidence { lines.append("Extraction confidence: \(Int(confidence * 100))%") }
    if let contextSummary, !contextSummary.isEmpty { lines.append("Context when detected: \(contextSummary)") }
    if let currentActivity, !currentActivity.isEmpty { lines.append("User activity: \(currentActivity)") }
    let evidenceCount = (provenance ?? []).count
    if evidenceCount > 0 { lines.append("Linked evidence count: \(evidenceCount)") }
    return lines.joined(separator: "\n")
  }
}
