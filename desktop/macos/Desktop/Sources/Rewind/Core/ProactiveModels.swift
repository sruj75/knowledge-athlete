import Foundation
@preconcurrency import GRDB

// MARK: - Focus Session Record

/// Database record for focus tracking sessions
struct FocusSessionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  var id: Int64?
  var screenshotId: Int64?
  var status: String  // "focused" or "distracted"
  var appOrSite: String
  var windowTitle: String?
  var description: String
  var message: String?
  var durationSeconds: Int?
  var createdAt: Date

  static let databaseTableName = "focus_sessions"

  // MARK: - Initialization

  init(
    id: Int64? = nil,
    screenshotId: Int64? = nil,
    status: String,
    appOrSite: String,
    windowTitle: String? = nil,
    description: String,
    message: String? = nil,
    durationSeconds: Int? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.screenshotId = screenshotId
    self.status = status
    self.appOrSite = appOrSite
    self.windowTitle = windowTitle
    self.description = description
    self.message = message
    self.durationSeconds = durationSeconds
    self.createdAt = createdAt
  }

  // MARK: - Persistence Callbacks

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }

  // MARK: - Computed Properties

  var isFocused: Bool {
    status == "focused"
  }

  var isDistracted: Bool {
    status == "distracted"
  }

  // MARK: - Relationships

  static let screenshot = belongsTo(Screenshot.self)

  var screenshot: QueryInterfaceRequest<Screenshot> {
    request(for: FocusSessionRecord.screenshot)
  }
}

// MARK: - Task Dedup Log Record

/// Database record for AI-driven task deduplication deletions
struct TaskDedupLogRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  var id: Int64?
  var deletedTaskId: String
  var deletedDescription: String
  var keptTaskId: String
  var keptDescription: String
  var reason: String
  var deletedAt: Date

  static let databaseTableName = "task_dedup_log"

  init(
    id: Int64? = nil,
    deletedTaskId: String,
    deletedDescription: String,
    keptTaskId: String,
    keptDescription: String,
    reason: String,
    deletedAt: Date = Date()
  ) {
    self.id = id
    self.deletedTaskId = deletedTaskId
    self.deletedDescription = deletedDescription
    self.keptTaskId = keptTaskId
    self.keptDescription = keptDescription
    self.reason = reason
    self.deletedAt = deletedAt
  }

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

// MARK: - Screenshot Extensions for Relationships

extension Screenshot {
  static let focusSessions = hasMany(FocusSessionRecord.self)

  var focusSessions: QueryInterfaceRequest<FocusSessionRecord> {
    request(for: Screenshot.focusSessions)
  }
}

// MARK: - TableDocumented

extension FocusSessionRecord: TableDocumented {
  static var tableDescription: String { ChatPrompts.tableAnnotations["focus_sessions"]! }
  static var columnDescriptions: [String: String] { ChatPrompts.columnAnnotations["focus_sessions"] ?? [:] }
}

// MARK: - Focus Session with Screenshot

/// Combined focus session and screenshot data for UI display
struct FocusSessionWithScreenshot {
  let session: FocusSessionRecord
  let screenshot: Screenshot?

  var imagePath: String? {
    screenshot?.imagePath
  }

  var screenshotTimestamp: Date? {
    screenshot?.timestamp
  }
}
