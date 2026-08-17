import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationDeletionCascadeTests: XCTestCase {
  func testDeletePermanentlyRemovesExactDescendantsAndPreservesUnrelatedRows() async throws {
    let owner = try makeDeletionOwner()
    defer { owner.cleanup() }
    let target = try await seededConversation(owner.storage, text: "target")
    let unrelated = try await seededConversation(owner.storage, text: "unrelated")
    try await seedChildren(owner.pool, target: target, unrelated: unrelated)

    try await owner.storage.deleteConversationCascade(
      id: target.conversationId, authorization: .unrestricted)

    let targetDetail = try await owner.storage.conversationDetail(id: target.conversationId)
    let unrelatedDetail = try await owner.storage.conversationDetail(id: unrelated.conversationId)
    let counts = try await descendantCounts(owner.pool, target: target, unrelated: unrelated)
    let archive = try await owner.storage.conversationArchivePage(after: nil, limit: 20)
    XCTAssertNil(targetDetail)
    XCTAssertNotNil(unrelatedDetail)
    XCTAssertEqual(counts.target, [0, 0, 0])
    XCTAssertEqual(counts.unrelated, [1, 2, 1])
    XCTAssertFalse(
      archive.contains {
        $0.conversationId == target.conversationId
      })
  }

  func testInjectedFailureRollsBackTheWholeCascade() async throws {
    let owner = try makeDeletionOwner()
    defer { owner.cleanup() }
    let target = try await seededConversation(owner.storage, text: "target")
    let unrelated = try await seededConversation(owner.storage, text: "unrelated")
    try await seedChildren(owner.pool, target: target, unrelated: unrelated)

    do {
      try await owner.storage.deleteConversationCascade(
        id: target.conversationId,
        authorization: .unrestricted,
        failureInjector: { throw DeletionTestError.injected })
      XCTFail("Expected injected failure")
    } catch DeletionTestError.injected {
      // Expected.
    }

    let detail = try await owner.storage.conversationDetail(id: target.conversationId)
    let counts = try await descendantCounts(owner.pool, target: target, unrelated: unrelated)
    XCTAssertNotNil(detail)
    XCTAssertEqual(counts.target, [1, 2, 1])
  }

  private func seededConversation(
    _ storage: TranscriptionStorage, text: String
  ) async throws -> ConversationCaptureHandle {
    let handle = try await storage.beginConversation(configuration: .testDefault)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: nil, speakerId: 0, text: text, startTime: 0, endTime: 1,
          isUser: true, translations: [])
      ])
    return handle
  }

  private func seedChildren(
    _ pool: DatabasePool,
    target: ConversationCaptureHandle,
    unrelated: ConversationCaptureHandle
  ) async throws {
    try await pool.write { database in
      try database.execute(
        sql: "CREATE TABLE action_items (id INTEGER PRIMARY KEY, conversationId TEXT, description TEXT)")
      try database.execute(sql: "CREATE TABLE memories (id INTEGER PRIMARY KEY, conversationId TEXT, content TEXT)")
      for (conversationId, suffix) in [(target.conversationId, "target"), (unrelated.conversationId, "other")] {
        try database.execute(
          sql: "INSERT INTO action_items (conversationId, description) VALUES (?, ?), (?, ?)",
          arguments: [conversationId, "open-\(suffix)", conversationId, "completed-edited-\(suffix)"])
        try database.execute(
          sql: "INSERT INTO memories (conversationId, content) VALUES (?, ?)",
          arguments: [conversationId, "memory-\(suffix)"])
      }
      let targetSession = target.sessionId
      let unrelatedSession = unrelated.sessionId
      for sessionId in [targetSession, unrelatedSession] {
        try database.execute(
          sql: """
            INSERT INTO live_notes
              (sessionId, text, timestamp, isAiGenerated, createdAt, updatedAt)
            VALUES (?, 'note', ?, 1, ?, ?)
            """,
          arguments: [sessionId, Date(), Date(), Date()])
      }
    }
  }

  private func descendantCounts(
    _ pool: DatabasePool,
    target: ConversationCaptureHandle,
    unrelated: ConversationCaptureHandle
  ) async throws -> (target: [Int], unrelated: [Int]) {
    try await pool.read { database in
      func counts(_ item: ConversationCaptureHandle) throws -> [Int] {
        [
          try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM transcription_segments WHERE sessionId = ?",
            arguments: [item.sessionId]) ?? 0,
          try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM action_items WHERE conversationId = ?",
            arguments: [item.conversationId]) ?? 0,
          try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM memories WHERE conversationId = ?", arguments: [item.conversationId])
            ?? 0,
        ]
      }
      return (try counts(target), try counts(unrelated))
    }
  }

  private func makeDeletionOwner() throws -> DeletionStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationDeletionCascadeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return DeletionStorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private enum DeletionTestError: Error { case injected }

private struct DeletionStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
