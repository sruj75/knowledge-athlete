import Foundation
@preconcurrency import GRDB

/// Durable local task row. The containing per-owner database supplies the owner
/// boundary; the row ID supplies the only task identity.
struct ActionItemRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
  var id: Int64?
  var description: String
  var completed: Bool
  var deleted: Bool
  var source: String?
  var conversationId: String?
  var priority: String?
  var deletedBy: String?
  var deletedAt: Date?
  var dueAt: Date?
  var completedAt: Date?
  var recurrenceRule: String?
  var recurrenceParentId: String?
  var provenanceJson: String?
  var screenshotId: Int64?
  var confidence: Double?
  var sourceApp: String?
  var windowTitle: String?
  var contextSummary: String?
  var currentActivity: String?
  var embedding: Data?
  var sortOrder: Int?
  var createdAt: Date
  var updatedAt: Date

  static let databaseTableName = "action_items"

  init(
    id: Int64? = nil,
    description: String,
    completed: Bool = false,
    deleted: Bool = false,
    source: String? = nil,
    conversationId: String? = nil,
    priority: String? = nil,
    deletedBy: String? = nil,
    deletedAt: Date? = nil,
    dueAt: Date? = nil,
    completedAt: Date? = nil,
    recurrenceRule: String? = nil,
    recurrenceParentId: String? = nil,
    provenanceJson: String? = nil,
    screenshotId: Int64? = nil,
    confidence: Double? = nil,
    sourceApp: String? = nil,
    windowTitle: String? = nil,
    contextSummary: String? = nil,
    currentActivity: String? = nil,
    embedding: Data? = nil,
    sortOrder: Int? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.description = description
    self.completed = completed
    self.deleted = deleted
    self.source = source
    self.conversationId = conversationId
    self.priority = priority
    self.deletedBy = deletedBy
    self.deletedAt = deletedAt
    self.dueAt = dueAt
    self.completedAt = completedAt
    self.recurrenceRule = recurrenceRule
    self.recurrenceParentId = recurrenceParentId
    self.provenanceJson = provenanceJson
    self.screenshotId = screenshotId
    self.confidence = confidence
    self.sourceApp = sourceApp
    self.windowTitle = windowTitle
    self.contextSummary = contextSummary
    self.currentActivity = currentActivity
    self.embedding = embedding
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }

  static let screenshot = belongsTo(Screenshot.self)
  var screenshot: QueryInterfaceRequest<Screenshot> { request(for: Self.screenshot) }

  func toActionItem() -> ActionItem {
    ActionItem(description: description, completed: completed, deleted: deleted)
  }

  func toTaskActionItem() -> TaskActionItem {
    TaskActionItem(
      id: "local_\(id ?? 0)",
      description: description,
      completed: completed,
      createdAt: createdAt,
      updatedAt: updatedAt,
      dueAt: dueAt,
      completedAt: completedAt,
      conversationId: conversationId,
      source: source,
      priority: priority,
      deleted: deleted,
      deletedBy: deletedBy,
      recurrenceRule: recurrenceRule,
      recurrenceParentId: recurrenceParentId,
      provenance: Self.decodeEvidence(provenanceJson),
      sortOrder: sortOrder,
      screenshotId: screenshotId,
      confidence: confidence,
      sourceApp: sourceApp,
      windowTitle: windowTitle,
      contextSummary: contextSummary,
      currentActivity: currentActivity
    )
  }

  private static func decodeEvidence(_ json: String?) -> [TaskEvidenceRef]? {
    guard let data = json?.data(using: .utf8) else { return nil }
    if let envelope = try? JSONDecoder().decode(StoredTaskProvenance.self, from: data) {
      return envelope.evidence
    }
    return try? JSONDecoder().decode([TaskEvidenceRef].self, from: data)
  }
}

extension ActionItemRecord: TableDocumented {
  static var tableDescription: String { ChatPrompts.tableAnnotations["action_items"]! }
  static var columnDescriptions: [String: String] { ChatPrompts.columnAnnotations["action_items"] ?? [:] }
}

enum ActionItemStorageError: LocalizedError {
  case databaseNotInitialized
  case recordNotFound
  case invalidPriority
  case invalidRecurrence

  var errorDescription: String? {
    switch self {
    case .databaseNotInitialized: return "Action item storage database is not initialized"
    case .recordNotFound: return "Action item record not found"
    case .invalidPriority: return "Task priority must be High, Medium, or Low"
    case .invalidRecurrence: return "Task recurrence is not supported"
    }
  }
}
