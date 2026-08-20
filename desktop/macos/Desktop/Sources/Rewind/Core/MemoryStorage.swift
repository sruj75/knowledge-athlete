import Foundation
@preconcurrency import GRDB

struct MemoryStats: Sendable {
  let total: Int
  let unread: Int
}

struct LeasedMemoryWork: Sendable {
  let work: MemoryProcessingWorkRecord
  let memory: MemoryItem?
}

actor MemoryStorage {
  static let shared = MemoryStorage()
  static let shortTermLifetime: TimeInterval = 30 * 24 * 60 * 60

  static func deleteExactConversationSource(
    in database: Database,
    conversationId: String
  ) throws {
    try database.execute(
      sql: "DELETE FROM memory_processing_work WHERE conversationId = ?",
      arguments: [conversationId])
    try database.execute(
      sql: "DELETE FROM memories WHERE conversationId = ?",
      arguments: [conversationId])
  }

  static func reassignExactConversationSource(
    in database: Database,
    from sourceConversationId: String,
    to replacementConversationId: String
  ) throws {
    try database.execute(
      sql: "UPDATE memory_processing_work SET conversationId = ? WHERE conversationId = ?",
      arguments: [replacementConversationId, sourceConversationId])
    try database.execute(
      sql: """
        UPDATE memories
        SET conversationId = ?,
            sourceSegmentId = CASE
              WHEN sourceSegmentId IS NULL THEN NULL
              ELSE 'merge:' || ? || ':' || sourceSegmentId
            END
        WHERE conversationId = ?
        """,
      arguments: [replacementConversationId, sourceConversationId, sourceConversationId])
  }

  private var dbQueue: DatabasePool?
  private var dbGeneration = -1

  private init() {}

  func invalidateCache() {
    dbQueue = nil
    dbGeneration = -1
  }

  func database() async throws -> DatabasePool {
    if let dbQueue, await RewindDatabase.shared.poolGeneration() == dbGeneration {
      return dbQueue
    }
    try await RewindDatabase.shared.initialize()
    let (pool, generation) = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    guard let pool else { throw MemoryStorageError.databaseNotInitialized }
    dbQueue = pool
    dbGeneration = generation
    return pool
  }

  static func localID(_ value: String) throws -> Int64 {
    guard let id = Int64(value), id > 0 else { throw MemoryStorageError.invalidIdentity }
    return id
  }

  private static func trimmed(_ content: String) throws -> String {
    let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw MemoryStorageError.emptyContent }
    return value
  }

  private static func jsonString<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }

  private static func addLayerCondition(
    _ scope: MemoryLayerScope,
    conditions: inout [String],
    arguments: inout [DatabaseValue]
  ) {
    conditions.append("layer IN (\(scope.layers.map { _ in "?" }.joined(separator: ", ")))")
    arguments.append(contentsOf: scope.layers.map { $0.rawValue.databaseValue })
  }

  private static func addDefaultExpiryCondition(
    _ scope: MemoryLayerScope,
    now: Date,
    conditions: inout [String],
    arguments: inout [DatabaseValue]
  ) {
    guard scope == .defaultAccess else { return }
    conditions.append("(layer != ? OR expiresAt IS NULL OR expiresAt > ?)")
    arguments.append(MemoryLayer.shortTerm.rawValue.databaseValue)
    arguments.append(now.databaseValue)
  }

  private static func enqueue(
    _ kind: MemoryProcessingKind,
    memoryId: Int64?,
    conversationId: String? = nil,
    revision: Int,
    generation: Int = 0,
    ownerGeneration: Int,
    now: Date,
    in db: Database
  ) throws {
    let work = MemoryProcessingWorkRecord(
      id: UUID().uuidString,
      memoryId: memoryId,
      conversationId: conversationId,
      kind: kind.rawValue,
      inputRevision: revision,
      inputGeneration: generation,
      ownerGeneration: ownerGeneration,
      state: MemoryProcessingState.pending.rawValue,
      attemptCount: 0,
      nextAttemptAt: now,
      leaseExpiresAt: nil,
      lastErrorCode: nil,
      createdAt: now,
      updatedAt: now)
    try work.insert(db)
  }

  @discardableResult
  func acceptExplicitAssertion(
    content: String,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> MemoryItem {
    try await acceptAssertion(
      MemoryAssertion(
        content: content,
        category: .manual,
        layer: .shortTerm,
        manuallyAdded: true,
        source: .manual),
      now: now,
      authorization: authorization)
  }

  @discardableResult
  func acceptAssertion(
    _ assertion: MemoryAssertion,
    now: Date = Date(),
    ownerGeneration: Int = 0,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> MemoryItem {
    let content = try Self.trimmed(assertion.content)
    let normalized = MemoryAssertion(
      content: content,
      category: assertion.category,
      layer: assertion.layer,
      expiresAt: assertion.layer == .shortTerm
        ? assertion.expiresAt ?? now.addingTimeInterval(Self.shortTermLifetime)
        : nil,
      tags: assertion.tags,
      manuallyAdded: assertion.manuallyAdded,
      source: assertion.source,
      conversationId: assertion.conversationId,
      sourceSegmentId: assertion.sourceSegmentId,
      screenshotId: assertion.screenshotId,
      confidence: assertion.confidence,
      reasoning: assertion.reasoning,
      sourceApp: assertion.sourceApp,
      windowTitle: assertion.windowTitle,
      contextSummary: assertion.contextSummary,
      currentActivity: assertion.currentActivity,
      inputDeviceName: assertion.inputDeviceName,
      evidenceTokens: assertion.evidenceTokens,
      sensitivityLabels: assertion.sensitivityLabels,
      subject: assertion.subject,
      predicate: assertion.predicate,
      arguments: assertion.arguments)
    let pool = try await database()
    let effectiveOwnerGeneration = ownerGeneration == 0 ? dbGeneration : ownerGeneration
    let item = try await authorization.withCommitLease {
      try await pool.write { db -> MemoryItem in
        try authorization.require()
        var record = try MemoryRecord.from(assertion: normalized, now: now).inserted(db)
        guard let id = record.id else {
          throw MemoryStorageError.recordNotFound
        }
        if record.evidenceTokens.isEmpty {
          record.evidenceTokensJson = try Self.jsonString([
            "local:\(normalized.source.rawValue):\(id):r\(record.revision)"
          ])
          try record.update(db)
        }
        guard let item = record.toMemoryItem() else { throw MemoryStorageError.recordNotFound }
        if assertion.manuallyAdded {
          try Self.enqueue(
            .normalize, memoryId: id, revision: record.revision,
            ownerGeneration: effectiveOwnerGeneration, now: now, in: db)
        }
        if normalized.layer == .shortTerm && !normalized.manuallyAdded {
          try Self.enqueue(
            .consolidate, memoryId: id, revision: record.revision,
            ownerGeneration: effectiveOwnerGeneration, now: now, in: db)
        }
        try Self.enqueue(
          .embed, memoryId: id, revision: record.revision,
          ownerGeneration: effectiveOwnerGeneration, now: now, in: db)
        return item
      }
    }
    return item
  }

  func list(
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false,
    limit: Int = 100,
    offset: Int = 0
  ) async throws -> [MemoryItem] {
    try await listForTool(
      scope: scope,
      categories: categories,
      tags: tags,
      includeDismissed: includeDismissed,
      startDate: nil,
      endDate: nil,
      limit: limit,
      offset: offset)
  }

  /// Newest-first Insight projection. The `tips` tag is the authority boundary;
  /// the limit bounds presentation only and never prunes older rows.
  func listInsights(limit: Int = 100, includeDismissed: Bool = true) async throws -> [MemoryItem] {
    try await list(
      scope: .allIncludingArchive,
      categories: [.interesting],
      tags: ["tips"],
      includeDismissed: includeDismissed,
      limit: limit,
      offset: 0)
  }

  func listForTool(
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false,
    startDate: Date? = nil,
    endDate: Date? = nil,
    limit: Int = 100,
    offset: Int = 0
  ) async throws -> [MemoryItem] {
    let pool = try await database()
    return try await pool.read { db in
      var conditions = ["pendingDeleteDeadline IS NULL"]
      var arguments: [DatabaseValue] = []
      if !includeDismissed { conditions.append("isDismissed = 0") }
      Self.addDefaultExpiryCondition(
        scope, now: Date(), conditions: &conditions, arguments: &arguments)
      if let startDate {
        conditions.append("createdAt >= ?")
        arguments.append(startDate.databaseValue)
      }
      if let endDate {
        conditions.append("createdAt <= ?")
        arguments.append(endDate.databaseValue)
      }
      Self.addLayerCondition(scope, conditions: &conditions, arguments: &arguments)
      if !categories.isEmpty {
        conditions.append("category IN (\(categories.map { _ in "?" }.joined(separator: ", ")))")
        arguments.append(contentsOf: categories.map { $0.rawValue.databaseValue })
      }
      for tag in tags {
        conditions.append("tagsJson LIKE ?")
        arguments.append("%\"\(tag)\"%".databaseValue)
      }
      arguments.append(max(0, limit).databaseValue)
      arguments.append(max(0, offset).databaseValue)
      let records = try MemoryRecord.fetchAll(
        db,
        sql: """
          SELECT * FROM memories
          WHERE \(conditions.joined(separator: " AND "))
          ORDER BY createdAt DESC, id DESC
          LIMIT ? OFFSET ?
          """,
        arguments: StatementArguments(arguments))
      return records.compactMap { $0.toMemoryItem() }
    }
  }

  func count(
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false
  ) async throws -> Int {
    let pool = try await database()
    return try await pool.read { db in
      var conditions = ["pendingDeleteDeadline IS NULL"]
      var arguments: [DatabaseValue] = []
      if !includeDismissed { conditions.append("isDismissed = 0") }
      Self.addDefaultExpiryCondition(
        scope, now: Date(), conditions: &conditions, arguments: &arguments)
      Self.addLayerCondition(scope, conditions: &conditions, arguments: &arguments)
      if !categories.isEmpty {
        conditions.append("category IN (\(categories.map { _ in "?" }.joined(separator: ", ")))")
        arguments.append(contentsOf: categories.map { $0.rawValue.databaseValue })
      }
      for tag in tags {
        conditions.append("tagsJson LIKE ?")
        arguments.append("%\"\(tag)\"%".databaseValue)
      }
      return try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM memories WHERE \(conditions.joined(separator: " AND "))",
        arguments: StatementArguments(arguments)) ?? 0
    }
  }

  func literalSearch(
    _ text: String,
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false,
    limit: Int = 100,
    offset: Int = 0
  ) async throws -> [MemoryItem] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return try await list(
        scope: scope, categories: categories, tags: tags,
        includeDismissed: includeDismissed, limit: limit, offset: offset)
    }
    let pool = try await database()
    return try await pool.read { db in
      var conditions = ["pendingDeleteDeadline IS NULL", "content LIKE ? COLLATE NOCASE"]
      var arguments: [DatabaseValue] = ["%\(query)%".databaseValue]
      if !includeDismissed { conditions.append("isDismissed = 0") }
      Self.addDefaultExpiryCondition(
        scope, now: Date(), conditions: &conditions, arguments: &arguments)
      Self.addLayerCondition(scope, conditions: &conditions, arguments: &arguments)
      if !categories.isEmpty {
        conditions.append("category IN (\(categories.map { _ in "?" }.joined(separator: ", ")))")
        arguments.append(contentsOf: categories.map { $0.rawValue.databaseValue })
      }
      for tag in tags {
        conditions.append("tagsJson LIKE ?")
        arguments.append("%\"\(tag)\"%".databaseValue)
      }
      arguments.append(max(0, limit).databaseValue)
      arguments.append(max(0, offset).databaseValue)
      let records = try MemoryRecord.fetchAll(
        db,
        sql: """
          SELECT * FROM memories WHERE \(conditions.joined(separator: " AND "))
          ORDER BY createdAt DESC, id DESC LIMIT ? OFFSET ?
          """,
        arguments: StatementArguments(arguments))
      return records.compactMap { $0.toMemoryItem() }
    }
  }

  func memories(ids: [String]) async throws -> [MemoryItem] {
    let localIDs = try ids.map(Self.localID)
    guard !localIDs.isEmpty else { return [] }
    let pool = try await database()
    return try await pool.read { db in
      var found: [MemoryItem] = []
      for chunk in localIDs.chunked(maxSize: 400) {
        let rows =
          try MemoryRecord
          .filter(chunk.contains(Column("id")))
          .filter(Column("pendingDeleteDeadline") == nil)
          .order(Column("createdAt").desc)
          .fetchAll(db)
        found.append(contentsOf: rows.compactMap { $0.toMemoryItem() })
      }
      return found.sorted { $0.createdAt > $1.createdAt }
    }
  }

  func memory(id: String, includePendingDelete: Bool = false) async throws -> MemoryItem? {
    let rowID = try Self.localID(id)
    let pool = try await database()
    return try await pool.read { db in
      guard let record = try MemoryRecord.fetchOne(db, key: rowID) else { return nil }
      guard includePendingDelete || record.pendingDeleteDeadline == nil else { return nil }
      return record.toMemoryItem()
    }
  }

  @discardableResult
  func correct(
    id: String,
    expectedRevision: Int,
    content: String,
    now: Date = Date(),
    ownerGeneration: Int = 0,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> MemoryItem {
    let rowID = try Self.localID(id)
    let value = try Self.trimmed(content)
    let pool = try await database()
    let effectiveOwnerGeneration = ownerGeneration == 0 ? dbGeneration : ownerGeneration
    let item = try await authorization.withCommitLease {
      try await pool.write { db -> MemoryItem in
        try authorization.require()
        guard var record = try MemoryRecord.fetchOne(db, key: rowID) else {
          throw MemoryStorageError.recordNotFound
        }
        guard record.revision == expectedRevision else { throw MemoryStorageError.staleRevision }
        record.content = value
        record.revision += 1
        record.updatedAt = now
        record.correctedAt = now
        record.evidenceTokensJson = try Self.jsonString([
          "local:correction:\(rowID):r\(record.revision)"
        ])
        record.sensitivityLabelsJson = nil
        record.subject = nil
        record.predicate = nil
        record.argumentsJson = nil
        try record.update(db)
        try db.execute(sql: "DELETE FROM memory_embeddings WHERE memoryId = ?", arguments: [rowID])
        try db.execute(
          sql: "DELETE FROM memory_processing_work WHERE memoryId = ? AND state != ?",
          arguments: [rowID, MemoryProcessingState.completed.rawValue])
        try Self.enqueue(
          .normalize, memoryId: rowID, revision: record.revision,
          ownerGeneration: effectiveOwnerGeneration, now: now, in: db)
        try Self.enqueue(
          .embed, memoryId: rowID, revision: record.revision,
          ownerGeneration: effectiveOwnerGeneration, now: now, in: db)
        guard let item = record.toMemoryItem() else { throw MemoryStorageError.recordNotFound }
        return item
      }
    }
    return item
  }

  func markRead(
    id: String, isRead: Bool, now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    try await updateFlags(
      id: id, isRead: isRead, isDismissed: nil, now: now, authorization: authorization)
  }

  func markDismissed(
    id: String, isDismissed: Bool, now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    try await updateFlags(
      id: id, isRead: nil, isDismissed: isDismissed, now: now,
      authorization: authorization)
  }

  func markInsightRead(
    id: String,
    now: Date = Date(),
    authorization: LocalMutationAuthorization
  ) async throws {
    try await updateInsightFlags(
      id: id,
      isRead: true,
      isDismissed: nil,
      now: now,
      authorization: authorization)
  }

  func markInsightDismissed(
    id: String,
    isDismissed: Bool,
    now: Date = Date(),
    authorization: LocalMutationAuthorization
  ) async throws {
    try await updateInsightFlags(
      id: id,
      isRead: nil,
      isDismissed: isDismissed,
      now: now,
      authorization: authorization)
  }

  private func updateInsightFlags(
    id: String,
    isRead: Bool?,
    isDismissed: Bool?,
    now: Date,
    authorization: LocalMutationAuthorization
  ) async throws {
    let rowID = try Self.localID(id)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard var record = try MemoryRecord.fetchOne(db, key: rowID),
          record.tags.contains("tips")
        else { throw MemoryStorageError.recordNotFound }
        if let isRead { record.isRead = isRead }
        if let isDismissed { record.isDismissed = isDismissed }
        record.updatedAt = now
        try record.update(db)
        try authorization.require()
      }
    }
  }

  func markAllInsightsRead(
    now: Date = Date(),
    authorization: LocalMutationAuthorization
  ) async throws {
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        let records = try MemoryRecord.fetchAll(db).filter { $0.tags.contains("tips") }
        for var record in records where !record.isRead {
          record.isRead = true
          record.updatedAt = now
          try record.update(db)
        }
        try authorization.require()
      }
    }
  }

  func deleteInsight(
    id: String,
    authorization: LocalMutationAuthorization
  ) async throws {
    let rowID = try Self.localID(id)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard let record = try MemoryRecord.fetchOne(db, key: rowID),
          record.tags.contains("tips")
        else { throw MemoryStorageError.recordNotFound }
        try record.delete(db)
        try authorization.require()
      }
    }
  }

  @discardableResult
  func clearInsights(authorization: LocalMutationAuthorization) async throws -> Int {
    let pool = try await database()
    return try await authorization.withCommitLease {
      try await pool.write { db -> Int in
        try authorization.require()
        let ids = try MemoryRecord.fetchAll(db).compactMap { record in
          record.tags.contains("tips") ? record.id : nil
        }
        guard !ids.isEmpty else { return 0 }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        try db.execute(
          sql: "DELETE FROM memories WHERE id IN (\(placeholders))",
          arguments: StatementArguments(ids))
        try authorization.require()
        return db.changesCount
      }
    }
  }

  private func updateFlags(
    id: String,
    isRead: Bool?,
    isDismissed: Bool?,
    now: Date,
    authorization: LocalMutationAuthorization
  ) async throws {
    let rowID = try Self.localID(id)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard var record = try MemoryRecord.fetchOne(db, key: rowID) else {
          throw MemoryStorageError.recordNotFound
        }
        if let isRead { record.isRead = isRead }
        if let isDismissed { record.isDismissed = isDismissed }
        record.updatedAt = now
        try record.update(db)
      }
    }
  }

  func markAllRead(
    scope: MemoryLayerScope, now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        let placeholders = scope.layers.map { _ in "?" }.joined(separator: ", ")
        var arguments: [DatabaseValue] = [now.databaseValue]
        arguments.append(contentsOf: scope.layers.map { $0.rawValue.databaseValue })
        try db.execute(
          sql: "UPDATE memories SET isRead = 1, updatedAt = ? WHERE layer IN (\(placeholders))",
          arguments: StatementArguments(arguments))
      }
    }
  }

  @discardableResult
  func beginDeletion(
    id: String,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> Date {
    let rowID = try Self.localID(id)
    let deadline = now.addingTimeInterval(4)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard var record = try MemoryRecord.fetchOne(db, key: rowID) else {
          throw MemoryStorageError.recordNotFound
        }
        record.pendingDeleteDeadline = deadline
        record.updatedAt = now
        try record.update(db)
      }
    }
    return deadline
  }

  func undoDeletion(
    id: String,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let rowID = try Self.localID(id)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard var record = try MemoryRecord.fetchOne(db, key: rowID) else {
          throw MemoryStorageError.recordNotFound
        }
        guard let deadline = record.pendingDeleteDeadline, now <= deadline else {
          throw MemoryStorageError.invalidTransition("Undo window expired")
        }
        record.pendingDeleteDeadline = nil
        record.updatedAt = now
        try record.update(db)
      }
    }
  }

  func finalizeDeletion(
    id: String,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let rowID = try Self.localID(id)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard let record = try MemoryRecord.fetchOne(db, key: rowID) else { return }
        guard record.pendingDeleteDeadline != nil else {
          throw MemoryStorageError.invalidTransition("Memory is not pending deletion")
        }
        try record.delete(db)
      }
    }
  }

  @discardableResult
  func finalizeExpiredDeletions(
    now: Date = Date(), authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> Int {
    let pool = try await database()
    let count = try await authorization.withCommitLease {
      try await pool.write { db -> Int in
        try authorization.require()
        try db.execute(
          sql: "DELETE FROM memories WHERE pendingDeleteDeadline IS NOT NULL AND pendingDeleteDeadline <= ?",
          arguments: [now])
        return db.changesCount
      }
    }
    return count
  }

  func deleteDefaultMemories(
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        try db.execute(
          sql: "DELETE FROM memories WHERE layer IN (?, ?)",
          arguments: [MemoryLayer.shortTerm.rawValue, MemoryLayer.longTerm.rawValue])
      }
    }
  }

  @discardableResult
  func deleteAssertions(
    source: MemorySource, exactContent: String,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> Int {
    let pool = try await database()
    let count = try await authorization.withCommitLease {
      try await pool.write { db -> Int in
        try authorization.require()
        try db.execute(
          sql: "DELETE FROM memories WHERE source = ? AND content = ?",
          arguments: [source.rawValue, exactContent])
        return db.changesCount
      }
    }
    return count
  }

  @discardableResult
  func deleteTaggedAssertions(
    tag: String, authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> Int {
    let pool = try await database()
    let count = try await authorization.withCommitLease {
      try await pool.write { db -> Int in
        try authorization.require()
        let records = try MemoryRecord.fetchAll(db)
        let ids = records.compactMap { record in
          record.tags.contains(tag) ? record.id : nil
        }
        guard !ids.isEmpty else { return 0 }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        try db.execute(
          sql: "DELETE FROM memories WHERE id IN (\(placeholders))",
          arguments: StatementArguments(ids))
        return db.changesCount
      }
    }
    return count
  }

  func enqueueConversationExtraction(
    conversationId: String,
    generation: Int,
    ownerGeneration: Int,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        let exists =
          try Bool.fetchOne(
            db,
            sql: """
              SELECT EXISTS(
                SELECT 1 FROM memory_processing_work
                WHERE kind = ? AND conversationId = ? AND inputGeneration = ?
                  AND state != ?
              )
              """,
            arguments: [
              MemoryProcessingKind.extract.rawValue, conversationId, generation,
              MemoryProcessingState.terminal.rawValue,
            ]) ?? false
        guard !exists else { return }
        try Self.enqueue(
          .extract, memoryId: nil, conversationId: conversationId, revision: 0,
          generation: generation, ownerGeneration: ownerGeneration, now: now, in: db)
      }
    }
  }

  /// Durable work lives inside the owner database; pool generations only fence
  /// in-flight commits. Rebind unfinished rows after an authorized reopen and
  /// repair any missing vector work for current revisions.
  func recoverLifecycleWork(
    ownerGeneration: Int,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        try db.execute(
          sql: """
            UPDATE memory_processing_work
            SET ownerGeneration = ?,
                state = CASE WHEN state = ? THEN ? ELSE state END,
                leaseExpiresAt = NULL,
                nextAttemptAt = CASE WHEN state = ? THEN ? ELSE nextAttemptAt END,
                updatedAt = ?
            WHERE ownerGeneration != ? AND state IN (?, ?, ?)
            """,
          arguments: [
            ownerGeneration,
            MemoryProcessingState.leased.rawValue,
            MemoryProcessingState.retry.rawValue,
            MemoryProcessingState.leased.rawValue,
            now,
            now,
            ownerGeneration,
            MemoryProcessingState.pending.rawValue,
            MemoryProcessingState.retry.rawValue,
            MemoryProcessingState.leased.rawValue,
          ])
        let missing = try MemoryRecord.fetchAll(
          db,
          sql: """
            SELECT m.* FROM memories m
            WHERE m.pendingDeleteDeadline IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM memory_embeddings e
                WHERE e.memoryId = m.id AND e.revision = m.revision
              )
              AND NOT EXISTS (
                SELECT 1 FROM memory_processing_work w
                WHERE w.memoryId = m.id AND w.kind = ? AND w.inputRevision = m.revision
                  AND w.state != ?
              )
            """,
          arguments: [
            MemoryProcessingKind.embed.rawValue,
            MemoryProcessingState.terminal.rawValue,
          ])
        for record in missing {
          guard let memoryID = record.id else { continue }
          try Self.enqueue(
            .embed, memoryId: memoryID, revision: record.revision,
            ownerGeneration: ownerGeneration, now: now, in: db)
        }
      }
    }
  }

  func leaseDueWork(
    kind: MemoryProcessingKind,
    now: Date = Date(),
    ownerGeneration: Int,
    limit: Int = 8,
    leaseDuration: TimeInterval = 600,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> [LeasedMemoryWork] {
    let pool = try await database()
    return try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        try db.execute(
          sql: """
            UPDATE memory_processing_work
            SET state = ?, leaseExpiresAt = NULL, updatedAt = ?
            WHERE state = ? AND leaseExpiresAt <= ?
            """,
          arguments: [
            MemoryProcessingState.retry.rawValue, now,
            MemoryProcessingState.leased.rawValue, now,
          ])
        let due = try MemoryProcessingWorkRecord.fetchAll(
          db,
          sql: """
            SELECT * FROM memory_processing_work
            WHERE kind = ? AND state IN (?, ?) AND nextAttemptAt <= ? AND ownerGeneration = ?
            ORDER BY nextAttemptAt, createdAt LIMIT ?
            """,
          arguments: [
            kind.rawValue, MemoryProcessingState.pending.rawValue, MemoryProcessingState.retry.rawValue,
            now, ownerGeneration, max(1, limit),
          ])
        let deadline = now.addingTimeInterval(leaseDuration)
        var leased: [LeasedMemoryWork] = []
        for var work in due {
          work.state = MemoryProcessingState.leased.rawValue
          work.leaseExpiresAt = deadline
          work.updatedAt = now
          try work.update(db)
          let memory = try work.memoryId.flatMap { id in
            try MemoryRecord.fetchOne(db, key: id)?.toMemoryItem()
          }
          leased.append(LeasedMemoryWork(work: work, memory: memory))
        }
        return leased
      }
    }
  }

  func retryWork(
    id: String,
    errorCode: String,
    now: Date = Date(),
    ownerGeneration: Int? = nil,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard var work = try MemoryProcessingWorkRecord.fetchOne(db, key: id) else {
          throw MemoryStorageError.recordNotFound
        }
        if let ownerGeneration, work.ownerGeneration != ownerGeneration {
          throw MemoryStorageError.staleRevision
        }
        work.attemptCount += 1
        work.state =
          work.attemptCount >= 3
          ? MemoryProcessingState.terminal.rawValue
          : MemoryProcessingState.retry.rawValue
        let exponent = min(max(0, work.attemptCount - 1), 3)
        work.nextAttemptAt = now.addingTimeInterval(pow(2, Double(exponent)) * 300)
        work.leaseExpiresAt = nil
        work.lastErrorCode = String(errorCode.prefix(80))
        work.updatedAt = now
        try work.update(db)
      }
    }
  }

  func completeNormalization(
    workId: String,
    memoryId: String,
    expectedRevision: Int,
    normalizedContent: String,
    subject: String,
    predicate: String,
    arguments: [String: String],
    sensitivityLabels: [String],
    receiptId: String,
    ownerGeneration: Int,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> MemoryItem {
    let rowID = try Self.localID(memoryId)
    let content = try Self.trimmed(normalizedContent)
    let pool = try await database()
    let item = try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        if let transition =
          try MemoryTransitionRecord
          .filter(Column("idempotencyKey") == "normalize:\(workId)").fetchOne(db),
          transition.receiptId == receiptId,
          transition.memoryId == rowID,
          let record = try MemoryRecord.fetchOne(db, key: rowID),
          record.revision == transition.outputRevision,
          let item = record.toMemoryItem()
        {
          return item
        }
        guard var work = try MemoryProcessingWorkRecord.fetchOne(db, key: workId),
          work.state == MemoryProcessingState.leased.rawValue,
          work.ownerGeneration == ownerGeneration,
          work.memoryId == rowID,
          var record = try MemoryRecord.fetchOne(db, key: rowID),
          record.revision == expectedRevision
        else { throw MemoryStorageError.staleRevision }

        record.content = content
        record.subject = subject
        record.predicate = predicate
        record.argumentsJson = try Self.jsonString(arguments)
        record.sensitivityLabelsJson = try Self.jsonString(sensitivityLabels)
        record.revision += 1
        record.updatedAt = now
        try record.update(db)
        let transition = MemoryTransitionRecord(
          id: UUID().uuidString,
          memoryId: rowID,
          idempotencyKey: "normalize:\(workId)",
          fromLayer: record.layer,
          toLayer: record.layer,
          inputRevision: expectedRevision,
          outputRevision: record.revision,
          outcome: "normalized",
          receiptId: receiptId,
          createdAt: now)
        try transition.insert(db)
        try db.execute(
          sql: "DELETE FROM memory_processing_work WHERE memoryId = ? AND kind = ? AND state != ? AND id != ?",
          arguments: [
            rowID, MemoryProcessingKind.embed.rawValue,
            MemoryProcessingState.completed.rawValue, workId,
          ])
        work.state = MemoryProcessingState.completed.rawValue
        work.leaseExpiresAt = nil
        work.updatedAt = now
        try work.update(db)
        try Self.enqueue(
          .embed, memoryId: rowID, revision: record.revision,
          ownerGeneration: ownerGeneration, now: now, in: db)
        try Self.enqueue(
          .consolidate, memoryId: rowID, revision: record.revision,
          ownerGeneration: ownerGeneration, now: now, in: db)
        guard let item = record.toMemoryItem() else { throw MemoryStorageError.recordNotFound }
        return item
      }
    }
    return item
  }

  @discardableResult
  func completeExtraction(
    workId: String,
    conversationId: String,
    expectedGeneration: Int,
    admissions: [MemoryExtractionAdmission],
    receiptId: String,
    ownerGeneration: Int,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> [MemoryItem] {
    guard admissions.count <= 32 else {
      throw MemoryStorageError.invalidTransition("Extraction exceeded 32 candidates")
    }
    let contents = admissions.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard contents.allSatisfy({ !$0.isEmpty }), Set(contents).count == contents.count,
      admissions.allSatisfy({
        ["general", "sensitive"].contains($0.archiveClass)
          && $0.riskFlags.count <= 16 && $0.sensitivityLabels.count <= 16
      })
    else {
      throw MemoryStorageError.invalidTransition("Extraction candidates must be unique and non-empty")
    }
    let pool = try await database()
    let items = try await authorization.withCommitLease {
      try await pool.write { db -> [MemoryItem] in
        try authorization.require()
        let priorTransitions = try admissions.indices.compactMap { index in
          try MemoryTransitionRecord
            .filter(Column("idempotencyKey") == "extract:\(workId):\(index)")
            .fetchOne(db)
        }
        if !priorTransitions.isEmpty {
          guard priorTransitions.count == admissions.count,
            priorTransitions.allSatisfy({ $0.receiptId == receiptId })
          else { throw MemoryStorageError.invalidTransition("Extraction replay is inconsistent") }
          return try priorTransitions.map { transition in
            guard let record = try MemoryRecord.fetchOne(db, key: transition.memoryId),
              let item = record.toMemoryItem()
            else { throw MemoryStorageError.recordNotFound }
            return item
          }
        }
        guard var work = try MemoryProcessingWorkRecord.fetchOne(db, key: workId),
          work.state == MemoryProcessingState.leased.rawValue,
          work.kind == MemoryProcessingKind.extract.rawValue,
          work.ownerGeneration == ownerGeneration,
          work.conversationId == conversationId,
          work.inputGeneration == expectedGeneration,
          let currentGeneration = try Int.fetchOne(
            db,
            sql: "SELECT contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId]),
          currentGeneration == expectedGeneration
        else { throw MemoryStorageError.staleRevision }
        if admissions.isEmpty {
          work.state = MemoryProcessingState.completed.rawValue
          work.leaseExpiresAt = nil
          work.updatedAt = now
          try work.update(db)
          return []
        }

        var accepted: [MemoryItem] = []
        for (index, admission) in admissions.enumerated() {
          let duplicate =
            try Bool.fetchOne(
              db,
              sql: """
                SELECT EXISTS(
                  SELECT 1 FROM memories
                  WHERE conversationId = ? AND content = ? AND pendingDeleteDeadline IS NULL
                )
                """,
              arguments: [conversationId, contents[index]]) ?? false
          guard !duplicate else {
            throw MemoryStorageError.invalidTransition("Extraction duplicated an accepted Memory")
          }
          var sensitivityLabels = admission.sensitivityLabels.map { $0.lowercased() }
          sensitivityLabels.append(contentsOf: admission.riskFlags.map { $0.lowercased() })
          if admission.archiveClass == "sensitive" { sensitivityLabels.append("secret") }
          sensitivityLabels = Array(Set(sensitivityLabels)).sorted()
          let assertion = MemoryAssertion(
            content: contents[index], category: admission.category, layer: .shortTerm,
            expiresAt: now.addingTimeInterval(Self.shortTermLifetime),
            source: .conversation, conversationId: conversationId,
            sourceSegmentId: admission.segmentId,
            confidence: admission.confidence,
            contextSummary: admission.quote,
            evidenceTokens: admission.evidenceTokens,
            sensitivityLabels: sensitivityLabels,
            subject: admission.subject)
          let record = try MemoryRecord.from(assertion: assertion, now: now).inserted(db)
          guard let memoryId = record.id, let item = record.toMemoryItem() else {
            throw MemoryStorageError.recordNotFound
          }
          try MemoryTransitionRecord(
            id: UUID().uuidString,
            memoryId: memoryId,
            idempotencyKey: "extract:\(workId):\(index)",
            fromLayer: nil,
            toLayer: MemoryLayer.shortTerm.rawValue,
            inputRevision: 0,
            outputRevision: record.revision,
            outcome: "conversation_candidate_admitted",
            receiptId: receiptId,
            createdAt: now
          ).insert(db)
          try Self.enqueue(
            .embed, memoryId: memoryId, revision: record.revision,
            ownerGeneration: ownerGeneration, now: now, in: db)
          try Self.enqueue(
            .consolidate, memoryId: memoryId, revision: record.revision,
            ownerGeneration: ownerGeneration, now: now, in: db)
          accepted.append(item)
        }
        work.state = MemoryProcessingState.completed.rawValue
        work.leaseExpiresAt = nil
        work.updatedAt = now
        try work.update(db)
        return accepted
      }
    }
    return items
  }

  @discardableResult
  func completeConsolidation(
    applications: [MemoryConsolidationApplication],
    receiptId: String,
    ownerGeneration: Int,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> [MemoryItem] {
    let supersededTargets =
      applications
      .filter { $0.reconciliation == .replace || $0.reconciliation == .merge }
      .flatMap { $0.targets.map(\.memoryId) }
    guard !applications.isEmpty, applications.count <= 32,
      Set(applications.map(\.workId)).count == applications.count,
      Set(applications.map(\.memoryId)).count == applications.count,
      Set(supersededTargets).count == supersededTargets.count
    else { throw MemoryStorageError.invalidTransition("Consolidation decisions are incomplete") }

    let pool = try await database()
    let changed = try await authorization.withCommitLease {
      try await pool.write { db -> [MemoryItem] in
        try authorization.require()
        var candidateRecords: [String: MemoryRecord] = [:]
        var alreadyApplied: [String: MemoryItem] = [:]
        for application in applications {
          let rowID = try Self.localID(application.memoryId)
          if let transition =
            try MemoryTransitionRecord
            .filter(Column("idempotencyKey") == "consolidate:\(application.workId)").fetchOne(db),
            transition.receiptId == receiptId,
            transition.memoryId == rowID,
            let record = try MemoryRecord.fetchOne(db, key: rowID),
            record.revision == transition.outputRevision,
            let item = record.toMemoryItem()
          {
            alreadyApplied[application.memoryId] = item
            continue
          }
          guard let work = try MemoryProcessingWorkRecord.fetchOne(db, key: application.workId),
            work.state == MemoryProcessingState.leased.rawValue,
            work.kind == MemoryProcessingKind.consolidate.rawValue,
            work.ownerGeneration == ownerGeneration,
            work.memoryId == rowID,
            work.inputRevision == application.expectedRevision,
            let record = try MemoryRecord.fetchOne(db, key: rowID),
            record.revision == application.expectedRevision,
            record.layer == MemoryLayer.shortTerm.rawValue
          else { throw MemoryStorageError.staleRevision }
          try Self.validate(application: application, candidate: record)
          candidateRecords[application.memoryId] = record
          for target in application.targets {
            let targetID = try Self.localID(target.memoryId)
            guard let targetRecord = try MemoryRecord.fetchOne(db, key: targetID),
              targetRecord.revision == target.expectedRevision,
              targetRecord.pendingDeleteDeadline == nil,
              targetRecord.layer != MemoryLayer.archive.rawValue
            else { throw MemoryStorageError.staleRevision }
          }
        }

        var output: [MemoryItem] = []
        for application in applications {
          if let item = alreadyApplied[application.memoryId] {
            output.append(item)
            continue
          }
          guard var candidate = candidateRecords[application.memoryId], let candidateID = candidate.id else {
            throw MemoryStorageError.recordNotFound
          }
          if application.reconciliation == .replace || application.reconciliation == .merge {
            for target in application.targets {
              let targetID = try Self.localID(target.memoryId)
              guard var targetRecord = try MemoryRecord.fetchOne(db, key: targetID),
                targetRecord.revision == target.expectedRevision,
                targetRecord.pendingDeleteDeadline == nil,
                targetRecord.layer == MemoryLayer.longTerm.rawValue,
                let fromLayer = MemoryLayer(rawValue: targetRecord.layer)
              else { throw MemoryStorageError.staleRevision }
              let inputRevision = targetRecord.revision
              targetRecord.layer = MemoryLayer.archive.rawValue
              targetRecord.expiresAt = nil
              targetRecord.revision += 1
              targetRecord.updatedAt = now
              try targetRecord.update(db)
              try Self.replaceEmbeddingWork(
                memoryId: targetID, revision: targetRecord.revision,
                ownerGeneration: ownerGeneration, now: now, in: db)
              try MemoryTransitionRecord(
                id: UUID().uuidString,
                memoryId: targetID,
                idempotencyKey: "consolidate:\(application.workId):target:\(targetID)",
                fromLayer: fromLayer.rawValue,
                toLayer: MemoryLayer.archive.rawValue,
                inputRevision: inputRevision,
                outputRevision: targetRecord.revision,
                outcome: "superseded_\(application.reconciliation.rawValue)",
                receiptId: receiptId,
                createdAt: now
              ).insert(db)
            }
          }

          let fromLayer = candidate.layer
          let inputRevision = candidate.revision
          switch (application.action, application.reconciliation) {
          case (_, .duplicate), (.reject, _):
            candidate.layer = MemoryLayer.archive.rawValue
            candidate.isDismissed = true
            candidate.expiresAt = nil
          case (.archive, _):
            candidate.layer = MemoryLayer.archive.rawValue
            candidate.expiresAt = nil
          case (.review, _):
            candidate.layer = MemoryLayer.shortTerm.rawValue
            candidate.expiresAt = now.addingTimeInterval(Self.shortTermLifetime)
          case (.promote, _):
            candidate.layer = MemoryLayer.longTerm.rawValue
            candidate.expiresAt = nil
            candidate.content = try Self.trimmed(application.memoryText ?? "")
            candidate.evidenceTokensJson = try Self.jsonString(application.evidenceTokens)
            candidate.sensitivityLabelsJson = try Self.jsonString(application.sensitivityLabels)
            candidate.subject = application.subject
            candidate.predicate = application.predicate
            candidate.argumentsJson = try Self.jsonString(application.arguments)
          }
          candidate.revision += 1
          candidate.updatedAt = now
          try candidate.update(db)
          try MemoryTransitionRecord(
            id: UUID().uuidString,
            memoryId: candidateID,
            idempotencyKey: "consolidate:\(application.workId)",
            fromLayer: fromLayer,
            toLayer: candidate.layer,
            inputRevision: inputRevision,
            outputRevision: candidate.revision,
            outcome: "\(application.action.rawValue)_\(application.reconciliation.rawValue)",
            receiptId: receiptId,
            createdAt: now
          ).insert(db)
          try Self.replaceEmbeddingWork(
            memoryId: candidateID, revision: candidate.revision,
            ownerGeneration: ownerGeneration, now: now, in: db)
          guard var work = try MemoryProcessingWorkRecord.fetchOne(db, key: application.workId) else {
            throw MemoryStorageError.recordNotFound
          }
          work.state = MemoryProcessingState.completed.rawValue
          work.leaseExpiresAt = nil
          work.updatedAt = now
          try work.update(db)
          guard let item = candidate.toMemoryItem() else { throw MemoryStorageError.recordNotFound }
          output.append(item)
        }
        return output
      }
    }
    return changed
  }

  private static func validate(
    application: MemoryConsolidationApplication,
    candidate: MemoryRecord
  ) throws {
    let needsTargets: Bool
    switch application.reconciliation {
    case .duplicate, .replace, .merge: needsTargets = true
    case .create, .keepBoth: needsTargets = false
    }
    guard needsTargets == !application.targets.isEmpty else {
      throw MemoryStorageError.invalidTransition("Consolidation target shape is invalid")
    }
    guard application.targets.count <= 8,
      Set(application.targets.map(\.memoryId)).count == application.targets.count,
      !application.targets.contains(where: { $0.memoryId == application.memoryId })
    else { throw MemoryStorageError.invalidTransition("Consolidation targets are invalid") }
    guard (application.action == .promote) == (application.memoryText != nil) else {
      throw MemoryStorageError.invalidTransition("Consolidation Memory text is invalid")
    }
    if application.reconciliation == .replace || application.reconciliation == .merge {
      guard application.action == .promote else {
        throw MemoryStorageError.invalidTransition("Replacement and merge must promote")
      }
    }
    if application.reconciliation == .keepBoth && application.action != .promote {
      throw MemoryStorageError.invalidTransition("Only promotion may keep both")
    }
    if application.reconciliation == .duplicate && application.action == .promote {
      throw MemoryStorageError.invalidTransition("Duplicate observations must not promote")
    }
    guard Set(application.evidenceTokens).isSubset(of: Set(candidate.evidenceTokens)),
      application.evidenceTokens.count == Set(application.evidenceTokens).count,
      Set(application.sensitivityLabels) == Set(candidate.sensitivityLabels),
      application.subject == (candidate.subject ?? "unclear")
    else { throw MemoryStorageError.invalidTransition("Consolidation changed authoritative evidence") }
    if application.action == .promote {
      let restricted = Set([
        "credential", "secret", "financial", "health", "intimate", "minor", "minors",
        "workplace_confidential", "identity_authentication",
      ])
      let durableRelationship =
        (application.relationshipToUser == "self" && application.aboutness == "primary_user")
        || (application.relationshipToUser == "owned_work"
          && application.aboutness == "user_owned_project")
        || (application.relationshipToUser == "adopted"
          && application.aboutness == "user_relationship")
        || (application.relationshipToUser == "other_speaker"
          && application.aboutness == "user_relationship"
          && application.basisForMemory == "recurring")
      guard restricted.isDisjoint(with: Set(application.sensitivityLabels)),
        !["third_party", "unclear"].contains(application.aboutness),
        application.basisForMemory != "weak_or_none",
        durableRelationship,
        !application.evidenceTokens.isEmpty,
        application.predicate != nil,
        argumentsAreBounded(application.arguments)
      else { throw MemoryStorageError.invalidTransition("Unsafe Memory promotion") }
    }
  }

  private static func argumentsAreBounded(_ arguments: [String: String]) -> Bool {
    guard arguments.count <= 32,
      arguments.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 128 && $0.value.count <= 1_024 }),
      let encoded = try? JSONSerialization.data(withJSONObject: arguments),
      encoded.count <= 8_192
    else { return false }
    return true
  }

  private static func replaceEmbeddingWork(
    memoryId: Int64,
    revision: Int,
    ownerGeneration: Int,
    now: Date,
    in db: Database
  ) throws {
    try db.execute(sql: "DELETE FROM memory_embeddings WHERE memoryId = ?", arguments: [memoryId])
    try db.execute(
      sql: "DELETE FROM memory_processing_work WHERE memoryId = ? AND kind = ? AND state != ?",
      arguments: [
        memoryId, MemoryProcessingKind.embed.rawValue,
        MemoryProcessingState.completed.rawValue,
      ])
    try Self.enqueue(
      .embed, memoryId: memoryId, revision: revision,
      ownerGeneration: ownerGeneration, now: now, in: db)
  }

  func storeEmbedding(
    workId: String,
    memoryId: String,
    expectedRevision: Int,
    model: String,
    vector: [Double],
    ownerGeneration: Int,
    now: Date = Date(),
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws {
    guard !vector.isEmpty, vector.allSatisfy(\.isFinite), vector.contains(where: { $0 != 0 }) else {
      throw MemoryStorageError.invalidEmbedding
    }
    let rowID = try Self.localID(memoryId)
    let data = try JSONEncoder().encode(vector)
    let encoded = String(decoding: data, as: UTF8.self)
    let pool = try await database()
    try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard var work = try MemoryProcessingWorkRecord.fetchOne(db, key: workId),
          work.state == MemoryProcessingState.leased.rawValue,
          work.ownerGeneration == ownerGeneration,
          work.memoryId == rowID,
          let record = try MemoryRecord.fetchOne(db, key: rowID),
          record.revision == expectedRevision
        else { throw MemoryStorageError.staleRevision }
        try MemoryEmbeddingRecord(
          memoryId: rowID, revision: expectedRevision, model: model,
          vectorJson: encoded, updatedAt: now
        ).save(db)
        work.state = MemoryProcessingState.completed.rawValue
        work.leaseExpiresAt = nil
        work.updatedAt = now
        try work.update(db)
      }
    }
  }

  @discardableResult
  func enqueueDueLifecycleWork(
    now: Date = Date(),
    ownerGeneration: Int,
    authorization: LocalMutationAuthorization = .unrestricted
  ) async throws -> Int {
    let pool = try await database()
    let count = try await authorization.withCommitLease {
      try await pool.write { db -> Int in
        try authorization.require()
        let records = try MemoryRecord.fetchAll(
          db,
          sql: """
            SELECT m.* FROM memories m
            WHERE m.layer = ? AND m.expiresAt IS NOT NULL AND m.expiresAt <= ?
              AND m.pendingDeleteDeadline IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM memory_processing_work w
                WHERE w.memoryId = m.id AND w.kind = ? AND w.inputRevision = m.revision
              )
            """,
          arguments: [
            MemoryLayer.shortTerm.rawValue, now,
            MemoryProcessingKind.consolidate.rawValue,
          ])
        for record in records {
          guard let memoryId = record.id else { continue }
          try Self.enqueue(
            .consolidate, memoryId: memoryId, revision: record.revision,
            ownerGeneration: ownerGeneration, now: now, in: db)
        }
        return records.count
      }
    }
    return count
  }

  func getUnreadTipsCount() async throws -> Int {
    let pool = try await database()
    return try await pool.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM memories
          WHERE pendingDeleteDeadline IS NULL AND isDismissed = 0 AND isRead = 0
            AND tagsJson LIKE '%"tips"%'
          """) ?? 0
    }
  }

  func getStats() async throws -> MemoryStats {
    let pool = try await database()
    return try await pool.read { db in
      let total =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM memories WHERE pendingDeleteDeadline IS NULL") ?? 0
      let unread =
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM memories
            WHERE pendingDeleteDeadline IS NULL AND isRead = 0 AND isDismissed = 0
            """) ?? 0
      return MemoryStats(total: total, unread: unread)
    }
  }

  @discardableResult
  func cleanupOldDismissedMemories(olderThan date: Date) async throws -> Int {
    let pool = try await database()
    return try await pool.write { db in
      try db.execute(
        sql: "DELETE FROM memories WHERE isDismissed = 1 AND updatedAt < ?",
        arguments: [date])
      return db.changesCount
    }
  }
}

extension Array {
  func chunked(maxSize: Int) -> [[Element]] {
    precondition(maxSize > 0)
    return stride(from: 0, to: count, by: maxSize).map {
      Array(self[$0..<Swift.min($0 + maxSize, count)])
    }
  }
}
