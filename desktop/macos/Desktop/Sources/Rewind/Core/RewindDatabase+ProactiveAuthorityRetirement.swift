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
          WHERE legacy.type IN ('memory', 'advice')
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
          ORDER BY legacy.id
          """)

      try db.execute(
        sql: """
          INSERT INTO action_items (
            description, completed, deleted, source, priority, screenshotId,
            confidence, sourceApp, contextSummary, createdAt, updatedAt
          )
          SELECT
            legacy.content, 0, 0, 'screenshot', legacy.priority, legacy.screenshotId,
            legacy.confidence, legacy.sourceApp, legacy.contextSummary,
            legacy.createdAt, legacy.updatedAt
          FROM proactive_extractions AS legacy
          WHERE legacy.type = 'task'
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
