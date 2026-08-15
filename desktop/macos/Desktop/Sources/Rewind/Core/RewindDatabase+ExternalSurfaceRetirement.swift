import GRDB

extension RewindDatabase {
  static func registerExternalSurfaceRetirementMigration(on migrator: inout DatabaseMigrator) {
    migrator.registerMigration("retireExternalDataSurfacesS06") { db in
      // Drop dependents before owners. Historical create migrations stay registered
      // so both upgraded and fresh databases converge on this retained schema.
      try db.execute(sql: "DROP TABLE IF EXISTS local_kg_edges")
      try db.execute(sql: "DROP TABLE IF EXISTS local_kg_nodes")
      try db.execute(sql: "DROP TABLE IF EXISTS indexed_files")
      if try db.tableExists("memories"),
        try db.columns(in: "memories").contains(where: { $0.name == "visibility" })
      {
        try db.execute(sql: "ALTER TABLE memories DROP COLUMN visibility")
      }
      if try db.tableExists("transcription_sessions"),
        try db.columns(in: "transcription_sessions").contains(where: { $0.name == "appsResultsJson" })
      {
        try db.execute(sql: "ALTER TABLE transcription_sessions DROP COLUMN appsResultsJson")
      }
    }
  }
}
