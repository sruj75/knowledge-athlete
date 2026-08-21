import GRDB
import XCTest

@testable import Omi_Computer

@MainActor
final class DailyRecapLocalAuthorityTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    ownerFixture = fixture
    await fixture.establish(authOwnerID: "daily-recap-owner")
  }

  override func tearDown() async throws {
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
  }

  func testCurrentSchemasProduceSixSectionsWithReviewedBoundsAndArbitraryPeriod() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = Date(timeIntervalSince1970: 1_704_283_200)  // 2024-01-03 12:00 UTC
    let previousDay = Date(timeIntervalSince1970: 1_704_196_800)  // 2024-01-02 12:00 UTC
    try await seed(owner.pool, at: previousDay)
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let authority = DailyRecapLocalAuthority(databasePool: owner.pool)

    let today = try await authority.recap(
      daysAgo: 0, now: now, calendar: calendar, authorizationSnapshot: snapshot)
    XCTAssertTrue(today.contains("# Today Recap"))
    XCTAssertTrue(today.contains("No conversations recorded."))
    for section in ["## Apps", "## Conversations", "## Tasks", "## Focus", "## Memories Learned", "## Screen Context"] {
      XCTAssertTrue(today.contains(section), "missing empty-state \(section)")
    }
    XCTAssertTrue(today.contains("No focus sessions recorded."))
    XCTAssertTrue(today.contains("No memories learned."))
    XCTAssertTrue(today.contains("No screen context recorded."))

    let yesterday = try await authority.recap(
      daysAgo: 1, now: now, calendar: calendar, authorizationSnapshot: snapshot)
    for section in ["## Apps", "## Conversations", "## Tasks", "## Focus", "## Memories Learned", "## Screen Context"] {
      XCTAssertTrue(yesterday.contains(section), "missing \(section)")
    }
    XCTAssertTrue(yesterday.contains("## Conversations (3)"))
    XCTAssertTrue(yesterday.contains("Conversation 0"))
    XCTAssertTrue(yesterday.contains("Conversation 2"))
    XCTAssertTrue(yesterday.contains("## Tasks (3)"))
    XCTAssertTrue(yesterday.contains("Task 0"))
    XCTAssertTrue(yesterday.contains("Task 2"))
    XCTAssertTrue(yesterday.contains("...and 5 more apps"))
    XCTAssertTrue(yesterday.contains("...and 2 more sessions"))
    XCTAssertTrue(yesterday.contains("...and 2 more\n"))
    XCTAssertTrue(yesterday.contains("Observation 19"))
    XCTAssertFalse(yesterday.contains("Observation 20"))
    XCTAssertTrue(yesterday.contains("...and 2 more observations"))

    for daysAgo in [30, 365] {
      let arbitrary = try await authority.recap(
        daysAgo: daysAgo, now: now, calendar: calendar, authorizationSnapshot: snapshot)
      XCTAssertTrue(arbitrary.contains("# Past \(daysAgo) days Recap"))
      XCTAssertTrue(arbitrary.contains("## Conversations (3)"), "days_ago must not be capped")
    }
  }

  func testRecapRejectsSameOwnerAfterAuthorizationGenerationChanges() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let fixture = try XCTUnwrap(ownerFixture)
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "daily-recap-owner")

    do {
      _ = try await DailyRecapLocalAuthority(databasePool: owner.pool).recap(
        daysAgo: 0,
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale recap authorization must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
  }

  private func seed(_ pool: DatabasePool, at date: Date) async throws {
    try await pool.write { db in
      for index in 0..<25 {
        try db.execute(
          sql: "INSERT INTO screenshots(timestamp, appName) VALUES (?, ?)",
          arguments: [date, "App \(index)"])
      }
      for index in 0..<3 {
        try db.execute(
          sql: """
            INSERT INTO transcription_sessions
              (title, overview, emoji, startedAt, finishedAt, status)
            VALUES (?, ?, '•', ?, ?, 'completed')
            """,
          arguments: ["Conversation \(index)", "Summary \(index)", date, date.addingTimeInterval(600)])
        try db.execute(
          sql: """
            INSERT INTO action_items(description, completed, deleted, priority, createdAt)
            VALUES (?, 0, 0, 'high', ?)
            """,
          arguments: ["Task \(index)", date])
      }
      for index in 0..<12 {
        try db.execute(
          sql: """
            INSERT INTO focus_sessions(status, appOrSite, description, durationSeconds, createdAt)
            VALUES ('focused', 'Xcode', ?, 60, ?)
            """,
          arguments: ["Focus \(index)", date])
        try db.execute(
          sql: """
            INSERT INTO memories(content, category, source, pendingDeleteDeadline, isDismissed, createdAt)
            VALUES (?, 'system', 'conversation', NULL, 0, ?)
            """,
          arguments: ["Memory \(index)", date])
      }
      for index in 0..<22 {
        try db.execute(
          sql: """
            INSERT INTO observations(appName, currentActivity, contextSummary, createdAt)
            VALUES ('Safari', ?, 'Context', ?)
            """,
          arguments: ["Observation \(index)", date.addingTimeInterval(TimeInterval(22 - index))])
      }
    }
  }

  private func makeOwner() throws -> DailyRecapStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DailyRecapLocalAuthorityTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    try pool.write { db in
      try db.execute(sql: "CREATE TABLE screenshots(id INTEGER PRIMARY KEY, timestamp DATETIME, appName TEXT)")
      try db.execute(
        sql: """
          CREATE TABLE transcription_sessions(
            id INTEGER PRIMARY KEY, title TEXT, overview TEXT, emoji TEXT,
            startedAt DATETIME, finishedAt DATETIME, status TEXT)
          """)
      try db.execute(
        sql: """
          CREATE TABLE action_items(
            id INTEGER PRIMARY KEY, description TEXT, completed BOOLEAN, deleted BOOLEAN,
            priority TEXT, createdAt DATETIME)
          """)
      try db.execute(
        sql: """
          CREATE TABLE focus_sessions(
            id INTEGER PRIMARY KEY, status TEXT, appOrSite TEXT, description TEXT,
            durationSeconds INTEGER, createdAt DATETIME)
          """)
      try db.execute(
        sql: """
          CREATE TABLE memories(
            id INTEGER PRIMARY KEY, content TEXT, category TEXT, source TEXT,
            pendingDeleteDeadline DATETIME, isDismissed BOOLEAN, createdAt DATETIME)
          """)
      try db.execute(
        sql: """
          CREATE TABLE observations(
            id INTEGER PRIMARY KEY, appName TEXT, currentActivity TEXT,
            contextSummary TEXT, createdAt DATETIME)
          """)
    }
    return DailyRecapStorageOwner(directory: directory, pool: pool)
  }
}

private struct DailyRecapStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
