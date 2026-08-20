import Foundation
@preconcurrency import GRDB

/// Unified storage manager for all proactive assistant data (memories, tasks, advice, focus sessions)
/// Uses SQLite for local persistence with backend sync
actor ProactiveStorage {
  static let shared = ProactiveStorage()

  private var _dbQueue: DatabasePool?
  private var _dbGeneration = -1
  private var isInitialized = false

  private init() {}

  /// Invalidate cached DB queue (called on user switch / sign-out)
  func invalidateCache() {
    _dbQueue = nil
    isInitialized = false
  }

  /// Ensure database is initialized before use
  private func ensureInitialized() async throws -> DatabasePool {
    if let db = _dbQueue, await RewindDatabase.shared.poolGeneration() == _dbGeneration {
      return db
    }

    // Initialize RewindDatabase which creates our tables via migrations
    do {
      try await RewindDatabase.shared.initialize()
    } catch {
      log("ProactiveStorage: Database initialization failed: \(error.localizedDescription)")
      throw error
    }

    let (queue, generation) = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    guard let db = queue else {
      throw ProactiveStorageError.databaseNotInitialized
    }

    _dbQueue = db
    _dbGeneration = generation
    isInitialized = true
    return db
  }

  // MARK: - Extraction Operations (Memory, Task, Advice)

  /// Insert a new extraction record
  @discardableResult
  func insertExtraction(_ extraction: ProactiveExtractionRecord) async throws -> ProactiveExtractionRecord {
    let db = try await ensureInitialized()

    let record = try await db.write { database in
      try extraction.inserted(database)
    }
    log("ProactiveStorage: Inserted \(extraction.type.rawValue) extraction (id: \(record.id ?? -1))")
    return record
  }

  /// Get extractions by type
  func getExtractions(
    type: ExtractionType,
    limit: Int = 100,
    offset: Int = 0,
    includeDismissed: Bool = false
  ) async throws -> [ProactiveExtractionRecord] {
    let db = try await ensureInitialized()

    return try await db.read { database in
      var query =
        ProactiveExtractionRecord
        .filter(Column("type") == type.rawValue)

      if !includeDismissed {
        query = query.filter(Column("isDismissed") == false)
      }

      return
        try query
        .order(Column("createdAt").desc)
        .limit(limit, offset: offset)
        .fetchAll(database)
    }
  }

  /// Get extraction by ID
  func getExtraction(id: Int64) async throws -> ProactiveExtractionRecord? {
    let db = try await ensureInitialized()

    return try await db.read { database in
      try ProactiveExtractionRecord.fetchOne(database, key: id)
    }
  }

  /// Get extraction with its screenshot
  func getExtractionWithScreenshot(id: Int64) async throws -> ExtractionWithScreenshot? {
    let db = try await ensureInitialized()

    return try await db.read { database in
      guard let extraction = try ProactiveExtractionRecord.fetchOne(database, key: id) else {
        return nil
      }

      let screenshot: Screenshot?
      if let screenshotId = extraction.screenshotId {
        screenshot = try Screenshot.fetchOne(database, key: screenshotId)
      } else {
        screenshot = nil
      }

      return ExtractionWithScreenshot(extraction: extraction, screenshot: screenshot)
    }
  }

  /// Get extractions with their screenshots
  func getExtractionsWithScreenshots(
    type: ExtractionType,
    limit: Int = 100,
    includeDismissed: Bool = false
  ) async throws -> [ExtractionWithScreenshot] {
    let db = try await ensureInitialized()

    return try await db.read { database in
      var query =
        ProactiveExtractionRecord
        .filter(Column("type") == type.rawValue)

      if !includeDismissed {
        query = query.filter(Column("isDismissed") == false)
      }

      let extractions =
        try query
        .order(Column("createdAt").desc)
        .limit(limit)
        .fetchAll(database)

      return try extractions.map { extraction in
        let screenshot: Screenshot?
        if let screenshotId = extraction.screenshotId {
          screenshot = try Screenshot.fetchOne(database, key: screenshotId)
        } else {
          screenshot = nil
        }
        return ExtractionWithScreenshot(extraction: extraction, screenshot: screenshot)
      }
    }
  }

  /// Update extraction
  func updateExtraction(id: Int64, updates: ExtractionUpdate) async throws {
    let db = try await ensureInitialized()

    try await db.write { database in
      guard var record = try ProactiveExtractionRecord.fetchOne(database, key: id) else {
        throw ProactiveStorageError.recordNotFound
      }

      if let content = updates.content {
        record.content = content
      }
      if let isRead = updates.isRead {
        record.isRead = isRead
      }
      if let isDismissed = updates.isDismissed {
        record.isDismissed = isDismissed
      }
      if let backendId = updates.backendId {
        record.backendId = backendId
      }
      if let backendSynced = updates.backendSynced {
        record.backendSynced = backendSynced
      }

      record.updatedAt = Date()
      try record.update(database)
    }
  }

  /// Mark extraction as read
  func markExtractionAsRead(id: Int64) async throws {
    try await updateExtraction(id: id, updates: ExtractionUpdate(isRead: true))
  }

  /// Mark all extractions of a type as read
  func markAllExtractionsAsRead(type: ExtractionType) async throws {
    let db = try await ensureInitialized()

    try await db.write { database in
      try database.execute(
        sql: "UPDATE proactive_extractions SET isRead = 1, updatedAt = ? WHERE type = ? AND isRead = 0",
        arguments: [Date(), type.rawValue]
      )
    }
  }

  /// Dismiss extraction (hide from list)
  func dismissExtraction(id: Int64) async throws {
    try await updateExtraction(id: id, updates: ExtractionUpdate(isDismissed: true))
  }

  /// Delete extraction
  func deleteExtraction(id: Int64) async throws {
    let db = try await ensureInitialized()

    try await db.write { database in
      try database.execute(
        sql: "DELETE FROM proactive_extractions WHERE id = ?",
        arguments: [id]
      )
    }
  }

  /// Get unsynced extractions
  func getUnsyncedExtractions(type: ExtractionType? = nil) async throws -> [ProactiveExtractionRecord] {
    let db = try await ensureInitialized()

    return try await db.read { database in
      var query =
        ProactiveExtractionRecord
        .filter(Column("backendSynced") == false)

      if let type = type {
        query = query.filter(Column("type") == type.rawValue)
      }

      return try query.fetchAll(database)
    }
  }

  /// Get unread count for a type
  func getUnreadCount(type: ExtractionType) async throws -> Int {
    let db = try await ensureInitialized()

    return try await db.read { database in
      try Int.fetchOne(
        database,
        sql: "SELECT COUNT(*) FROM proactive_extractions WHERE type = ? AND isRead = 0 AND isDismissed = 0",
        arguments: [type.rawValue]
      ) ?? 0
    }
  }

  /// Search extractions by content
  func searchExtractions(query: String, type: ExtractionType? = nil, limit: Int = 50) async throws
    -> [ProactiveExtractionRecord]
  {
    let db = try await ensureInitialized()

    return try await db.read { database in
      var sql = """
        SELECT proactive_extractions.* FROM proactive_extractions
        JOIN proactive_extractions_fts ON proactive_extractions.id = proactive_extractions_fts.rowid
        WHERE proactive_extractions_fts MATCH ?
        """
      var arguments: [DatabaseValueConvertible] = [query + "*"]

      if let type = type {
        sql += " AND proactive_extractions.type = ?"
        arguments.append(type.rawValue)
      }

      sql += " ORDER BY proactive_extractions.createdAt DESC LIMIT ?"
      arguments.append(limit)

      return try ProactiveExtractionRecord.fetchAll(database, sql: sql, arguments: StatementArguments(arguments))
    }
  }

  // MARK: - Focus Session Operations

  /// Insert a new focus session
  @discardableResult
  func insertFocusSession(
    _ session: FocusSessionRecord,
    authorization: LocalMutationAuthorization
  ) async throws -> FocusSessionRecord {
    try authorization.require()
    let db = try await ensureInitialized()

    let record = try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        let inserted = try session.inserted(database)
        try Self.pruneFocusSessions(in: database, now: Date())
        try authorization.require()
        return inserted
      }
    }
    log("ProactiveStorage: Inserted focus session (id: \(record.id ?? -1), status: \(session.status))")
    return record
  }

  /// Enforce the Focus retention contract even when no new session is admitted.
  /// This makes a startup/refresh repair stale rows left by older app versions.
  func pruneFocusSessions(
    now: Date = Date(),
    authorization: LocalMutationAuthorization
  ) async throws {
    try authorization.require()
    let db = try await ensureInitialized()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try Self.pruneFocusSessions(in: database, now: now)
        try authorization.require()
      }
    }
  }

  private static func pruneFocusSessions(in database: Database, now: Date) throws {
    let retentionCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
    try database.execute(
      sql: "DELETE FROM focus_sessions WHERE createdAt < ?",
      arguments: [retentionCutoff]
    )
    try database.execute(
      sql: """
        DELETE FROM focus_sessions
        WHERE id NOT IN (
          SELECT id FROM focus_sessions
          ORDER BY createdAt DESC, id DESC
          LIMIT 500
        )
        """)
  }

  /// Get focus sessions for a date range
  func getFocusSessions(from startDate: Date, to endDate: Date, limit: Int = 500) async throws -> [FocusSessionRecord] {
    let db = try await ensureInitialized()

    return try await db.read { database in
      try FocusSessionRecord
        .filter(Column("createdAt") >= startDate && Column("createdAt") <= endDate)
        .order(Column("createdAt").desc)
        .limit(limit)
        .fetchAll(database)
    }
  }

  /// Get today's focus sessions
  func getTodayFocusSessions() async throws -> [FocusSessionRecord] {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: Date())
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

    return try await getFocusSessions(from: startOfDay, to: endOfDay)
  }

  /// Get total count of all focus sessions
  func getTotalFocusSessionCount() async throws -> Int {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try FocusSessionRecord.fetchCount(database)
    }
  }

  /// Delete focus session
  func deleteFocusSession(
    id: Int64,
    authorization: LocalMutationAuthorization
  ) async throws {
    try authorization.require()
    let db = try await ensureInitialized()

    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: "DELETE FROM focus_sessions WHERE id = ?",
          arguments: [id]
        )
        try authorization.require()
      }
    }
  }

  /// Delete the complete Focus history for the current local owner.
  func clearFocusSessions(authorization: LocalMutationAuthorization) async throws {
    try authorization.require()
    let db = try await ensureInitialized()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(sql: "DELETE FROM focus_sessions")
        try authorization.require()
      }
    }
  }

  /// Get most recent focus session
  func getMostRecentFocusSession() async throws -> FocusSessionRecord? {
    let db = try await ensureInitialized()

    return try await db.read { database in
      try FocusSessionRecord
        .order(Column("createdAt").desc)
        .limit(1)
        .fetchOne(database)
    }
  }

  // MARK: - Task Dedup Log

  /// Insert a dedup log record tracking an AI-driven task deletion
  @discardableResult
  func insertDedupLogRecord(_ record: TaskDedupLogRecord) async throws -> TaskDedupLogRecord {
    let db = try await ensureInitialized()

    let inserted = try await db.write { database in
      try record.inserted(database)
    }
    log("ProactiveStorage: Inserted dedup log (deleted: \(record.deletedTaskId), kept: \(record.keptTaskId))")
    return inserted
  }

  /// Get dedup log records for review
  func getDedupLogRecords(limit: Int = 100, offset: Int = 0) async throws -> [TaskDedupLogRecord] {
    let db = try await ensureInitialized()

    return try await db.read { database in
      try TaskDedupLogRecord
        .order(Column("deletedAt").desc)
        .limit(limit, offset: offset)
        .fetchAll(database)
    }
  }

  // MARK: - Cleanup

  /// Delete old extractions (for data retention)
  func deleteExtractionsOlderThan(_ date: Date) async throws -> Int {
    let db = try await ensureInitialized()

    return try await db.write { database in
      let count =
        try Int.fetchOne(
          database,
          sql: "SELECT COUNT(*) FROM proactive_extractions WHERE createdAt < ?",
          arguments: [date]
        ) ?? 0

      try database.execute(
        sql: "DELETE FROM proactive_extractions WHERE createdAt < ?",
        arguments: [date]
      )

      return count
    }
  }

  /// Delete old focus sessions (for data retention)
  func deleteFocusSessionsOlderThan(_ date: Date) async throws -> Int {
    let db = try await ensureInitialized()

    return try await db.write { database in
      let count =
        try Int.fetchOne(
          database,
          sql: "SELECT COUNT(*) FROM focus_sessions WHERE createdAt < ?",
          arguments: [date]
        ) ?? 0

      try database.execute(
        sql: "DELETE FROM focus_sessions WHERE createdAt < ?",
        arguments: [date]
      )

      return count
    }
  }
}

// MARK: - Supporting Types

/// Update parameters for extractions
struct ExtractionUpdate {
  var content: String?
  var isRead: Bool?
  var isDismissed: Bool?
  var backendId: String?
  var backendSynced: Bool?
}

/// Errors for ProactiveStorage operations
enum ProactiveStorageError: LocalizedError {
  case databaseNotInitialized
  case recordNotFound
  case syncFailed(String)

  var errorDescription: String? {
    switch self {
    case .databaseNotInitialized:
      return "Proactive storage database is not initialized"
    case .recordNotFound:
      return "Record not found"
    case .syncFailed(let message):
      return "Sync failed: \(message)"
    }
  }
}
