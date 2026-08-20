import Foundation
import GRDB

extension RewindDatabase {
  static func registerMemoryLocalAuthorityMigration(on migrator: inout DatabaseMigrator) {
    migrator.registerMigration("makeMemoriesLocalAuthoritativeS12") { db in
      let columns = Set(try db.columns(in: "memories").map(\.name))
      let isFinalSchema =
        columns.contains("layer") && columns.contains("revision")
        && columns.contains("sourceSegmentId") && !columns.contains("backendId")

      if !isFinalSchema {
        try rebuildMemoryTableForLocalAuthority(in: db, legacyColumns: columns)
      }
      try createMemoryAuthorityTables(in: db)
    }
    migrator.registerMigration("addMemorySourceSegmentS12") { db in
      let columns = Set(try db.columns(in: "memories").map(\.name))
      if !columns.contains("sourceSegmentId") {
        try db.alter(table: "memories") { $0.add(column: "sourceSegmentId", .text) }
      }
    }
    migrator.registerMigration("completeMemoryLifecycleInputsS12") { db in
      let columns = Set(try db.columns(in: "memories").map(\.name))
      try db.alter(table: "memories") { table in
        if !columns.contains("evidenceTokensJson") { table.add(column: "evidenceTokensJson", .text) }
        if !columns.contains("sensitivityLabelsJson") { table.add(column: "sensitivityLabelsJson", .text) }
        if !columns.contains("subject") { table.add(column: "subject", .text) }
        if !columns.contains("predicate") { table.add(column: "predicate", .text) }
        if !columns.contains("argumentsJson") { table.add(column: "argumentsJson", .text) }
      }
      try db.execute(
        sql: "UPDATE memories SET category = ? WHERE tagsJson LIKE '%\"tips\"%'",
        arguments: [MemoryCategory.interesting.rawValue])
      try db.execute(
        sql: """
          UPDATE memories
          SET expiresAt = datetime(updatedAt, '+30 days')
          WHERE layer = ? AND expiresAt IS NULL
          """,
        arguments: [MemoryLayer.shortTerm.rawValue])

      let now = Date()
      let rows = try Row.fetchAll(db, sql: "SELECT id, revision, layer, manuallyAdded FROM memories")
      for row in rows {
        let memoryID: Int64 = row["id"]
        let revision: Int = row["revision"]
        let layer: String = row["layer"]
        let manuallyAdded: Bool = row["manuallyAdded"]
        try enqueueMigrationWorkIfMissing(
          kind: .embed, memoryID: memoryID, revision: revision, now: now, in: db)
        if layer == MemoryLayer.shortTerm.rawValue {
          try enqueueMigrationWorkIfMissing(
            kind: manuallyAdded ? .normalize : .consolidate,
            memoryID: memoryID, revision: revision, now: now, in: db)
        }
      }
    }
  }

  private static func rebuildMemoryTableForLocalAuthority(
    in db: Database,
    legacyColumns: Set<String>
  ) throws {
    for index in [
      "idx_memories_backend_id", "idx_memories_created", "idx_memories_category",
      "idx_memories_synced", "idx_memories_screenshot", "idx_memories_deleted",
      "idx_memories_tier", "idx_memories_tier_explicit", "idx_memories_capture_device",
    ] {
      try db.execute(sql: "DROP INDEX IF EXISTS \(index)")
    }

    try db.create(table: "memories_s12") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("content", .text).notNull()
      t.column("category", .text).notNull()
      t.column("layer", .text).notNull()
      t.column("expiresAt", .datetime)
      t.column("revision", .integer).notNull().defaults(to: 1)
      t.column("tagsJson", .text)
      t.column("manuallyAdded", .boolean).notNull().defaults(to: false)
      t.column("source", .text)
      t.column("conversationId", .text)
      t.column("sourceSegmentId", .text)
      t.column("screenshotId", .integer).references("screenshots", onDelete: .setNull)
      t.column("confidence", .double)
      t.column("reasoning", .text)
      t.column("sourceApp", .text)
      t.column("windowTitle", .text)
      t.column("contextSummary", .text)
      t.column("currentActivity", .text)
      t.column("inputDeviceName", .text)
      t.column("isRead", .boolean).notNull().defaults(to: false)
      t.column("isDismissed", .boolean).notNull().defaults(to: false)
      t.column("pendingDeleteDeadline", .datetime)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
      t.column("correctedAt", .datetime)
      t.column("evidenceTokensJson", .text)
      t.column("sensitivityLabelsJson", .text)
      t.column("subject", .text)
      t.column("predicate", .text)
      t.column("argumentsJson", .text)
    }

    func column(_ name: String, fallback: String) -> String {
      legacyColumns.contains(name) ? name : fallback
    }
    let layerExpression: String
    if legacyColumns.contains("tier") {
      layerExpression =
        "CASE WHEN tier IN ('short_term', 'long_term', 'archive') THEN tier ELSE 'short_term' END"
    } else {
      layerExpression = "'short_term'"
    }
    let sourceExpression = """
      CASE
        WHEN \(column("manuallyAdded", fallback: "0")) = 1 THEN 'manual'
        WHEN \(column("conversationId", fallback: "NULL")) IS NOT NULL THEN 'conversation'
        WHEN \(column("screenshotId", fallback: "NULL")) IS NOT NULL THEN 'screenshot'
        WHEN \(column("source", fallback: "NULL")) IN ('desktop', 'screenshot')
          THEN \(column("source", fallback: "NULL"))
        ELSE NULL
      END
      """
    let reasoningExpression =
      legacyColumns.contains("reasoning") && legacyColumns.contains("tagsJson")
      ? "CASE WHEN tagsJson LIKE '%\"tips\"%' THEN reasoning ELSE NULL END"
      : "NULL"
    let visiblePredicate = legacyColumns.contains("deleted") ? "WHERE deleted = 0" : ""
    let categoryExpression =
      legacyColumns.contains("tagsJson")
      ? "CASE WHEN tagsJson LIKE '%\"tips\"%' THEN 'interesting' ELSE category END"
      : "category"
    let expiryExpression =
      "CASE WHEN \(layerExpression) = 'short_term' THEN datetime(updatedAt, '+30 days') ELSE NULL END"

    try db.execute(
      sql: """
        INSERT INTO memories_s12 (
          id, content, category, layer, expiresAt, revision, tagsJson, manuallyAdded,
          source, conversationId, sourceSegmentId, screenshotId, confidence, reasoning, sourceApp,
          windowTitle, contextSummary, currentActivity, inputDeviceName, isRead,
          isDismissed, pendingDeleteDeadline, createdAt, updatedAt, correctedAt,
          evidenceTokensJson, sensitivityLabelsJson, subject, predicate, argumentsJson
        )
        SELECT
          id, content, \(categoryExpression), \(layerExpression), \(expiryExpression), 1,
          \(column("tagsJson", fallback: "NULL")),
          \(column("manuallyAdded", fallback: "0")),
          \(sourceExpression),
          \(column("conversationId", fallback: "NULL")),
          \(column("sourceSegmentId", fallback: "NULL")),
          \(column("screenshotId", fallback: "NULL")),
          \(column("confidence", fallback: "NULL")),
          \(reasoningExpression),
          \(column("sourceApp", fallback: "NULL")),
          \(column("windowTitle", fallback: "NULL")),
          \(column("contextSummary", fallback: "NULL")),
          \(column("currentActivity", fallback: "NULL")),
          \(column("inputDeviceName", fallback: "NULL")),
          \(column("isRead", fallback: "0")),
          \(column("isDismissed", fallback: "0")),
          NULL, createdAt, updatedAt, NULL, NULL, NULL, NULL, NULL, NULL
        FROM memories
        \(visiblePredicate)
        """)

    try db.drop(table: "memories")
    try db.rename(table: "memories_s12", to: "memories")
  }

  private static func enqueueMigrationWorkIfMissing(
    kind: MemoryProcessingKind,
    memoryID: Int64,
    revision: Int,
    now: Date,
    in db: Database
  ) throws {
    let exists =
      try Bool.fetchOne(
        db,
        sql: """
          SELECT EXISTS(
            SELECT 1 FROM memory_processing_work
            WHERE kind = ? AND memoryId = ? AND inputRevision = ? AND state != ?
          )
          """,
        arguments: [
          kind.rawValue, memoryID, revision, MemoryProcessingState.completed.rawValue,
        ]) ?? false
    guard !exists else { return }
    try MemoryProcessingWorkRecord(
      id: "s12-migration-\(kind.rawValue)-\(memoryID)-r\(revision)",
      memoryId: memoryID,
      conversationId: nil,
      kind: kind.rawValue,
      inputRevision: revision,
      inputGeneration: 0,
      ownerGeneration: 0,
      state: MemoryProcessingState.pending.rawValue,
      attemptCount: 0,
      nextAttemptAt: now,
      leaseExpiresAt: nil,
      lastErrorCode: nil,
      createdAt: now,
      updatedAt: now
    ).insert(db)
  }

  private static func createMemoryAuthorityTables(in db: Database) throws {
    try db.create(index: "idx_memories_created", on: "memories", columns: ["createdAt"], ifNotExists: true)
    try db.create(index: "idx_memories_category", on: "memories", columns: ["category"], ifNotExists: true)
    try db.create(index: "idx_memories_layer", on: "memories", columns: ["layer"], ifNotExists: true)
    try db.create(index: "idx_memories_screenshot", on: "memories", columns: ["screenshotId"], ifNotExists: true)
    try db.create(
      index: "idx_memories_conversation", on: "memories", columns: ["conversationId"], ifNotExists: true)
    try db.create(
      index: "idx_memories_pending_delete", on: "memories", columns: ["pendingDeleteDeadline"],
      ifNotExists: true)

    try db.create(table: "memory_processing_work", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("memoryId", .integer).references("memories", onDelete: .cascade)
      t.column("conversationId", .text)
      t.column("kind", .text).notNull()
      t.column("inputRevision", .integer).notNull()
      t.column("inputGeneration", .integer).notNull()
      t.column("ownerGeneration", .integer).notNull()
      t.column("state", .text).notNull()
      t.column("attemptCount", .integer).notNull().defaults(to: 0)
      t.column("nextAttemptAt", .datetime).notNull()
      t.column("leaseExpiresAt", .datetime)
      t.column("lastErrorCode", .text)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }
    try db.create(
      index: "idx_memory_work_due", on: "memory_processing_work",
      columns: ["state", "nextAttemptAt"], ifNotExists: true)
    try db.create(
      index: "idx_memory_work_memory", on: "memory_processing_work", columns: ["memoryId"],
      ifNotExists: true)
    try db.create(
      index: "idx_memory_work_conversation", on: "memory_processing_work", columns: ["conversationId"],
      ifNotExists: true)

    try db.create(table: "memory_transitions", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("memoryId", .integer).notNull().references("memories", onDelete: .cascade)
      t.column("idempotencyKey", .text).notNull().unique()
      t.column("fromLayer", .text)
      t.column("toLayer", .text)
      t.column("inputRevision", .integer).notNull()
      t.column("outputRevision", .integer).notNull()
      t.column("outcome", .text).notNull()
      t.column("receiptId", .text)
      t.column("createdAt", .datetime).notNull()
    }
    try db.create(
      index: "idx_memory_transitions_memory", on: "memory_transitions", columns: ["memoryId"],
      ifNotExists: true)

    try db.create(table: "memory_embeddings", ifNotExists: true) { t in
      t.column("memoryId", .integer).primaryKey().references("memories", onDelete: .cascade)
      t.column("revision", .integer).notNull()
      t.column("model", .text).notNull()
      t.column("vectorJson", .text).notNull()
      t.column("updatedAt", .datetime).notNull()
    }
  }
}
