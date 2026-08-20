import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationLocalQueryTests: XCTestCase {
  func testNewestFirstPagingUsesFiftyRowsWithoutDuplicatesAndCountsTheSameScope() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    for index in 0..<55 {
      try await seed(
        owner.storage,
        startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
        title: "Conversation \(index)")
    }

    let first = try await owner.storage.conversationPage(query: .all, offset: 0, limit: 50)
    let second = try await owner.storage.conversationPage(query: .all, offset: 50, limit: 50)
    let count = try await owner.storage.conversationCount(query: .all)

    XCTAssertEqual(first.count, 50)
    XCTAssertEqual(second.count, 5)
    XCTAssertEqual(Set((first + second).map(\.conversationId)).count, 55)
    XCTAssertEqual(first.first?.title, "Conversation 54")
    XCTAssertEqual(second.last?.title, "Conversation 0")
    XCTAssertEqual(count, 55)
  }

  func testCombinedStarFolderAndHalfOpenDateFiltersShareListAndCountSemantics() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let day = Date(timeIntervalSince1970: 1_700_006_400)
    let matching = try await seed(owner.storage, startedAt: day.addingTimeInterval(10), title: "Match")
    _ = try await seed(owner.storage, startedAt: day.addingTimeInterval(20), title: "Wrong star")
    _ = try await seed(owner.storage, startedAt: day.addingTimeInterval(86_400), title: "Next day")
    try await owner.pool.write { database in
      try database.execute(
        sql: "INSERT INTO conversation_folders (id, name, color, createdAt) VALUES ('folder-a', 'Folder', '#fff', ?)",
        arguments: [day])
      try database.execute(
        sql: "UPDATE transcription_sessions SET starred = 1, folderId = 'folder-a' WHERE conversationId = ?",
        arguments: [matching.conversationId])
      try database.execute(
        sql: "UPDATE transcription_sessions SET folderId = 'folder-a' WHERE title = 'Wrong star'")
      try database.execute(
        sql: "UPDATE transcription_sessions SET starred = 1, folderId = 'folder-a' WHERE title = 'Next day'")
    }
    let query = ConversationLocalQuery(
      starredOnly: true,
      startDate: day,
      endDate: day.addingTimeInterval(86_400),
      folderId: "folder-a")

    let rows = try await owner.storage.conversationPage(query: query, offset: 0, limit: 50)
    let count = try await owner.storage.conversationCount(query: query)

    XCTAssertEqual(rows.map(\.conversationId), [matching.conversationId])
    XCTAssertEqual(count, 1)
  }

  func testCompletedStatusFilterIsAppliedBeforeThePageLimit() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let completed = try await seed(
      owner.storage,
      startedAt: Date(timeIntervalSince1970: 1),
      title: "Completed")
    let newerFinalizing = try await seed(
      owner.storage,
      startedAt: Date(timeIntervalSince1970: 2),
      title: "Still finalizing")
    try await owner.pool.write { database in
      try database.execute(
        sql: "UPDATE transcription_sessions SET status = 'finalizing' WHERE conversationId = ?",
        arguments: [newerFinalizing.conversationId])
    }
    let query = ConversationLocalQuery(
      starredOnly: false,
      startDate: nil,
      endDate: nil,
      folderId: nil,
      statuses: [.completed])

    let rows = try await owner.storage.conversationPage(query: query, offset: 0, limit: 1)

    XCTAssertEqual(rows.map(\.conversationId), [completed.conversationId])
  }

  func testSearchNormalizesWhitespaceMatchesTitleAndOverviewOnlyAndCapsAtFifty() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    for index in 0..<52 {
      _ = try await seed(owner.storage, startedAt: Date(timeIntervalSince1970: TimeInterval(index)), title: "Road Map")
    }
    let transcriptOnly = try await seed(
      owner.storage,
      startedAt: Date(timeIntervalSince1970: 100),
      title: "Other",
      transcript: "road map")

    let results = try await owner.storage.searchConversations(text: "  road   MAP \n ")

    XCTAssertEqual(results.count, 50)
    XCTAssertFalse(results.contains { $0.conversationId == transcriptOnly.conversationId })
  }

  @discardableResult
  private func seed(
    _ storage: TranscriptionStorage,
    startedAt: Date,
    title: String,
    transcript: String? = nil
  ) async throws -> ConversationCaptureHandle {
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: startedAt)
    if let transcript {
      try await storage.upsertSegments(
        conversationId: handle.conversationId,
        segments: [
          ConversationSegmentInput(
            segmentId: nil, speakerId: 0, text: transcript, startTime: 0, endTime: 1,
            isUser: true, translations: [])
        ])
    }
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: startedAt.addingTimeInterval(5))
    let pool = try await storage.ensureInitializedForLocalAuthority()
    try await pool.write { database in
      try database.execute(
        sql: "UPDATE transcription_sessions SET title = ?, status = 'completed' WHERE conversationId = ?",
        arguments: [title, handle.conversationId])
    }
    return handle
  }

  private func makeOwner() throws -> LocalQueryStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationLocalQueryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return LocalQueryStorageOwner(
      directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct LocalQueryStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
