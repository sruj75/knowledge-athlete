import Foundation
@preconcurrency import GRDB

/// Storage manager for Focus sessions and task-deduplication audit rows.
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

/// Errors for ProactiveStorage operations
enum ProactiveStorageError: LocalizedError {
  case databaseNotInitialized

  var errorDescription: String? {
    switch self {
    case .databaseNotInitialized:
      return "Proactive storage database is not initialized"
    }
  }
}
