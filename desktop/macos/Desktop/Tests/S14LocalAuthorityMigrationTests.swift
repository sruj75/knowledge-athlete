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
      XCTAssertFalse(try db.tableExists("proactive_extractions"))
      XCTAssertFalse(try db.tableExists("proactive_extractions_fts"))
      let residue = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE name LIKE 'proactive_extractions%' OR name LIKE 'extractions_%'")
      XCTAssertEqual(residue, [])
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

  func testRetirementCopiesUnmatchedMemoryAdviceAndTaskRowsExactlyOnceThenDropsResidue() throws {
    let queue = try DatabaseQueue()
    let createdAt = Date(timeIntervalSince1970: 1_731_000_000)
    try queue.write { db in
      try Self.createCanonicalExtractionTargets(in: db)
      try Self.createLegacyProactiveExtractions(in: db)
      try db.execute(
        sql: """
          INSERT INTO memories (
            content, category, layer, revision, source, sourceApp, createdAt, updatedAt
          ) VALUES ('Already canonical memory', 'system', 'short_term', 1, 'screenshot', 'Notes', ?, ?)
          """,
        arguments: [createdAt, createdAt])
      try Self.insertLegacyExtraction(
        type: "memory", content: "Already canonical memory", category: "system",
        sourceApp: "Notes", createdAt: createdAt, in: db)
      try Self.insertLegacyExtraction(
        type: "memory", content: "Unmatched local memory", category: "system",
        sourceApp: "Safari", createdAt: createdAt.addingTimeInterval(1), in: db)
      try Self.insertLegacyExtraction(
        type: "advice", content: "Take a short walk", category: "wellbeing",
        sourceApp: "Calendar", createdAt: createdAt.addingTimeInterval(2), in: db)
      try Self.insertLegacyExtraction(
        type: "task", content: "Send the draft", category: "work", priority: "high",
        sourceApp: "Mail", createdAt: createdAt.addingTimeInterval(3), in: db)

      try RewindDatabase.retireProactiveExtractionsAuthority(in: db)
    }

    try queue.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM memories WHERE content = 'Already canonical memory'"),
        1)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memories WHERE content = 'Unmatched local memory'"),
        1)
      let tip = try Row.fetchOne(db, sql: "SELECT * FROM memories WHERE content = 'Take a short walk'")
      XCTAssertEqual(tip?["category"] as String?, "interesting")
      XCTAssertEqual(tip?["tagsJson"] as String?, "[\"tips\",\"wellbeing\"]")
      XCTAssertEqual(tip?["reasoning"] as String?, "fixture reasoning")

      let task = try Row.fetchOne(db, sql: "SELECT * FROM action_items WHERE description = 'Send the draft'")
      XCTAssertEqual(task?["priority"] as String?, "high")
      XCTAssertEqual(task?["source"] as String?, "screenshot")

      let residue = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE name LIKE 'proactive_extractions%' OR name LIKE 'extractions_%'")
      XCTAssertEqual(residue, [])
    }
  }

  func testRetirementFailsClosedForUnknownLegacyType() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try Self.createCanonicalExtractionTargets(in: db)
      try Self.createLegacyProactiveExtractions(in: db)
      try Self.insertLegacyExtraction(
        type: "surprise", content: "Unknown", category: nil, sourceApp: "Unknown",
        createdAt: Date(timeIntervalSince1970: 1_732_000_000), in: db)
    }

    XCTAssertThrowsError(
      try queue.write { db in
        try RewindDatabase.retireProactiveExtractionsAuthority(in: db)
      }
    ) { error in
      guard case ProactiveAuthorityRetirementError.unknownLegacyTypes(let types) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(types, ["surprise"])
    }
    try queue.read { db in
      XCTAssertTrue(try db.tableExists("proactive_extractions"))
    }
  }

  private static func createCanonicalExtractionTargets(in db: Database) throws {
    try db.create(table: "memories") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("content", .text).notNull()
      t.column("category", .text).notNull()
      t.column("layer", .text).notNull()
      t.column("expiresAt", .datetime)
      t.column("revision", .integer).notNull()
      t.column("tagsJson", .text)
      t.column("manuallyAdded", .boolean).notNull().defaults(to: false)
      t.column("source", .text)
      t.column("screenshotId", .integer)
      t.column("confidence", .double)
      t.column("reasoning", .text)
      t.column("sourceApp", .text)
      t.column("contextSummary", .text)
      t.column("isRead", .boolean).notNull().defaults(to: false)
      t.column("isDismissed", .boolean).notNull().defaults(to: false)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }
    try db.create(table: "action_items") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("description", .text).notNull()
      t.column("completed", .boolean).notNull().defaults(to: false)
      t.column("deleted", .boolean).notNull().defaults(to: false)
      t.column("source", .text)
      t.column("priority", .text)
      t.column("screenshotId", .integer)
      t.column("confidence", .double)
      t.column("sourceApp", .text)
      t.column("contextSummary", .text)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }
  }

  private static func createLegacyProactiveExtractions(in db: Database) throws {
    try db.create(table: "proactive_extractions") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("screenshotId", .integer)
      t.column("type", .text).notNull()
      t.column("content", .text).notNull()
      t.column("category", .text)
      t.column("confidence", .double)
      t.column("reasoning", .text)
      t.column("sourceApp", .text).notNull()
      t.column("contextSummary", .text)
      t.column("priority", .text)
      t.column("isRead", .boolean).notNull().defaults(to: false)
      t.column("isDismissed", .boolean).notNull().defaults(to: false)
      t.column("backendId", .text)
      t.column("backendSynced", .boolean).notNull().defaults(to: false)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }
    for index in [
      "idx_extractions_type", "idx_extractions_screenshot", "idx_extractions_synced",
      "idx_extractions_created", "idx_extractions_type_created",
    ] {
      try db.execute(sql: "CREATE INDEX \(index) ON proactive_extractions(type)")
    }
    try db.execute(sql: "CREATE VIRTUAL TABLE proactive_extractions_fts USING fts5(content)")
    try db.execute(
      sql: """
        CREATE TRIGGER extractions_ai AFTER INSERT ON proactive_extractions BEGIN
          INSERT INTO proactive_extractions_fts(rowid, content) VALUES (new.id, new.content);
        END
        """)
    try db.execute(
      sql: "CREATE TRIGGER extractions_ad AFTER DELETE ON proactive_extractions BEGIN SELECT 1; END")
    try db.execute(
      sql: "CREATE TRIGGER extractions_au AFTER UPDATE ON proactive_extractions BEGIN SELECT 1; END")
  }

  private static func insertLegacyExtraction(
    type: String,
    content: String,
    category: String?,
    priority: String? = nil,
    sourceApp: String,
    createdAt: Date,
    in db: Database
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO proactive_extractions (
          type, content, category, confidence, reasoning, sourceApp, contextSummary,
          priority, isRead, isDismissed, backendSynced, createdAt, updatedAt
        ) VALUES (?, ?, ?, 0.91, 'fixture reasoning', ?, 'fixture context', ?, 1, 0, 0, ?, ?)
        """,
      arguments: [type, content, category, sourceApp, priority, createdAt, createdAt])
  }
}
