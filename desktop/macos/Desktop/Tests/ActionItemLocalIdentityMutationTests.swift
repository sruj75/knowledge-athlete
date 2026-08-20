import GRDB
import XCTest

@testable import Omi_Computer

final class ActionItemLocalIdentityMutationTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "local-task-identity")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testOnlyPositiveLocalRowIDsAreAccepted() {
    XCTAssertEqual(ActionItemStorage.localRowID(surfacedId: "local_42"), 42)
    XCTAssertNil(ActionItemStorage.localRowID(surfacedId: "42"))
    XCTAssertNil(ActionItemStorage.localRowID(surfacedId: "backend-id"))
    XCTAssertNil(ActionItemStorage.localRowID(surfacedId: "local_0"))
    XCTAssertNil(ActionItemStorage.localRowID(surfacedId: "local_x"))
  }

  func testCRUDKeepsOneStableLocalIdentityAcrossReload() async throws {
    let dueAt = Date().addingTimeInterval(3_600)
    let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(
        description: "local task",
        source: "manual",
        priority: "high",
        dueAt: dueAt,
        sortOrder: 123
      ),
      authorization: .unrestricted
    )
    let surfacedID = inserted.toTaskActionItem().id
    XCTAssertEqual(surfacedID, "local_\(try XCTUnwrap(inserted.id))")

    try await ActionItemStorage.shared.updateActionItemFields(
      surfacedId: surfacedID,
      description: "renamed locally",
      priority: "low",
      authorization: .unrestricted
    )
    let completed = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
      surfacedId: surfacedID,
      completed: true,
      nextDueAt: nil,
      authorization: .unrestricted
    )
    XCTAssertEqual(completed.task.id, surfacedID)

    try await ActionItemStorage.shared.softDelete(
      surfacedId: surfacedID,
      authorization: .unrestricted
    )
    let restored = try await ActionItemStorage.shared.restoreActionItem(
      surfacedId: surfacedID,
      authorization: .unrestricted
    )
    XCTAssertEqual(restored.id, surfacedID)
    XCTAssertEqual(restored.description, "renamed locally")
    XCTAssertEqual(restored.priority, "low")
    XCTAssertEqual(restored.dueAt, dueAt)
    XCTAssertEqual(restored.sortOrder, 123)
    XCTAssertTrue(restored.completed)

    await ActionItemStorage.shared.invalidateCache()
    let afterReload = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: surfacedID)
    XCTAssertEqual(afterReload?.id, surfacedID)
    XCTAssertEqual(afterReload?.description, "renamed locally")
  }

  func testInvalidAndOtherOwnerIDsDoNotResolve() async throws {
    let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(description: "owner A task", source: "manual"),
      authorization: .unrestricted
    )
    let ownerASurfacedID = inserted.toTaskActionItem().id
    let invalidLookup = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: "remote-id")
    XCTAssertNil(invalidLookup)

    let ownerB = "local-task-owner-b-\(UUID().uuidString)"
    let ownerBDirectory = RewindStorageTestIsolation.userDirectory(for: ownerB)
    defer { try? FileManager.default.removeItem(at: ownerBDirectory) }
    try await RewindDatabase.shared.switchUser(to: ownerB)
    await ActionItemStorage.shared.invalidateCache()

    let crossOwnerLookup = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: ownerASurfacedID)
    XCTAssertNil(crossOwnerLookup)
  }

  func testRecurringCompletionIsExactlyOnceAndCopiesOnlyRetainedFields() async throws {
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    let conversationID = "conversation-\(UUID().uuidString)"
    let timestamp = Date(timeIntervalSince1970: 1_735_000_000)
    try await pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO transcription_sessions (
            conversationId, startedAt, language, timezone, status, createdAt, updatedAt
          ) VALUES (?, ?, 'en', 'UTC', 'completed', ?, ?)
          """,
        arguments: [conversationID, timestamp, timestamp, timestamp]
      )
    }
    let dueAt = timestamp.addingTimeInterval(3_600)
    let nextDueAt = dueAt.addingTimeInterval(86_400)
    let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(
        description: "Recurring local task",
        source: "manual",
        conversationId: conversationID,
        priority: "high",
        dueAt: dueAt,
        recurrenceRule: "daily",
        provenanceJson: "[]",
        confidence: 0.96,
        sourceApp: "Calendar",
        windowTitle: "Plan",
        contextSummary: "Planning",
        currentActivity: "Reviewing the plan",
        sortOrder: 37,
        createdAt: timestamp,
        updatedAt: timestamp
      ),
      authorization: .unrestricted
    )
    let surfacedID = inserted.toTaskActionItem().id

    let first = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
      surfacedId: surfacedID,
      completed: true,
      nextDueAt: nextDueAt,
      authorization: .unrestricted
    )
    let second = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
      surfacedId: surfacedID,
      completed: true,
      nextDueAt: nextDueAt,
      authorization: .unrestricted
    )

    XCTAssertTrue(first.task.completed)
    XCTAssertEqual(first.task.id, surfacedID)
    let child = try XCTUnwrap(first.next)
    XCTAssertNil(second.next, "replaying completion must not create another occurrence")
    XCTAssertNotEqual(child.id, surfacedID)
    XCTAssertEqual(child.description, "Recurring local task")
    XCTAssertEqual(child.conversationId, conversationID)
    XCTAssertEqual(child.priority, "high")
    XCTAssertEqual(child.dueAt, nextDueAt)
    XCTAssertEqual(child.recurrenceRule, "daily")
    XCTAssertEqual(child.recurrenceParentId, surfacedID)
    XCTAssertEqual(child.provenance, [])
    XCTAssertEqual(child.confidence, 0.96)
    XCTAssertEqual(child.sourceApp, "Calendar")
    XCTAssertEqual(child.windowTitle, "Plan")
    XCTAssertEqual(child.contextSummary, "Planning")
    XCTAssertEqual(child.currentActivity, "Reviewing the plan")
    XCTAssertEqual(child.sortOrder, 37)

    let count = try await pool.read { db in try ActionItemRecord.fetchCount(db) }
    XCTAssertEqual(count, 2)

    _ = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
      surfacedId: surfacedID,
      completed: false,
      nextDueAt: nil,
      authorization: .unrestricted
    )
    let replay = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
      surfacedId: surfacedID,
      completed: true,
      nextDueAt: nextDueAt,
      authorization: .unrestricted
    )
    XCTAssertEqual(replay.next?.id, child.id, "re-completing must reuse the existing future row")
    let replayCount = try await pool.read { db in try ActionItemRecord.fetchCount(db) }
    XCTAssertEqual(replayCount, 2)
  }

  func testRecurringCompletionRollsBackParentWhenChildInsertFails() async throws {
    let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(
        description: "Atomic recurrence",
        source: "manual",
        dueAt: Date(timeIntervalSince1970: 1_735_000_000),
        recurrenceRule: "daily"
      ),
      authorization: .unrestricted
    )
    let surfacedID = inserted.toTaskActionItem().id
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    try await pool.write { db in
      try db.execute(
        sql: """
          CREATE TRIGGER fail_s13_recurrence_insert
          BEFORE INSERT ON action_items
          WHEN NEW.recurrenceParentId IS NOT NULL
          BEGIN
            SELECT RAISE(ABORT, 'injected recurrence insert failure');
          END
          """)
    }

    do {
      _ = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
        surfacedId: surfacedID,
        completed: true,
        nextDueAt: Date(timeIntervalSince1970: 1_735_086_400),
        authorization: .unrestricted
      )
      XCTFail("expected injected child insert failure")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("injected recurrence insert failure"))
    }

    let parent = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: surfacedID)
    XCTAssertEqual(parent?.completed, false)
    XCTAssertNil(parent?.completedAt)
    let count = try await pool.read { db in try ActionItemRecord.fetchCount(db) }
    XCTAssertEqual(count, 1)
  }

  @MainActor
  func testEveryRecurrenceRuleAdvancesPastMissedBacklog() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: 2025, month: 1, day: 6, hour: 10)))
    let cases: [(rule: String, due: DateComponents, expected: DateComponents)] = [
      ("daily", .init(year: 2025, month: 1, day: 5, hour: 9), .init(year: 2025, month: 1, day: 7, hour: 9)),
      ("weekdays", .init(year: 2025, month: 1, day: 3, hour: 9), .init(year: 2025, month: 1, day: 7, hour: 9)),
      ("weekly", .init(year: 2024, month: 12, day: 23, hour: 9), .init(year: 2025, month: 1, day: 13, hour: 9)),
      ("biweekly", .init(year: 2024, month: 12, day: 9, hour: 9), .init(year: 2025, month: 1, day: 20, hour: 9)),
      ("monthly", .init(year: 2024, month: 11, day: 6, hour: 9), .init(year: 2025, month: 2, day: 6, hour: 9)),
    ]

    for item in cases {
      let due = try XCTUnwrap(calendar.date(from: item.due))
      let expected = try XCTUnwrap(calendar.date(from: item.expected))
      let task = TaskActionItem(
        id: "local_1",
        description: item.rule,
        completed: false,
        createdAt: due,
        dueAt: due,
        recurrenceRule: item.rule
      )
      XCTAssertEqual(
        TasksStore.nextFutureDueDate(for: task, now: now, calendar: calendar),
        expected,
        item.rule
      )
    }
  }

  func testStorageNormalizesTypedTaskFieldsAndRejectsUnknownValues() async throws {
    let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(
        description: "Typed task fields",
        source: "manual",
        priority: "High",
        recurrenceRule: "Weekly"
      ),
      authorization: .unrestricted
    )
    XCTAssertEqual(inserted.priority, "high")
    XCTAssertEqual(inserted.recurrenceRule, "weekly")

    do {
      _ = try await ActionItemStorage.shared.insertLocalActionItem(
        ActionItemRecord(description: "Invalid priority", priority: "urgent"),
        authorization: .unrestricted
      )
      XCTFail("expected invalid priority rejection")
    } catch ActionItemStorageError.invalidPriority {
      // Expected.
    }

    do {
      try await ActionItemStorage.shared.updateActionItemFields(
        surfacedId: inserted.toTaskActionItem().id,
        recurrenceRule: "quarterly",
        authorization: .unrestricted
      )
      XCTFail("expected invalid recurrence rejection")
    } catch ActionItemStorageError.invalidRecurrence {
      // Expected.
    }
  }
}
