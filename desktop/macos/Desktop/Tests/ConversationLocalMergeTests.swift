import CryptoKit
import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationLocalMergeTests: XCTestCase {
  func testMergeOrdersSourcesPreservesRealGapAndAtomicallyReplacesThem() async throws {
    let owner = try makeMergeOwner()
    defer { owner.cleanup() }
    let first = try await completed(
      owner.storage, start: Date(timeIntervalSince1970: 100), finish: Date(timeIntervalSince1970: 110),
      text: "first")
    let second = try await completed(
      owner.storage, start: Date(timeIntervalSince1970: 120), finish: Date(timeIntervalSince1970: 125),
      text: "second")

    let merged = try await owner.storage.mergeConversations(
      ids: [second.conversationId, first.conversationId], authorization: .unrestricted)
    let firstAfter = try await owner.storage.conversationDetail(id: first.conversationId)
    let secondAfter = try await owner.storage.conversationDetail(id: second.conversationId)

    XCTAssertNil(firstAfter)
    XCTAssertNil(secondAfter)
    XCTAssertEqual(merged.status, .processing)
    XCTAssertEqual(merged.segments.map(\.text), ["first", "second"])
    XCTAssertEqual(merged.segments.map(\.startTime), [0, 20])
    XCTAssertEqual(Set(merged.segments.map(\.segmentId)).count, 2)
    let provenance = try await owner.pool.read { database in
      try String.fetchAll(
        database,
        sql:
          "SELECT sourceConversationId FROM conversation_merge_sources WHERE replacementConversationId = ? ORDER BY sourceOrdinal",
        arguments: [merged.conversationId])
    }
    let work = try await owner.storage.enrichmentWork(conversationId: merged.conversationId)
    XCTAssertEqual(provenance, [first.conversationId, second.conversationId])
    XCTAssertEqual(work.map(\.kind), [.structure, .actionItems])
  }

  func testInjectedFailureLeavesBothSourcesAndNoReplacement() async throws {
    let owner = try makeMergeOwner()
    defer { owner.cleanup() }
    let first = try await completed(owner.storage, start: Date(), finish: Date().addingTimeInterval(2), text: "a")
    let second = try await completed(
      owner.storage, start: Date().addingTimeInterval(3), finish: Date().addingTimeInterval(5), text: "b")
    let replacementId = UUID().uuidString.lowercased()

    do {
      _ = try await owner.storage.mergeConversations(
        ids: [first.conversationId, second.conversationId],
        replacementId: replacementId,
        authorization: .unrestricted,
        failureInjector: { throw MergeTestError.injected })
      XCTFail("Expected merge interruption")
    } catch MergeTestError.injected {
      // Expected.
    }

    let firstAfter = try await owner.storage.conversationDetail(id: first.conversationId)
    let secondAfter = try await owner.storage.conversationDetail(id: second.conversationId)
    let replacement = try await owner.storage.conversationDetail(id: replacementId)
    XCTAssertNotNil(firstAfter)
    XCTAssertNotNil(secondAfter)
    XCTAssertNil(replacement)
  }

  func testMergeRemapsConversationScopedSpeakerIdsWithoutLabelCollision() async throws {
    let owner = try makeMergeOwner()
    defer { owner.cleanup() }
    let first = try await completed(
      owner.storage, start: Date(timeIntervalSince1970: 100), finish: Date(timeIntervalSince1970: 102),
      text: "Alice speaks", speakerId: 0, speakerName: "Alice")
    let second = try await completed(
      owner.storage, start: Date(timeIntervalSince1970: 103), finish: Date(timeIntervalSince1970: 105),
      text: "Bob speaks", speakerId: 0, speakerName: "Bob")

    let merged = try await owner.storage.mergeConversations(
      ids: [first.conversationId, second.conversationId], authorization: .unrestricted)

    XCTAssertEqual(merged.segments.map(\.speakerId), [0, 1])
    XCTAssertEqual(merged.speakerLabels[0]?.name, "Alice")
    XCTAssertEqual(merged.speakerLabels[1]?.name, "Bob")
  }

  private func completed(
    _ storage: TranscriptionStorage,
    start: Date,
    finish: Date,
    text: String,
    speakerId: Int = 0,
    speakerName: String? = nil
  ) async throws -> ConversationCaptureHandle {
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: start)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: UUID().uuidString, speakerId: speakerId, text: text, startTime: 0,
          endTime: finish.timeIntervalSince(start), isUser: speakerName == nil, translations: [])
      ])
    if let speakerName {
      _ = try await storage.setConversationSpeakerLabel(
        conversationId: handle.conversationId,
        speakerId: speakerId,
        name: speakerName,
        isUser: false,
        applyToExisting: true,
        segmentIds: [],
        authorization: .unrestricted)
    }
    _ = try await storage.finishConversation(sessionId: handle.sessionId, reason: .userStop, finishedAt: finish)
    let pool = try await storage.ensureInitializedForLocalAuthority()
    try await pool.write { database in
      try database.execute(
        sql: "UPDATE transcription_sessions SET status = 'completed' WHERE conversationId = ?",
        arguments: [handle.conversationId])
    }
    return handle
  }

  private func makeMergeOwner() throws -> MergeStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationLocalMergeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return MergeStorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private enum MergeTestError: Error { case injected }

private struct MergeStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
