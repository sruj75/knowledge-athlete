import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationArchiveReaderTests: XCTestCase {
  func testArchivePagesAreStableOwnerScopedAndContainNoServerAuthorityFields() async throws {
    let ownerA = try makeOwnerDatabase()
    let ownerB = try makeOwnerDatabase()
    defer {
      try? ownerA.pool.close()
      try? ownerB.pool.close()
      try? FileManager.default.removeItem(at: ownerA.directory)
      try? FileManager.default.removeItem(at: ownerB.directory)
    }

    let ids = [
      "10000000-0000-4000-8000-000000000001",
      "10000000-0000-4000-8000-000000000002",
      "10000000-0000-4000-8000-000000000003",
    ]
    for (index, id) in ids.enumerated() {
      try await seedConversation(
        in: ownerA.pool,
        id: id,
        createdAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)),
        text: "owner-a-\(index)"
      )
    }
    try await seedConversation(
      in: ownerB.pool,
      id: "20000000-0000-4000-8000-000000000001",
      createdAt: Date(timeIntervalSince1970: 1_700_000_100),
      text: "owner-b"
    )

    let readerA: any ConversationArchiveReader = TranscriptionStorage(databasePool: ownerA.pool)
    let firstPage = try await readerA.conversationArchivePage(after: nil, limit: 2)
    XCTAssertEqual(firstPage.map(\.conversationId), [ids[2], ids[1]])
    XCTAssertEqual(firstPage.flatMap(\.segments).map(\.text), ["owner-a-2", "owner-a-1"])

    let secondPage = try await readerA.conversationArchivePage(after: firstPage.last?.conversationId, limit: 2)
    XCTAssertEqual(secondPage.map(\.conversationId), [ids[0]])

    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(firstPage)) as? [[String: Any]]
    XCTAssertNil(encoded?.first?["backendId"])
    XCTAssertNil(encoded?.first?["backendSynced"])
    XCTAssertNil(encoded?.first?["serverUpdatedAt"])
    XCTAssertNil(encoded?.first?["cacheCompleteness"])

    let readerB: any ConversationArchiveReader = TranscriptionStorage(databasePool: ownerB.pool)
    let ownerBPage = try await readerB.conversationArchivePage(after: nil, limit: 10)
    XCTAssertEqual(ownerBPage.map(\.conversationId), ["20000000-0000-4000-8000-000000000001"])
    XCTAssertFalse(ownerBPage.flatMap(\.segments).contains(where: { $0.text.hasPrefix("owner-a") }))
  }

  private func makeOwnerDatabase() throws -> (directory: URL, pool: DatabasePool) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationArchiveReaderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return (directory, pool)
  }

  private func seedConversation(in pool: DatabasePool, id: String, createdAt: Date, text: String) async throws {
    try await pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO transcription_sessions
            (conversationId, startedAt, finishedAt, language, timezone, status, starred, createdAt, updatedAt,
             contentGeneration, isTitleManuallyEdited)
          VALUES (?, ?, ?, 'en', 'UTC', 'completed', 0, ?, ?, 0, 0)
          """,
        arguments: [id, createdAt, createdAt.addingTimeInterval(30), createdAt, createdAt])
      let sessionId = db.lastInsertedRowID
      try db.execute(
        sql: """
          INSERT INTO transcription_segments
            (sessionId, segmentId, speakerId, text, startTime, endTime, segmentOrder, isUser, createdAt, updatedAt)
          VALUES (?, ?, 0, ?, 0, 1, 0, 1, ?, ?)
          """,
        arguments: [sessionId, UUID().uuidString, text, createdAt, createdAt])
    }
  }
}
