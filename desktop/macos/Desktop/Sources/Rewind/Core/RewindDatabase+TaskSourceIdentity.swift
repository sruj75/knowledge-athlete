import GRDB

extension RewindDatabase {
  static func registerTaskSourceIdentityMigration(on migrator: inout DatabaseMigrator) {
    migrator.registerMigration("neutralizeRetiredTaskSourcesS30") { db in
      try db.execute(
        sql: "UPDATE action_items SET source = 'task' WHERE source = 'transcription:omi'"
      )
    }
  }
}
