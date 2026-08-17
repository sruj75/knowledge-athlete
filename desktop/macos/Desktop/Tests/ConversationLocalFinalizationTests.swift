import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationLocalFinalizationTests: XCTestCase {
  func testFinalizationProjectionRefreshesBeforeAndAfterPostProcessing() async throws {
    let recorder = FinalizationProjectionRecorder()

    try await ConversationFinalizationProjectionFlow.run(
      finish: {
        await recorder.append("finish")
        return "conversation-id"
      },
      refresh: { await recorder.append("refresh") },
      postProcess: { id in await recorder.append("post:\(id)") })

    let values = await recorder.values()
    XCTAssertEqual(
      values,
      ["finish", "refresh", "post:conversation-id", "refresh"])
  }

  func testPostProcessProjectionRefreshesMergedRowBeforeAndAfterEnrichment() async {
    let recorder = FinalizationProjectionRecorder()

    await ConversationPostProcessProjectionFlow.run(
      conversationId: "merged-id",
      refresh: { await recorder.append("refresh") },
      postProcess: { id in await recorder.append("post:\(id)") })

    let values = await recorder.values()
    XCTAssertEqual(
      values,
      ["refresh", "post:merged-id", "refresh"])
  }

  func testEveryRetainedReasonClosesExactlyOnceAndIsImmediatelyRestartVisible() async throws {
    for reason in TranscriptionFinalizationReason.allCases {
      let owner = try makeStorage()
      defer {
        try? owner.pool.close()
        try? FileManager.default.removeItem(at: owner.directory)
      }
      let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
      let handle = try await owner.storage.beginConversation(configuration: .testDefault, startedAt: startedAt)
      try await owner.storage.upsertSegments(
        conversationId: handle.conversationId,
        segments: [
          ConversationSegmentInput(
            segmentId: UUID().uuidString, speakerId: 0, text: "remember this", startTime: 0, endTime: 1,
            isUser: true, translations: [])
        ])

      let first = try await owner.storage.finishConversation(
        sessionId: handle.sessionId, reason: reason, finishedAt: startedAt.addingTimeInterval(10))
      let second = try await owner.storage.finishConversation(
        sessionId: handle.sessionId, reason: .retry, finishedAt: startedAt.addingTimeInterval(20))

      XCTAssertEqual(first.status, .finalizing)
      XCTAssertEqual(first.finalizationReason, reason)
      XCTAssertEqual(first.finishedAt, startedAt.addingTimeInterval(10))
      XCTAssertEqual(second.contentGeneration, first.contentGeneration)
      XCTAssertEqual(second.finalizationReason, reason)

      let restarted = TranscriptionStorage(databasePool: owner.pool)
      let afterRestart = try await restarted.conversationDetail(id: handle.conversationId)
      XCTAssertEqual(afterRestart?.status, .finalizing)
      XCTAssertEqual(afterRestart?.segments.map(\.text), ["remember this"])

      let work = try await restarted.enrichmentWork(conversationId: handle.conversationId)
      XCTAssertEqual(work.map(\.kind), [.discard])
      XCTAssertEqual(work.map(\.state), [.pending])
    }
  }

  func testRecoveryClosesOldNonemptyCaptureAndDeletesOldEmptyCapture() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    let nonempty = try await owner.storage.beginConversation(configuration: .testDefault, startedAt: old)
    let empty = try await owner.storage.beginConversation(configuration: .testDefault, startedAt: old)
    try await owner.storage.upsertSegments(
      conversationId: nonempty.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: nil, speakerId: 0, text: "survives", startTime: 0, endTime: 1, isUser: true,
          translations: [])
      ])

    let report = try await owner.storage.recoverLocalFinalization(
      now: old.addingTimeInterval(60), minimumRecordingAge: 30)

    XCTAssertEqual(report.finalizedConversationIds, [nonempty.conversationId])
    XCTAssertEqual(report.deletedEmptyConversationIds, [empty.conversationId])
    let recovered = try await owner.storage.conversationDetail(id: nonempty.conversationId)
    let removed = try await owner.storage.conversationDetail(id: empty.conversationId)
    XCTAssertEqual(recovered?.status, .finalizing)
    XCTAssertNil(removed)
  }

  func testRecoveryFailKeepsStaleRunningDiscardAndAdmitsDownstreamWork() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let handle = try await finishedConversation(owner.storage)
    let claimedDiscard = try await owner.storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    _ = try XCTUnwrap(claimedDiscard)
    let now = Date()
    try await ageRunningWork(owner.pool, conversationId: handle.conversationId, now: now)

    _ = try await owner.storage.recoverAndListPendingEnrichmentWork(
      minimumRunningAge: 300, now: now)

    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)
    XCTAssertEqual(detail?.status, .processing)
    XCTAssertEqual(work.map(\.kind), [.discard, .structure, .actionItems])
    XCTAssertEqual(work.map(\.state), [.failed, .pending, .pending])
  }

  func testRecoveryDoesNotStealActiveWorkAndOldAttemptCannotCommitAfterReclaim() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let handle = try await finishedConversation(owner.storage)
    let claimedDiscard = try await owner.storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    let discard = try XCTUnwrap(claimedDiscard)
    _ = try await owner.storage.resolveDiscardWork(
      conversationId: handle.conversationId,
      contentGeneration: discard.contentGeneration,
      attemptCount: discard.attemptCount,
      discard: false,
      authorization: .unrestricted)
    let claimedFirst = try await owner.storage.claimEnrichmentWork(
      conversationId: handle.conversationId, kind: .structure, authorization: .unrestricted)
    let first = try XCTUnwrap(claimedFirst)
    let now = Date()

    _ = try await owner.storage.recoverAndListPendingEnrichmentWork(
      minimumRunningAge: 300, now: now)
    let activeWork = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)
    XCTAssertEqual(activeWork.first { $0.kind == .structure }?.state, .running)

    try await ageRunningWork(owner.pool, conversationId: handle.conversationId, now: now)
    _ = try await owner.storage.recoverAndListPendingEnrichmentWork(
      minimumRunningAge: 300, now: now)
    let claimedSecond = try await owner.storage.claimEnrichmentWork(
      conversationId: handle.conversationId, kind: .structure, authorization: .unrestricted)
    let second = try XCTUnwrap(claimedSecond)
    XCTAssertEqual(second.attemptCount, first.attemptCount + 1)

    let response = ConversationStructureComputeResponse(
      generationId: UUID(), title: "Recovered", overview: "Safe", emoji: "✅", commitments: [])
    let stale = try await owner.storage.completeStructureWork(
      conversationId: handle.conversationId,
      contentGeneration: first.contentGeneration,
      attemptCount: first.attemptCount,
      response: response,
      authorization: .unrestricted)
    XCTAssertEqual(stale, .missing)
    let detailAfterStaleAttempt = try await owner.storage.conversationDetail(id: handle.conversationId)
    XCTAssertNil(detailAfterStaleAttempt?.title)

    let applied = try await owner.storage.completeStructureWork(
      conversationId: handle.conversationId,
      contentGeneration: second.contentGeneration,
      attemptCount: second.attemptCount,
      response: response,
      authorization: .unrestricted)
    XCTAssertEqual(applied, .applied)
  }

  func testManualRetryCreatesNewGenerationAndSupersedesOldEnrichmentWork() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let handle = try await finishedConversation(owner.storage)
    let loadedBefore = try await owner.storage.conversationDetail(id: handle.conversationId)
    let before = try XCTUnwrap(loadedBefore)
    let claimedDiscard = try await owner.storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    let discard = try XCTUnwrap(claimedDiscard)
    _ = try await owner.storage.resolveDiscardWork(
      conversationId: handle.conversationId,
      contentGeneration: discard.contentGeneration,
      attemptCount: discard.attemptCount,
      discard: false,
      authorization: .unrestricted)
    try await owner.pool.write { database in
      try database.execute(
        sql: """
          UPDATE conversation_enrichment_work
          SET state = 'failed', attemptCount = 5, lastError = 'compute_failed'
          WHERE conversationId = ? AND kind IN ('structure', 'actionItems')
          """,
        arguments: [handle.conversationId])
    }

    let retried = try await owner.storage.retryConversationEnrichment(
      id: handle.conversationId,
      authorization: .unrestricted)
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(retried.contentGeneration, before.contentGeneration + 1)
    XCTAssertEqual(retried.status, .processing)
    XCTAssertEqual(
      work.filter { $0.contentGeneration == before.contentGeneration && $0.kind != .discard }
        .map(\.state),
      [.superseded, .superseded])
    XCTAssertEqual(
      work.filter { $0.contentGeneration == retried.contentGeneration }.map(\.state),
      [.pending, .pending])
  }

  private func finishedConversation(_ storage: TranscriptionStorage) async throws -> ConversationCaptureHandle {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: startedAt)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: UUID().uuidString, speakerId: 0, text: "recover this", startTime: 0,
          endTime: 1, isUser: true, translations: [])
      ])
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: startedAt.addingTimeInterval(2))
    return handle
  }

  private func ageRunningWork(
    _ pool: DatabasePool,
    conversationId: String,
    now: Date
  ) async throws {
    try await pool.write { database in
      try database.execute(
        sql: "UPDATE conversation_enrichment_work SET updatedAt = ? WHERE conversationId = ? AND state = 'running'",
        arguments: [now.addingTimeInterval(-301), conversationId])
    }
  }

  private func makeStorage() throws -> (directory: URL, pool: DatabasePool, storage: TranscriptionStorage) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationLocalFinalizationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return (directory, pool, TranscriptionStorage(databasePool: pool))
  }
}

private actor FinalizationProjectionRecorder {
  private var recorded: [String] = []

  func append(_ value: String) {
    recorded.append(value)
  }

  func values() -> [String] { recorded }
}
