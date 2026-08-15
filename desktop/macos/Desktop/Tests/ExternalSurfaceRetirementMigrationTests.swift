import GRDB
import XCTest

@testable import Omi_Computer

final class ExternalSurfaceRetirementMigrationTests: XCTestCase {
  func testUpgradeDropsRejectedTablesAndPreservesRetainedRows() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ExternalSurfaceRetirementMigrationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let queue = try DatabaseQueue(path: temporaryDirectory.appendingPathComponent("omi.db").path)
    try queue.write { db in
      for table in ["memories", "action_items", "conversations", "transcription_sessions"] {
        try db.execute(sql: "CREATE TABLE \(table) (id TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try db.execute(sql: "INSERT INTO \(table) (id, value) VALUES ('retained', '\(table)')")
      }
      try db.execute(sql: "ALTER TABLE memories ADD COLUMN visibility TEXT")
      try db.execute(sql: "ALTER TABLE transcription_sessions ADD COLUMN appsResultsJson TEXT")
      try db.execute(sql: "CREATE TABLE indexed_files (id INTEGER PRIMARY KEY)")
      try db.execute(sql: "CREATE TABLE local_kg_nodes (id INTEGER PRIMARY KEY)")
      try db.execute(sql: "CREATE TABLE local_kg_edges (id INTEGER PRIMARY KEY)")
    }

    var migrator = DatabaseMigrator()
    RewindDatabase.registerExternalSurfaceRetirementMigration(on: &migrator)
    try migrator.migrate(queue)

    try queue.read { db in
      for retired in ["indexed_files", "local_kg_nodes", "local_kg_edges"] {
        XCTAssertFalse(try db.tableExists(retired), "\(retired) must be absent after upgrade")
      }
      XCTAssertFalse(try db.columns(in: "memories").contains(where: { $0.name == "visibility" }))
      XCTAssertFalse(
        try db.columns(in: "transcription_sessions").contains(where: { $0.name == "appsResultsJson" })
      )
      for retained in ["memories", "action_items", "conversations", "transcription_sessions"] {
        XCTAssertTrue(try db.tableExists(retained))
        XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM \(retained) WHERE id = 'retained'"), retained)
      }
    }
  }

  func testMigrationIsSafeWhenRejectedTablesAreAlreadyAbsent() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ExternalSurfaceRetirementMigrationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let queue = try DatabaseQueue(path: temporaryDirectory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerExternalSurfaceRetirementMigration(on: &migrator)
    XCTAssertNoThrow(try migrator.migrate(queue))
  }
}
