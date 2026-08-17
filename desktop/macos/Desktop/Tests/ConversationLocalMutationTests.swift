import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationLocalMutationTests: XCTestCase {
  func testLatestStarAndManualTitleCommitAreDurableAcrossRestart() async throws {
    let owner = try makeMutationOwner()
    defer { owner.cleanup() }
    let handle = try await finished(owner.storage)

    _ = try await owner.storage.setConversationStarred(
      id: handle.conversationId, starred: true, authorization: .unrestricted)
    _ = try await owner.storage.setConversationStarred(
      id: handle.conversationId, starred: false, authorization: .unrestricted)
    _ = try await owner.storage.setConversationTitle(
      id: handle.conversationId, title: "  My Durable Title  ", authorization: .unrestricted)

    let restarted = TranscriptionStorage(databasePool: owner.pool)
    let detail = try await restarted.conversationDetail(id: handle.conversationId)
    XCTAssertEqual(detail?.starred, false)
    XCTAssertEqual(detail?.title, "My Durable Title")
    XCTAssertEqual(detail?.isTitleManuallyEdited, true)
    XCTAssertEqual(detail?.status, .processing)
    let work = try await restarted.enrichmentWork(conversationId: handle.conversationId)
    XCTAssertEqual(
      work.filter { $0.contentGeneration == detail?.contentGeneration }.map(\.kind),
      [.structure, .actionItems])
    XCTAssertEqual(
      work.filter { $0.contentGeneration == detail?.contentGeneration }.map(\.state),
      [.pending, .pending])
  }

  func testRevokedTransactionRollsBackWithoutPublishingRequestedValue() async throws {
    let owner = try makeMutationOwner()
    defer { owner.cleanup() }
    let handle = try await finished(owner.storage)
    let revoked = LocalMutationAuthorization { false }

    do {
      _ = try await owner.storage.setConversationStarred(
        id: handle.conversationId, starred: true, authorization: revoked)
      XCTFail("Expected the owner fence to reject the transaction")
    } catch LocalMutationAuthorizationError.revoked {
      // Expected.
    }

    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    XCTAssertEqual(detail?.starred, false)
  }

  func testManualTitleWinsOverStaleAndCurrentGeneratedStructure() async throws {
    let owner = try makeMutationOwner()
    defer { owner.cleanup() }
    let handle = try await finished(owner.storage)
    let loadedBefore = try await owner.storage.conversationDetail(id: handle.conversationId)
    let before = try XCTUnwrap(loadedBefore)
    _ = try await owner.storage.setConversationTitle(
      id: handle.conversationId, title: "User Title", authorization: .unrestricted)

    let stale = try await owner.storage.applyConversationStructureCandidate(
      id: handle.conversationId,
      contentGeneration: before.contentGeneration,
      title: "Stale Generated",
      overview: "Overview",
      emoji: "💡",
      commitmentsJson: nil,
      authorization: .unrestricted)
    let loadedCurrent = try await owner.storage.conversationDetail(id: handle.conversationId)
    let current = try XCTUnwrap(loadedCurrent)
    let applied = try await owner.storage.applyConversationStructureCandidate(
      id: handle.conversationId,
      contentGeneration: current.contentGeneration,
      title: "Current Generated",
      overview: "Current overview",
      emoji: "✅",
      commitmentsJson: nil,
      authorization: .unrestricted)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)

    XCTAssertEqual(stale, .stale)
    XCTAssertEqual(applied, .applied)
    XCTAssertEqual(detail?.title, "User Title")
    XCTAssertEqual(detail?.overview, "Current overview")
    XCTAssertEqual(detail?.emoji, "✅")
  }

  private func finished(_ storage: TranscriptionStorage) async throws -> ConversationCaptureHandle {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: start)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: nil, speakerId: 0, text: "content", startTime: 0, endTime: 1,
          isUser: true, translations: [])
      ])
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: start.addingTimeInterval(2))
    let claimedDiscard = try await storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    let discard = try XCTUnwrap(claimedDiscard)
    _ = try await storage.resolveDiscardWork(
      conversationId: handle.conversationId,
      contentGeneration: discard.contentGeneration,
      attemptCount: discard.attemptCount,
      discard: false,
      authorization: .unrestricted)
    return handle
  }

  private func makeMutationOwner() throws -> MutationStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationLocalMutationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return MutationStorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct MutationStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
