import GRDB
import XCTest

@testable import Omi_Computer

final class S14LocalAuthorityMigrationTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "s14-local-authority-schema")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testFreshDatabaseHasOnlyLocalFocusAndProfileColumns() async throws {
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    try await pool.read { db in
      XCTAssertEqual(
        Set(try db.columns(in: "focus_sessions").map(\.name)),
        Set([
          "id", "screenshotId", "status", "appOrSite", "windowTitle", "description", "message",
          "durationSeconds", "createdAt",
        ])
      )
      XCTAssertEqual(
        Set(try db.columns(in: "ai_user_profiles").map(\.name)),
        Set(["id", "profileText", "dataSourcesUsed", "generatedAt"])
      )
      let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
      XCTAssertFalse(indexes.contains("idx_focus_synced"))
    }
  }

  func testUpgradePreservesFocusAndProfileRowsAndLocalIDs() throws {
    let queue = try DatabaseQueue()
    let createdAt = Date(timeIntervalSince1970: 1_730_000_000)
    try queue.write { db in
      try db.create(table: "screenshots") { t in t.autoIncrementedPrimaryKey("id") }
      try db.execute(sql: "INSERT INTO screenshots (id) VALUES (7)")
      try db.create(table: "focus_sessions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("screenshotId", .integer)
        t.column("status", .text).notNull()
        t.column("appOrSite", .text).notNull()
        t.column("windowTitle", .text)
        t.column("description", .text).notNull()
        t.column("message", .text)
        t.column("durationSeconds", .integer)
        t.column("backendId", .text)
        t.column("backendSynced", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
      }
      try db.create(index: "idx_focus_synced", on: "focus_sessions", columns: ["backendSynced"])
      try db.execute(
        sql: """
          INSERT INTO focus_sessions (
            id, screenshotId, status, appOrSite, windowTitle, description, message,
            durationSeconds, backendId, backendSynced, createdAt
          ) VALUES (41, 7, 'focused', 'Xcode', 'Migration.swift', 'Writing tests', 'Keep going',
            90, 'cloud-41', 1, ?)
          """,
        arguments: [createdAt]
      )

      try db.create(table: "ai_user_profiles") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("profileText", .text).notNull()
        t.column("dataSourcesUsed", .integer).notNull()
        t.column("backendSynced", .boolean).notNull().defaults(to: false)
        t.column("generatedAt", .datetime).notNull()
      }
      try db.execute(
        sql: """
          INSERT INTO ai_user_profiles (id, profileText, dataSourcesUsed, backendSynced, generatedAt)
          VALUES (9, '- User writes migration tests.', 4, 1, ?)
          """,
        arguments: [createdAt]
      )

      try RewindDatabase.makeProactiveSurfacesLocalAuthoritative(in: db)
    }

    try queue.read { db in
      let focus = try Row.fetchOne(db, sql: "SELECT * FROM focus_sessions WHERE id = 41")
      XCTAssertEqual(focus?["screenshotId"] as Int64?, 7)
      XCTAssertEqual(focus?["windowTitle"] as String?, "Migration.swift")
      XCTAssertEqual(focus?["message"] as String?, "Keep going")
      XCTAssertEqual(focus?["durationSeconds"] as Int?, 90)

      let profile = try Row.fetchOne(db, sql: "SELECT * FROM ai_user_profiles WHERE id = 9")
      XCTAssertEqual(profile?["profileText"] as String?, "- User writes migration tests.")
      XCTAssertEqual(profile?["dataSourcesUsed"] as Int?, 4)

      XCTAssertFalse(try db.columns(in: "focus_sessions").map(\.name).contains("backendSynced"))
      XCTAssertFalse(try db.columns(in: "focus_sessions").map(\.name).contains("backendId"))
      XCTAssertFalse(try db.columns(in: "ai_user_profiles").map(\.name).contains("backendSynced"))
    }
  }
}
