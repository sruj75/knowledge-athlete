import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationLocalAuthorityMigrationTests: XCTestCase {
  func testFreshSchemaContainsOnlyLocalAuthorityConversationColumns() throws {
    try withDatabaseQueue { queue in
      try migrate(queue)

      try queue.read { db in
        for table in [
          "transcription_sessions",
          "transcription_segments",
          "conversation_segment_ingestion",
          "conversation_folders",
          "conversation_speaker_labels",
          "conversation_merge_sources",
          "conversation_enrichment_work",
        ] {
          XCTAssertTrue(try db.tableExists(table), "missing local-authority table \(table)")
        }

        let sessionColumns = try db.columns(in: "transcription_sessions")
        let sessionNames = Set(sessionColumns.map(\.name))
        XCTAssertTrue(sessionColumns.first(where: { $0.name == "conversationId" })?.isNotNull == true)
        XCTAssertTrue(sessionColumns.first(where: { $0.name == "contentGeneration" })?.isNotNull == true)
        XCTAssertTrue(
          Set([
            "conversationId", "startedAt", "finishedAt", "language", "timezone", "inputDeviceName", "status",
            "lastError", "finalizationReason", "finalizationStartedAt", "finalizationCompletedAt", "title",
            "isTitleManuallyEdited", "overview", "emoji", "commitmentsJson", "geolocationJson", "starred",
            "folderId", "createdAt", "updatedAt", "contentGeneration",
            "autoDetectLanguage", "vocabularyJson", "classifierCategory", "classifierSource",
          ]).isSubset(of: sessionNames)
        )
        XCTAssertFalse(sessionColumns.first(where: { $0.name == "classifierCategory" })?.isNotNull ?? true)
        XCTAssertFalse(sessionColumns.first(where: { $0.name == "classifierSource" })?.isNotNull ?? true)
        XCTAssertTrue(
          Set([
            "source", "backendId", "clientConversationId", "backendSynced", "serverUpdatedAt", "cacheCompleteness",
            "retryCount", "finalizationStrategy", "category", "actionItemsJson", "eventsJson", "discarded",
            "deleted", "isLocked",
          ]).isDisjoint(with: sessionNames)
        )

        let segmentColumns = try db.columns(in: "transcription_segments")
        let segmentNames = Set(segmentColumns.map(\.name))
        XCTAssertTrue(segmentColumns.first(where: { $0.name == "segmentId" })?.isNotNull == true)
        XCTAssertTrue(
          Set([
            "id", "sessionId", "segmentId", "speakerId", "text", "startTime", "endTime", "segmentOrder",
            "isUser", "translationsJson", "createdAt", "updatedAt",
          ]).isSubset(of: segmentNames)
        )
        XCTAssertTrue(Set(["speaker", "speakerLabel", "personId"]).isDisjoint(with: segmentNames))
      }
    }
  }

  func testLegacyMigrationPreservesContentRewritesExactSourcesAndRemovesDiscardedRows() throws {
    let firstConversationId = "11111111-1111-4111-8111-111111111111"
    let duplicateConversationId = firstConversationId
    let firstBackendId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let secondBackendId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let discardedBackendId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    let firstSegmentId = "22222222-2222-4222-8222-222222222222"

    try withDatabaseQueue { queue in
      try queue.write { db in
        try createLegacySchema(db)
        let insertSession = """
          INSERT INTO transcription_sessions
            (id, startedAt, finishedAt, source, language, timezone, inputDeviceName, status, retryCount,
             lastError, backendId, clientConversationId, backendSynced, createdAt, updatedAt, serverUpdatedAt,
             cacheCompleteness, finalizationStrategy, finalizationReason, finalizationStartedAt,
             finalizationCompletedAt, title, overview, emoji, category, actionItemsJson, eventsJson,
             geolocationJson, conversationStatus, discarded, deleted, isLocked, starred, folderId)
          VALUES (?, ?, ?, 'desktop', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                  NULL, ?, ?, ?, ?, ?, NULL)
          """
        try db.execute(
          sql: insertSession,
          arguments: [
            1, date(0), date(60), "en", "America/Los_Angeles", "Mac mic", "completed", 0, nil,
            firstBackendId, firstConversationId, true, date(0), date(61), date(61), "detail", "local_segments",
            "user_stop", date(60), date(60), "First", "Overview", "1", "other", "[]",
            "[{\"title\":\"Follow up\",\"description\":\"Send notes\",\"start\":\"2026-08-18T09:00:00Z\",\"duration\":30,\"created\":true}]",
            "completed", false, false, false, true,
          ])
        try db.execute(
          sql: insertSession,
          arguments: [
            2, date(60), date(120), "fr", "Europe/Paris", nil, "pending_upload", 2, "offline",
            secondBackendId, duplicateConversationId, false, date(60), date(121), nil, "list", "local_segments",
            "crash_recovery", nil, nil, nil, nil, nil, nil, nil, nil, "in_progress", false, false, false, false,
          ])
        try db.execute(
          sql: insertSession,
          arguments: [
            3, date(120), date(180), "en", "UTC", nil, "failed", 4, nil, discardedBackendId, nil, false,
            date(120), date(181), nil, "list", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "failed", true,
            false, false, false,
          ])
        try db.execute(
          sql: insertSession,
          arguments: [
            4, date(240), nil, "en", "UTC", nil, "recording", 0, nil, "not-a-uuid", nil, false, date(240),
            date(241), nil, "list", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "in_progress", false,
            false, false, false,
          ])
        try db.execute(
          sql: insertSession,
          arguments: [
            5, date(300), date(360), "en", "UTC", nil, "failed", 5, nil, nil, nil, false, date(300), date(361),
            nil, "list", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "failed", false, false, false, false,
          ])

        try db.execute(
          sql: """
            INSERT INTO transcription_segments
              (id, sessionId, speaker, text, startTime, endTime, segmentOrder, createdAt, segmentId,
               speakerLabel, isUser, personId, translationsJson)
            VALUES
              (10, 1, 0, 'hello', 0, 1, 0, ?, ?, 'SPEAKER_00', 1, 'person-a', '[{"language":"fr","text":"salut"}]'),
              (11, 2, 1, 'world', 0, 1, 0, ?, ?, 'SPEAKER_01', 0, NULL, NULL),
              (12, 3, 0, 'discard me', 0, 1, 0, ?, NULL, NULL, 0, NULL, NULL),
              (13, 4, 2, 'recording', 0, 1, 0, ?, NULL, NULL, 0, NULL, NULL)
            """,
          arguments: [date(1), firstSegmentId, date(61), firstSegmentId, date(121), date(241)])

        try db.execute(
          sql:
            "INSERT INTO live_notes (id, sessionId, text, timestamp, isAiGenerated, createdAt, updatedAt) VALUES (1, 1, 'keep', ?, 0, ?, ?), (2, 3, 'discard', ?, 0, ?, ?)",
          arguments: [date(30), date(30), date(30), date(150), date(150), date(150)])

        for (table, ids) in [
          ("action_items", [firstBackendId, discardedBackendId, "unrelated"]),
          ("memories", [firstConversationId, discardedBackendId, "unrelated"]),
        ] {
          for (offset, sourceId) in ids.enumerated() {
            try db.execute(
              sql: "INSERT INTO \(table) (id, conversationId, value) VALUES (?, ?, ?)",
              arguments: [offset + 1, sourceId, "\(table)-\(offset)"])
          }
        }
      }

      try migrate(queue)

      try queue.read { db in
        let sessions = try Row.fetchAll(db, sql: "SELECT * FROM transcription_sessions ORDER BY id")
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions[0]["conversationId"], firstConversationId)
        XCTAssertEqual(sessions[0]["status"], "completed")
        let commitmentsData = try XCTUnwrap(
          (sessions[0]["commitmentsJson"] as String?).flatMap { $0.data(using: .utf8) })
        let commitments = try JSONDecoder().decode(
          [ConversationCommitmentComputeCandidate].self, from: commitmentsData)
        let commitmentStart = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-18T09:00:00Z"))
        XCTAssertEqual(
          commitments,
          [
            ConversationCommitmentComputeCandidate(
              title: "Follow up",
              description: "Send notes",
              start: commitmentStart,
              durationMinutes: 30,
              created: false)
          ])
        XCTAssertEqual(sessions[0]["starred"], true)

        let migratedDuplicate: String = sessions[1]["conversationId"]
        XCTAssertNotEqual(migratedDuplicate, duplicateConversationId)
        XCTAssertNotNil(UUID(uuidString: migratedDuplicate))
        XCTAssertEqual(sessions[1]["status"], "finalizing")

        let generatedConversationId: String = sessions[2]["conversationId"]
        XCTAssertNotNil(UUID(uuidString: generatedConversationId))
        XCTAssertEqual(sessions[2]["status"], "recording")

        let segments = try Row.fetchAll(db, sql: "SELECT * FROM transcription_segments ORDER BY id")
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0]["segmentId"], firstSegmentId)
        let duplicateReplacement: String = segments[1]["segmentId"]
        XCTAssertNotEqual(duplicateReplacement, firstSegmentId)
        XCTAssertNotNil(UUID(uuidString: duplicateReplacement))
        let missingReplacement: String = segments[2]["segmentId"]
        XCTAssertNotNil(UUID(uuidString: missingReplacement))
        XCTAssertEqual(segments[0]["speakerId"], 0)
        XCTAssertEqual(segments[0]["translationsJson"], "[{\"language\":\"fr\",\"text\":\"salut\"}]")

        XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_notes"), 1)
        XCTAssertEqual(
          try String.fetchOne(db, sql: "SELECT conversationId FROM action_items WHERE id = 1"), firstConversationId)
        XCTAssertNil(
          try Row.fetchOne(
            db, sql: "SELECT * FROM action_items WHERE conversationId = ?", arguments: [discardedBackendId]))
        XCTAssertEqual(
          try String.fetchOne(db, sql: "SELECT conversationId FROM memories WHERE id = 1"), firstConversationId)
        XCTAssertNil(
          try Row.fetchOne(db, sql: "SELECT * FROM memories WHERE conversationId = ?", arguments: [discardedBackendId]))
        XCTAssertEqual(
          try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM action_items WHERE conversationId = 'unrelated'"), 1)
        XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memories WHERE conversationId = 'unrelated'"), 1)
      }
    }
  }

  private func migrate(_ queue: DatabaseQueue) throws {
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(queue)
  }

  private func withDatabaseQueue(_ operation: (DatabaseQueue) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationLocalAuthorityMigrationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try operation(DatabaseQueue(path: directory.appendingPathComponent("omi.db").path))
  }

  private func createLegacySchema(_ db: Database) throws {
    try db.execute(
      sql: """
        CREATE TABLE transcription_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT, startedAt DATETIME NOT NULL, finishedAt DATETIME, source TEXT NOT NULL,
          language TEXT NOT NULL, timezone TEXT NOT NULL, inputDeviceName TEXT, status TEXT NOT NULL,
          retryCount INTEGER NOT NULL, lastError TEXT, backendId TEXT, clientConversationId TEXT, backendSynced BOOLEAN NOT NULL,
          createdAt DATETIME NOT NULL, updatedAt DATETIME NOT NULL, serverUpdatedAt DATETIME, cacheCompleteness TEXT NOT NULL,
          finalizationStrategy TEXT, finalizationReason TEXT, finalizationStartedAt DATETIME, finalizationCompletedAt DATETIME,
          title TEXT, overview TEXT, emoji TEXT, category TEXT, actionItemsJson TEXT, eventsJson TEXT, geolocationJson TEXT,
          conversationStatus TEXT, discarded BOOLEAN, deleted BOOLEAN, isLocked BOOLEAN, starred BOOLEAN, folderId TEXT
        );
        CREATE TABLE transcription_segments (
          id INTEGER PRIMARY KEY AUTOINCREMENT, sessionId INTEGER NOT NULL REFERENCES transcription_sessions(id) ON DELETE CASCADE,
          speaker INTEGER NOT NULL, text TEXT NOT NULL, startTime DOUBLE NOT NULL, endTime DOUBLE NOT NULL,
          segmentOrder INTEGER NOT NULL, createdAt DATETIME NOT NULL, segmentId TEXT, speakerLabel TEXT, isUser BOOLEAN,
          personId TEXT, translationsJson TEXT
        );
        CREATE TABLE live_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT, sessionId INTEGER NOT NULL REFERENCES transcription_sessions(id) ON DELETE CASCADE,
          text TEXT NOT NULL, timestamp DATETIME NOT NULL, isAiGenerated BOOLEAN NOT NULL, segmentStartOrder INTEGER,
          segmentEndOrder INTEGER, createdAt DATETIME NOT NULL, updatedAt DATETIME NOT NULL
        );
        CREATE TABLE action_items (id INTEGER PRIMARY KEY, conversationId TEXT, value TEXT NOT NULL);
        CREATE TABLE memories (id INTEGER PRIMARY KEY, conversationId TEXT, value TEXT NOT NULL);
        """)
  }

  private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + seconds)
  }
}
