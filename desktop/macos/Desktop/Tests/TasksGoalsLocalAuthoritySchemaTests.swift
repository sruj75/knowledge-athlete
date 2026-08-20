import GRDB
import XCTest

@testable import Omi_Computer

final class TasksGoalsLocalAuthoritySchemaTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "tasks-goals-schema")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testFreshDatabaseConvergesOnRetainedTaskGoalAndObservationSchema() async throws {
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)

    try await pool.read { db in
      let taskColumns = Set(try db.columns(in: "action_items").map(\.name))
      XCTAssertEqual(
        taskColumns,
        Set([
          "id", "description", "completed", "deleted", "source", "conversationId", "priority",
          "deletedBy", "deletedAt", "dueAt", "completedAt", "recurrenceRule", "recurrenceParentId",
          "provenanceJson", "screenshotId", "confidence", "sourceApp", "windowTitle", "contextSummary",
          "currentActivity", "embedding", "sortOrder", "createdAt", "updatedAt",
        ]))

      let goalColumns = Set(try db.columns(in: "goals").map(\.name))
      XCTAssertEqual(
        goalColumns,
        Set(["id", "title", "goalDescription", "isActive", "completedAt", "createdAt", "updatedAt"]))

      let observationColumns = Set(try db.columns(in: "observations").map(\.name))
      XCTAssertEqual(
        observationColumns,
        Set([
          "id", "screenshotId", "appName", "contextSummary", "currentActivity", "hasTask", "taskTitle",
          "metadataJson", "createdAt",
        ]))

      for retiredTable in ["staged_tasks", "staged_tasks_fts", "task_chat_messages", "task_chat_messages_fts"] {
        XCTAssertFalse(try db.tableExists(retiredTable), "retired table remains: \(retiredTable)")
      }
      XCTAssertTrue(try db.tableExists("action_items_fts"))

      let schemaObjects = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index', 'trigger')"
      )
      for retiredFragment in ["staged_tasks", "task_chat_messages"] {
        XCTAssertFalse(
          schemaObjects.contains(where: { $0.contains(retiredFragment) }),
          "retired schema object remains: \(retiredFragment)"
        )
      }
    }
  }

  func testUpgradedDatabasePreservesLocalIDsAndValidSourceLinksWhileDroppingRejectedProducts() throws {
    let queue = try DatabaseQueue()
    let createdAt = Date(timeIntervalSince1970: 1_730_000_000)
    let updatedAt = createdAt.addingTimeInterval(600)
    try queue.write { db in
      try db.create(table: "transcription_sessions") { t in
        t.column("conversationId", .text).primaryKey()
      }
      try db.execute(
        sql: "INSERT INTO transcription_sessions (conversationId) VALUES ('conversation-retained')")
      try db.create(table: "screenshots") { t in t.autoIncrementedPrimaryKey("id") }
      try db.create(table: "action_items") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("backendId", .text)
        t.column("backendSynced", .boolean).notNull().defaults(to: false)
        t.column("description", .text).notNull()
        t.column("completed", .boolean).notNull().defaults(to: false)
        t.column("deleted", .boolean).notNull().defaults(to: false)
        t.column("source", .text)
        t.column("conversationId", .text)
        t.column("priority", .text)
        t.column("category", .text)
        t.column("tagsJson", .text)
        t.column("deletedBy", .text)
        t.column("dueAt", .datetime)
        t.column("completedAt", .datetime)
        t.column("recurrenceRule", .text)
        t.column("recurrenceParentId", .text)
        t.column("provenanceJson", .text)
        t.column("screenshotId", .integer)
        t.column("confidence", .double)
        t.column("sourceApp", .text)
        t.column("windowTitle", .text)
        t.column("contextSummary", .text)
        t.column("currentActivity", .text)
        t.column("metadataJson", .text)
        t.column("embedding", .blob)
        t.column("sortOrder", .integer)
        t.column("relevanceScore", .integer)
        t.column("agentStatus", .text)
        t.column("goalId", .text)
        t.column("workstreamId", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
      }
      try db.execute(
        sql: """
          INSERT INTO action_items (
            id, backendId, backendSynced, description, completed, deleted, source, conversationId,
            priority, category, tagsJson, recurrenceRule, provenanceJson, confidence, sourceApp,
            windowTitle, contextSummary, currentActivity, sortOrder, relevanceScore, agentStatus,
            goalId, workstreamId, createdAt, updatedAt
          ) VALUES (
            41, 'cloud-41', 1, 'Retained task', 0, 0, 'conversation', 'conversation-retained',
            'high', 'work', '[\"planning\"]', 'weekly', '[]', 0.98, 'Calendar',
            'Weekly plan', 'Plan the week', 'Reviewing calendar', 77, 99, 'running',
            'goal-cloud', 'workstream-cloud', ?, ?
          )
          """,
        arguments: [createdAt, updatedAt]
      )
      try db.execute(
        sql: """
          INSERT INTO action_items (
            id, description, completed, deleted, source, conversationId, deletedBy, createdAt, updatedAt
          ) VALUES (42, 'Deleted task', 0, 1, 'manual', 'missing-conversation', 'user', ?, ?)
          """,
        arguments: [createdAt, updatedAt]
      )

      try db.create(table: "observations") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("screenshotId", .integer)
        t.column("appName", .text).notNull()
        t.column("contextSummary", .text).notNull()
        t.column("currentActivity", .text).notNull()
        t.column("hasTask", .boolean).notNull().defaults(to: false)
        t.column("taskTitle", .text)
        t.column("sourceCategory", .text)
        t.column("sourceSubcategory", .text)
        t.column("metadataJson", .text)
        t.column("createdAt", .datetime).notNull()
      }
      try db.execute(
        sql: """
          INSERT INTO observations (
            id, appName, contextSummary, currentActivity, hasTask, taskTitle,
            sourceCategory, sourceSubcategory, createdAt
          ) VALUES (6, 'Calendar', 'Planning', 'Reviewing', 1, 'Retained task', 'work', 'planning', ?)
          """,
        arguments: [createdAt]
      )

      try db.create(table: "goals") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("backendId", .text)
        t.column("backendSynced", .boolean).notNull().defaults(to: false)
        t.column("title", .text).notNull()
        t.column("goalDescription", .text)
        t.column("goalType", .text)
        t.column("targetValue", .double)
        t.column("currentValue", .double)
        t.column("minValue", .double)
        t.column("maxValue", .double)
        t.column("unit", .text)
        t.column("isActive", .boolean).notNull().defaults(to: true)
        t.column("completedAt", .datetime)
        t.column("deleted", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
      }
      try db.execute(
        sql: """
          INSERT INTO goals (
            id, backendId, title, goalDescription, goalType, targetValue, currentValue,
            minValue, maxValue, unit, isActive, deleted, createdAt, updatedAt
          ) VALUES (9, 'cloud-goal', 'Ship S-13', 'Keep it local', 'numeric', 10, 4, 0, 10, 'steps', 1, 0, ?, ?)
          """,
        arguments: [createdAt, updatedAt]
      )
      try db.execute(
        sql: """
          INSERT INTO goals (id, title, isActive, deleted, createdAt, updatedAt)
          VALUES (10, 'Deleted goal', 0, 1, ?, ?)
          """,
        arguments: [createdAt, updatedAt]
      )

      for table in [
        "action_items_fts", "staged_tasks", "staged_tasks_fts", "task_chat_messages", "task_chat_messages_fts",
      ] {
        try db.create(table: table) { t in t.column("value", .text) }
      }

      try RewindDatabase.makeTasksAndGoalsLocalAuthoritative(in: db)
    }

    try queue.read { db in
      let retainedTask = try Row.fetchOne(db, sql: "SELECT * FROM action_items WHERE id = 41")
      XCTAssertEqual(retainedTask?["description"] as String?, "Retained task")
      XCTAssertEqual(retainedTask?["conversationId"] as String?, "conversation-retained")
      XCTAssertEqual(retainedTask?["priority"] as String?, "high")
      XCTAssertEqual(retainedTask?["recurrenceRule"] as String?, "weekly")
      XCTAssertEqual(retainedTask?["sortOrder"] as Int?, 77)

      let deletedTask = try Row.fetchOne(db, sql: "SELECT * FROM action_items WHERE id = 42")
      XCTAssertNil(deletedTask?["conversationId"] as String?)
      XCTAssertEqual(deletedTask?["deletedAt"] as Date?, updatedAt)

      let taskColumns = Set(try db.columns(in: "action_items").map(\.name))
      for retired in [
        "backendId", "backendSynced", "category", "tagsJson", "metadataJson", "relevanceScore",
        "agentStatus", "goalId", "workstreamId",
      ] {
        XCTAssertFalse(taskColumns.contains(retired), "retired task column remains: \(retired)")
      }

      let retainedGoal = try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 9")
      XCTAssertEqual(retainedGoal?["title"] as String?, "Ship S-13")
      XCTAssertEqual(retainedGoal?["goalDescription"] as String?, "Keep it local")
      XCTAssertNil(try Row.fetchOne(db, sql: "SELECT * FROM goals WHERE id = 10"))

      let retainedObservation = try Row.fetchOne(db, sql: "SELECT * FROM observations WHERE id = 6")
      XCTAssertEqual(retainedObservation?["taskTitle"] as String?, "Retained task")
      XCTAssertFalse(try db.columns(in: "observations").map(\.name).contains("sourceCategory"))
      for retiredTable in ["staged_tasks", "staged_tasks_fts", "task_chat_messages", "task_chat_messages_fts"] {
        XCTAssertFalse(try db.tableExists(retiredTable), "retired table remains: \(retiredTable)")
      }
      XCTAssertTrue(try db.tableExists("action_items_fts"))
    }
  }
}
