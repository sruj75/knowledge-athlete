import Foundation
import GRDB

enum ProactiveAuthorityRetirementError: Error, Equatable {
  case unknownLegacyTypes([String])
}

extension RewindDatabase {
  static func registerProactiveAuthorityRetirementMigration(on migrator: inout DatabaseMigrator) {
    migrator.registerMigration("retireProactiveExtractionsAuthority") { db in
      try retireProactiveExtractionsAuthority(in: db)
    }
  }

  static func retireProactiveExtractionsAuthority(in db: Database) throws {
    if try db.tableExists("proactive_extractions") {
      let unknownTypes = try String.fetchAll(
        db,
        sql: """
          SELECT DISTINCT type
          FROM proactive_extractions
          WHERE type NOT IN ('memory', 'advice', 'task')
          ORDER BY type
          """)
      guard unknownTypes.isEmpty else {
        throw ProactiveAuthorityRetirementError.unknownLegacyTypes(unknownTypes)
      }

      try db.execute(
        sql: """
          CREATE TEMP TABLE wave2_proactive_memories_to_copy (
            legacyId INTEGER PRIMARY KEY
          )
          """)
      try db.execute(
        sql: """
          INSERT INTO wave2_proactive_memories_to_copy (legacyId)
          WITH ranked AS (
            SELECT
              legacy.id,
              ROW_NUMBER() OVER (
                PARTITION BY
                  legacy.content,
                  legacy.createdAt,
                  legacy.screenshotId,
                  legacy.sourceApp,
                  CASE
                    WHEN legacy.type = 'advice' THEN 'interesting'
                    WHEN legacy.category IN ('system', 'interesting', 'manual') THEN legacy.category
                    ELSE 'system'
                  END
                ORDER BY legacy.id
              ) AS copyRank
            FROM proactive_extractions AS legacy
            WHERE legacy.type IN ('memory', 'advice')
          )
          SELECT ranked.id
          FROM ranked
          JOIN proactive_extractions AS legacy ON legacy.id = ranked.id
          WHERE ranked.copyRank = 1
            AND NOT EXISTS (
              SELECT 1
              FROM memories AS canonical
              WHERE canonical.content = legacy.content
                AND canonical.createdAt = legacy.createdAt
                AND canonical.screenshotId IS legacy.screenshotId
                AND canonical.sourceApp IS legacy.sourceApp
                AND canonical.category = CASE
                  WHEN legacy.type = 'advice' THEN 'interesting'
                  WHEN legacy.category IN ('system', 'interesting', 'manual') THEN legacy.category
                  ELSE 'system'
                END
            )
          """)

      try db.execute(
        sql: """
          INSERT INTO memories (
            content, category, layer, expiresAt, revision, tagsJson, manuallyAdded,
            source, screenshotId, confidence, reasoning, sourceApp, contextSummary,
            isRead, isDismissed, createdAt, updatedAt
          )
          SELECT
            legacy.content,
            CASE
              WHEN legacy.type = 'advice' THEN 'interesting'
              WHEN legacy.category IN ('system', 'interesting', 'manual') THEN legacy.category
              ELSE 'system'
            END,
            'short_term', datetime(legacy.updatedAt, '+30 days'), 1,
            CASE
              WHEN legacy.type = 'advice'
                THEN json_array('tips', COALESCE(legacy.category, 'other'))
              ELSE NULL
            END,
            0, 'screenshot', legacy.screenshotId, legacy.confidence,
            CASE WHEN legacy.type = 'advice' THEN legacy.reasoning ELSE NULL END,
            legacy.sourceApp, legacy.contextSummary, legacy.isRead, legacy.isDismissed,
            legacy.createdAt, legacy.updatedAt
          FROM proactive_extractions AS legacy
          JOIN wave2_proactive_memories_to_copy AS selected ON selected.legacyId = legacy.id
          ORDER BY legacy.id
          """)

      if try db.tableExists("memory_processing_work") {
        let now = Date()
        for kind in [MemoryProcessingKind.consolidate, .embed] {
          try db.execute(
            sql: """
              INSERT INTO memory_processing_work (
                id, memoryId, conversationId, kind, inputRevision, inputGeneration,
                ownerGeneration, state, attemptCount, nextAttemptAt, leaseExpiresAt,
                lastErrorCode, createdAt, updatedAt
              )
              SELECT
                'wave2-proactive-retirement-' || ? || '-' || canonical.id || '-r1',
                canonical.id, NULL, ?, 1, 0, 0, 'pending', 0, ?, NULL, NULL, ?, ?
              FROM wave2_proactive_memories_to_copy AS selected
              JOIN proactive_extractions AS legacy ON legacy.id = selected.legacyId
              JOIN memories AS canonical
                ON canonical.content = legacy.content
                AND canonical.createdAt = legacy.createdAt
                AND canonical.screenshotId IS legacy.screenshotId
                AND canonical.sourceApp IS legacy.sourceApp
                AND canonical.category = CASE
                  WHEN legacy.type = 'advice' THEN 'interesting'
                  WHEN legacy.category IN ('system', 'interesting', 'manual') THEN legacy.category
                  ELSE 'system'
                END
              WHERE NOT EXISTS (
                SELECT 1
                FROM memory_processing_work AS work
                WHERE work.kind = ?
                  AND work.memoryId = canonical.id
                  AND work.inputRevision = 1
              )
              """,
            arguments: [kind.rawValue, kind.rawValue, now, now, now, kind.rawValue])
        }
      }
      try db.execute(sql: "DROP TABLE wave2_proactive_memories_to_copy")

      try db.execute(
        sql: """
          WITH ranked AS (
            SELECT
              legacy.*,
              ROW_NUMBER() OVER (
                PARTITION BY legacy.content, legacy.createdAt, legacy.screenshotId, legacy.sourceApp
                ORDER BY legacy.id
              ) AS copyRank
            FROM proactive_extractions AS legacy
            WHERE legacy.type = 'task'
          )
          INSERT INTO action_items (
            description, completed, deleted, source, priority, screenshotId,
            confidence, sourceApp, contextSummary, createdAt, updatedAt
          )
          SELECT
            legacy.content, 0, 0, 'screenshot', legacy.priority, legacy.screenshotId,
            legacy.confidence, legacy.sourceApp, legacy.contextSummary,
            legacy.createdAt, legacy.updatedAt
          FROM ranked AS legacy
          WHERE legacy.copyRank = 1
            AND NOT EXISTS (
              SELECT 1
              FROM action_items AS canonical
              WHERE canonical.description = legacy.content
                AND canonical.createdAt = legacy.createdAt
                AND canonical.screenshotId IS legacy.screenshotId
                AND canonical.sourceApp IS legacy.sourceApp
            )
          ORDER BY legacy.id
          """)
    }

    for trigger in ["extractions_ai", "extractions_ad", "extractions_au"] {
      try db.execute(sql: "DROP TRIGGER IF EXISTS \(trigger)")
    }
    for index in [
      "idx_extractions_type", "idx_extractions_screenshot", "idx_extractions_synced",
      "idx_extractions_created", "idx_extractions_type_created",
    ] {
      try db.execute(sql: "DROP INDEX IF EXISTS \(index)")
    }
    try db.execute(sql: "DROP TABLE IF EXISTS proactive_extractions_fts")
    try db.execute(sql: "DROP TABLE IF EXISTS proactive_extractions")
  }
}
