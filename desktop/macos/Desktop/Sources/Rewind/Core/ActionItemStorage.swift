import Foundation
@preconcurrency import GRDB

/// Sole durable authority for tasks in the current owner's database.
actor ActionItemStorage {
  static let shared = ActionItemStorage()

  private var dbQueue: DatabasePool?
  private var dbGeneration = -1

  private init() {}

  static func localRowID(surfacedId: String) -> Int64? {
    guard surfacedId.hasPrefix("local_"), let rowID = Int64(surfacedId.dropFirst(6)), rowID > 0 else {
      return nil
    }
    return rowID
  }

  static func fetchRecord(_ database: Database, surfacedId: String) throws -> ActionItemRecord? {
    guard let rowID = localRowID(surfacedId: surfacedId) else { return nil }
    return try ActionItemRecord.fetchOne(database, key: rowID)
  }

  func invalidateCache() {
    dbQueue = nil
    dbGeneration = -1
  }

  private func ensureInitialized() async throws -> DatabasePool {
    if let dbQueue, await RewindDatabase.shared.poolGeneration() == dbGeneration { return dbQueue }
    try await RewindDatabase.shared.initialize()
    let (queue, generation) = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    guard let queue else { throw ActionItemStorageError.databaseNotInitialized }
    dbQueue = queue
    dbGeneration = generation
    return queue
  }

  private static func normalizedPriority(_ value: String?) throws -> String? {
    guard let value else { return nil }
    guard let priority = LocalTaskPriority(input: value) else {
      throw ActionItemStorageError.invalidPriority
    }
    return priority.rawValue
  }

  private static func normalizedRecurrence(_ value: String?) throws -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let recurrence = LocalTaskRecurrence(input: trimmed) else {
      throw ActionItemStorageError.invalidRecurrence
    }
    return recurrence.rawValue
  }

  private static func normalizedForWrite(_ record: ActionItemRecord) throws -> ActionItemRecord {
    var normalized = record
    normalized.priority = try normalizedPriority(record.priority)
    normalized.recurrenceRule = try normalizedRecurrence(record.recurrenceRule)
    return normalized
  }

  // MARK: Reads

  func getLocalActionItems(
    limit: Int = 50,
    offset: Int = 0,
    completed: Bool? = nil,
    includeDeleted: Bool = false,
    startDate: Date? = nil
  ) async throws -> [TaskActionItem] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      var request = ActionItemRecord.all()
      if !includeDeleted { request = request.filter(Column("deleted") == false) }
      if let completed { request = request.filter(Column("completed") == completed) }
      if let startDate { request = request.filter(Column("createdAt") >= startDate) }
      return
        try request
        .order(Column("sortOrder").ascNullsLast, Column("dueAt").ascNullsLast, Column("createdAt").desc)
        .limit(max(0, limit), offset: max(0, offset))
        .fetchAll(database)
        .map { $0.toTaskActionItem() }
    }
  }

  func getFilteredActionItems(
    limit: Int = 200,
    offset: Int = 0,
    completedStates: [Bool]? = nil,
    includeDeleted: Bool = false,
    dueDateAfter: Date? = nil,
    dueDateBefore: Date? = nil,
    dueDateIsNull: Bool? = nil,
    createdAfter: Date? = nil,
    createdBefore: Date? = nil
  ) async throws -> [TaskActionItem] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      var request = ActionItemRecord.all()
      if !includeDeleted { request = request.filter(Column("deleted") == false) }
      if let completedStates, completedStates.count == 1 {
        request = request.filter(Column("completed") == completedStates[0])
      }
      if let dueDateAfter { request = request.filter(Column("dueAt") >= dueDateAfter) }
      if let dueDateBefore { request = request.filter(Column("dueAt") < dueDateBefore) }
      if let dueDateIsNull {
        request =
          dueDateIsNull
          ? request.filter(Column("dueAt") == nil)
          : request.filter(Column("dueAt") != nil)
      }
      if let createdAfter { request = request.filter(Column("createdAt") >= createdAfter) }
      if let createdBefore { request = request.filter(Column("createdAt") < createdBefore) }
      return
        try request
        .order(Column("sortOrder").ascNullsLast, Column("dueAt").ascNullsLast, Column("createdAt").desc)
        .limit(max(0, limit), offset: max(0, offset))
        .fetchAll(database)
        .map { $0.toTaskActionItem() }
    }
  }

  func getLocalActionItemsCount(
    completed: Bool? = nil,
    includeDeleted: Bool = false,
    startDate: Date? = nil
  ) async throws -> Int {
    let db = try await ensureInitialized()
    return try await db.read { database in
      var request = ActionItemRecord.all()
      if !includeDeleted { request = request.filter(Column("deleted") == false) }
      if let completed { request = request.filter(Column("completed") == completed) }
      if let startDate { request = request.filter(Column("createdAt") >= startDate) }
      return try request.fetchCount(database)
    }
  }

  /// Complete, deterministic, owner-scoped page for S-08's offline export
  /// composition. Deleted rows are intentionally omitted from user data export.
  func getLocalExportPage(limit: Int = 100, offset: Int = 0) async throws -> [TaskActionItem] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try ActionItemRecord
        .filter(Column("deleted") == false)
        .order(Column("createdAt").asc, Column("id").asc)
        .limit(max(0, limit), offset: max(0, offset))
        .fetchAll(database)
        .map { $0.toTaskActionItem() }
    }
  }

  func getFilterCounts() async throws -> (todo: Int, done: Int, deleted: Int) {
    let db = try await ensureInitialized()
    return try await db.read { database in
      let todo = try ActionItemRecord.filter(Column("deleted") == false && Column("completed") == false)
        .fetchCount(database)
      let done = try ActionItemRecord.filter(Column("deleted") == false && Column("completed") == true)
        .fetchCount(database)
      let deleted = try ActionItemRecord.filter(Column("deleted") == true).fetchCount(database)
      return (todo, done, deleted)
    }
  }

  func getActionItem(id: Int64) async throws -> ActionItemRecord? {
    let db = try await ensureInitialized()
    return try await db.read { try ActionItemRecord.fetchOne($0, key: id) }
  }

  func getLocalActionItem(surfacedId: String) async throws -> TaskActionItem? {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try Self.fetchRecord(database, surfacedId: surfacedId)?.toTaskActionItem()
    }
  }

  func actionItemExists(description: String) async -> Bool {
    guard let db = try? await ensureInitialized() else { return false }
    let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
    return
      (try? await db.read { database in
        try Bool.fetchOne(
          database,
          sql: "SELECT EXISTS(SELECT 1 FROM action_items WHERE deleted = 0 AND lower(trim(description)) = lower(?))",
          arguments: [normalized]
        ) ?? false
      }) ?? false
  }

  func searchDescriptions(query: String, limit: Int = 100, offset: Int = 0) async throws -> [TaskActionItem] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return [] }
    let db = try await ensureInitialized()
    return try await db.read { database in
      try ActionItemRecord
        .filter(Column("deleted") == false)
        .filter(Column("description").like("%\(normalized)%"))
        .order(Column("sortOrder").ascNullsLast, Column("dueAt").ascNullsLast, Column("createdAt").desc)
        .limit(max(0, limit), offset: max(0, offset))
        .fetchAll(database)
        .map { $0.toTaskActionItem() }
    }
  }

  func searchFTS(
    query: String,
    limit: Int = 20,
    includeCompleted: Bool = true,
    includeDeleted: Bool = false
  ) async throws -> [(id: Int64, description: String, completed: Bool, deleted: Bool, deletedBy: String?)] {
    let characters = query.map { $0.isLetter || $0.isNumber || $0 == "*" || $0 == " " ? $0 : " " }
    let sanitized = String(characters).split(separator: " ").map(String.init).joined(separator: " ")
    guard !sanitized.isEmpty else { return [] }
    let db = try await ensureInitialized()
    return try await db.read { database in
      var sql = """
        SELECT a.id, a.description, a.completed, a.deleted, a.deletedBy
        FROM action_items a JOIN action_items_fts fts ON fts.rowid = a.id
        WHERE action_items_fts MATCH ?
        """
      if !includeCompleted { sql += " AND a.completed = 0" }
      if !includeDeleted { sql += " AND a.deleted = 0" }
      sql += " ORDER BY bm25(action_items_fts), a.createdAt DESC LIMIT ?"
      return try Row.fetchAll(database, sql: sql, arguments: [sanitized, max(0, limit)]).map { row in
        (row["id"], row["description"], row["completed"], row["deleted"], row["deletedBy"])
      }
    }
  }

  func getRecentActiveTasks(limit: Int = 30) async throws -> [(id: Int64, description: String, priority: String?)] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql: """
          SELECT id, description, priority FROM action_items
          WHERE completed = 0 AND deleted = 0
          ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 3 END,
                   dueAt IS NULL, dueAt, sortOrder IS NULL, sortOrder, createdAt DESC
          LIMIT ?
          """,
        arguments: [max(0, limit)]
      ).map { ($0["id"], $0["description"], $0["priority"]) }
    }
  }

  func getRecentCompletedTasks(limit: Int = 10) async throws -> [(id: Int64, description: String)] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql:
          "SELECT id, description FROM action_items WHERE completed = 1 AND deleted = 0 ORDER BY completedAt DESC, updatedAt DESC LIMIT ?",
        arguments: [max(0, limit)]
      ).map { ($0["id"], $0["description"]) }
    }
  }

  func getRecentDeletedTasks(limit: Int = 10, deletedBy: String? = "user") async throws -> [(
    id: Int64, description: String
  )] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      var request = ActionItemRecord.filter(Column("deleted") == true)
      if let deletedBy { request = request.filter(Column("deletedBy") == deletedBy) }
      return try request.order(Column("deletedAt").desc, Column("updatedAt").desc)
        .limit(max(0, limit)).fetchAll(database)
        .compactMap { record in record.id.map { ($0, record.description) } }
    }
  }

  // MARK: Writes

  @discardableResult
  func insertLocalActionItem(
    _ record: ActionItemRecord,
    authorization: LocalMutationAuthorization
  ) async throws -> ActionItemRecord {
    try authorization.require()
    let db = try await ensureInitialized()
    let recordToInsert = try Self.normalizedForWrite(record)
    let inserted = try await authorization.withCommitLease {
      do {
        return try await db.write { database in
          try authorization.require()
          let inserted = try recordToInsert.inserted(database)
          try authorization.require()
          return inserted
        }
      } catch {
        guard await RewindDatabase.shared.isActionItemsFTSError(error) else { throw error }
        try authorization.require()
        try await RewindDatabase.shared.repairActionItemsFTS(in: db, reason: "insertLocalActionItem")
        return try await db.write { database in
          try authorization.require()
          return try recordToInsert.inserted(database)
        }
      }
    }
    HomeKnowledgeCountInvalidation.post(logMessage: "ActionItemStorage: inserted local task \(inserted.id ?? -1)")
    return inserted
  }

  @discardableResult
  func insertLocalActionItemIfDescriptionAbsent(
    _ record: ActionItemRecord,
    authorization: LocalMutationAuthorization
  ) async throws -> ActionItemRecord? {
    try authorization.require()
    let db = try await ensureInitialized()
    var prepared = record
    prepared.description = prepared.description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prepared.description.isEmpty else { return nil }
    let recordToInsert = try Self.normalizedForWrite(prepared)
    let inserted = try await authorization.withCommitLease {
      try await db.write { database -> ActionItemRecord? in
        try authorization.require()
        let exists =
          try Bool.fetchOne(
            database,
            sql: "SELECT EXISTS(SELECT 1 FROM action_items WHERE deleted = 0 AND lower(trim(description)) = lower(?))",
            arguments: [recordToInsert.description]
          ) ?? false
        guard !exists else { return nil }
        let inserted = try recordToInsert.inserted(database)
        try authorization.require()
        return inserted
      }
    }
    if inserted != nil { HomeKnowledgeCountInvalidation.post() }
    return inserted
  }

  @discardableResult
  func insertObservation(
    _ record: ObservationRecord,
    authorization: LocalMutationAuthorization
  ) async throws -> ObservationRecord {
    try authorization.require()
    let db = try await ensureInitialized()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        let inserted = try record.inserted(database)
        try authorization.require()
        return inserted
      }
    }
  }

  @discardableResult
  func setCompletionAndCreateNextOccurrence(
    surfacedId: String,
    completed: Bool,
    nextDueAt: Date?,
    authorization: LocalMutationAuthorization
  ) async throws -> (task: TaskActionItem, next: TaskActionItem?) {
    try authorization.require()
    let db = try await ensureInitialized()
    let result = try await authorization.withCommitLease {
      try await db.write { database -> (ActionItemRecord, ActionItemRecord?) in
        try authorization.require()
        guard var record = try Self.fetchRecord(database, surfacedId: surfacedId) else {
          throw ActionItemStorageError.recordNotFound
        }
        let wasCompleted = record.completed
        let mutationTime = Date()
        record.completed = completed
        record.completedAt = completed ? mutationTime : nil
        record.updatedAt = mutationTime
        try record.update(database)
        var child: ActionItemRecord?
        if completed, !wasCompleted, let nextDueAt, let recurrenceRule = record.recurrenceRule,
          !recurrenceRule.isEmpty
        {
          let seriesID = record.recurrenceParentId ?? surfacedId
          child =
            try ActionItemRecord
            .filter(Column("recurrenceParentId") == seriesID)
            .filter(Column("dueAt") == nextDueAt)
            .filter(Column("completed") == false)
            .filter(Column("deleted") == false)
            .fetchOne(database)
          if child == nil {
            child = try ActionItemRecord(
              description: record.description,
              source: "recurring",
              conversationId: record.conversationId,
              priority: record.priority,
              dueAt: nextDueAt,
              recurrenceRule: recurrenceRule,
              recurrenceParentId: seriesID,
              provenanceJson: record.provenanceJson,
              screenshotId: record.screenshotId,
              confidence: record.confidence,
              sourceApp: record.sourceApp,
              windowTitle: record.windowTitle,
              contextSummary: record.contextSummary,
              currentActivity: record.currentActivity,
              sortOrder: record.sortOrder
            ).inserted(database)
          }
        }
        try authorization.require()
        return (record, child)
      }
    }
    HomeKnowledgeCountInvalidation.post()
    return (result.0.toTaskActionItem(), result.1?.toTaskActionItem())
  }

  func updateActionItemFields(
    surfacedId: String,
    description: String? = nil,
    dueAt: Date? = nil,
    clearDueAt: Bool = false,
    priority: String? = nil,
    recurrenceRule: String? = nil,
    authorization: LocalMutationAuthorization
  ) async throws {
    try authorization.require()
    let normalizedPriority = try Self.normalizedPriority(priority)
    let normalizedRecurrence = try Self.normalizedRecurrence(recurrenceRule)
    let db = try await ensureInitialized()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard var record = try Self.fetchRecord(database, surfacedId: surfacedId) else {
          throw ActionItemStorageError.recordNotFound
        }
        if let description { record.description = description }
        if clearDueAt { record.dueAt = nil } else if let dueAt { record.dueAt = dueAt }
        if priority != nil { record.priority = normalizedPriority }
        if recurrenceRule != nil { record.recurrenceRule = normalizedRecurrence }
        record.updatedAt = Date()
        try record.update(database)
        try authorization.require()
      }
    }
  }

  func reorderTask(
    surfacedId: String,
    dueAt: Date?,
    orderedIds: [String],
    categoryIndex: Int,
    authorization: LocalMutationAuthorization
  ) async throws {
    try authorization.require()
    let db = try await ensureInitialized()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard var moved = try Self.fetchRecord(database, surfacedId: surfacedId) else {
          throw ActionItemStorageError.recordNotFound
        }
        moved.dueAt = dueAt
        moved.updatedAt = Date()
        try moved.update(database)
        let band = 100_000
        let spacing = max(1, min(1_000, band / max(2, orderedIds.count + 1)))
        for (index, id) in orderedIds.enumerated() {
          guard let rowID = Self.localRowID(surfacedId: id) else {
            throw ActionItemStorageError.recordNotFound
          }
          try database.execute(
            sql: "UPDATE action_items SET sortOrder = ?, updatedAt = ? WHERE id = ?",
            arguments: [categoryIndex * band + (index + 1) * spacing, Date(), rowID]
          )
        }
        try authorization.require()
      }
    }
  }

  func softDelete(
    surfacedId: String,
    authorization: LocalMutationAuthorization
  ) async throws {
    try authorization.require()
    let db = try await ensureInitialized()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard var record = try Self.fetchRecord(database, surfacedId: surfacedId) else {
          throw ActionItemStorageError.recordNotFound
        }
        record.deleted = true
        record.deletedBy = "user"
        let now = Date()
        record.deletedAt = now
        record.updatedAt = now
        try record.update(database)
        try authorization.require()
      }
    }
    HomeKnowledgeCountInvalidation.post()
  }

  @discardableResult
  func restoreActionItem(
    surfacedId: String,
    authorization: LocalMutationAuthorization
  ) async throws -> TaskActionItem {
    try authorization.require()
    let db = try await ensureInitialized()
    let record = try await authorization.withCommitLease {
      try await db.write { database -> ActionItemRecord in
        try authorization.require()
        guard var record = try Self.fetchRecord(database, surfacedId: surfacedId), record.deleted else {
          throw ActionItemStorageError.recordNotFound
        }
        record.deleted = false
        record.deletedBy = nil
        record.deletedAt = nil
        record.updatedAt = Date()
        try record.update(database)
        try authorization.require()
        return record
      }
    }
    HomeKnowledgeCountInvalidation.post()
    return record.toTaskActionItem()
  }

  @discardableResult
  func purgeUserDeletedItems(authorization: LocalMutationAuthorization) async throws -> Int {
    try authorization.require()
    let db = try await ensureInitialized()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        let count =
          try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM action_items WHERE deleted = 1 AND deletedBy = 'user'"
          ) ?? 0
        try database.execute(sql: "DELETE FROM action_items WHERE deleted = 1 AND deletedBy = 'user'")
        try authorization.require()
        return count
      }
    }
  }

  // MARK: Local semantic index

  func getAllEmbeddings() async throws -> [(id: Int64, embedding: Data)] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql: "SELECT id, embedding FROM action_items WHERE deleted = 0 AND embedding IS NOT NULL"
      ).map { ($0["id"], $0["embedding"]) }
    }
  }

  func getItemsMissingEmbeddings(limit: Int = 100) async throws -> [(id: Int64, description: String)] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql:
          "SELECT id, description FROM action_items WHERE deleted = 0 AND embedding IS NULL ORDER BY createdAt DESC LIMIT ?",
        arguments: [max(0, limit)]
      ).map { ($0["id"], $0["description"]) }
    }
  }

  func updateEmbedding(id: Int64, embedding: Data, authorization: LocalMutationAuthorization) async throws {
    try authorization.require()
    let db = try await ensureInitialized()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: "UPDATE action_items SET embedding = ?, updatedAt = ? WHERE id = ?",
          arguments: [embedding, Date(), id]
        )
        guard database.changesCount == 1 else { throw ActionItemStorageError.recordNotFound }
        try authorization.require()
      }
    }
  }
}
