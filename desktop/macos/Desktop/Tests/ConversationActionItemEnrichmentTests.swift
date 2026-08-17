import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

private struct ActionSimilarityStub: ConversationTaskSimilarityProviding {
  let matches: [ConversationTaskSimilarityMatch]
  let fails: Bool

  func similarActionItems(for transcript: String) async throws -> [ConversationTaskSimilarityMatch] {
    if fails { throw APIError.invalidResponse }
    return matches
  }
}

private actor ActionComputerStub: ConversationActionItemsComputing {
  let candidates: [ConversationActionComputeCandidate]
  private(set) var requests: [ConversationActionItemsComputeRequest] = []

  init(candidates: [ConversationActionComputeCandidate]) {
    self.candidates = candidates
  }

  func computeActionItems(
    _ request: ConversationActionItemsComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationActionItemsComputeResponse {
    requests.append(request)
    return ConversationActionItemsComputeResponse(
      generationId: request.generationId, candidates: candidates)
  }

  func lastRequest() -> ConversationActionItemsComputeRequest? { requests.last }
}

final class ConversationActionItemEnrichmentTests: XCTestCase {
  func testRelatedContextKeepsOnlyOpenRecentUnrelatedActionItemsAboveThreshold() async throws {
    let owner = try makeActionOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let now = Date(timeIntervalSince1970: 1_700_001_000)
    let eligible = try await insertTask(owner.pool, "eligible", now: now)
    let sameSource = try await insertTask(owner.pool, "same", conversationId: handle.conversationId, now: now)
    let completed = try await insertTask(owner.pool, "done", completed: true, now: now)
    let old = try await insertTask(owner.pool, "old", now: now.addingTimeInterval(-8 * 86_400))
    let belowThreshold = try await insertTask(owner.pool, "weak", now: now)

    let related = try await owner.storage.relatedOpenActionItems(
      conversationId: handle.conversationId,
      matches: [
        .init(localRowId: eligible, similarity: 0.91),
        .init(localRowId: sameSource, similarity: 0.9),
        .init(localRowId: completed, similarity: 0.9),
        .init(localRowId: old, similarity: 0.9),
        .init(localRowId: belowThreshold, similarity: 0.59),
      ],
      now: now)

    XCTAssertEqual(related.map(\.localRowId), [eligible])
  }

  func testRelatedContextFiltersExcludedLeadingMatchesBeforeCappingAtTen() async throws {
    let owner = try makeActionOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let now = Date(timeIntervalSince1970: 1_700_001_000)
    var matches: [ConversationTaskSimilarityMatch] = []
    for index in 0..<10 {
      let excluded = try await insertTask(owner.pool, "excluded-\(index)", completed: true, now: now)
      matches.append(.init(localRowId: excluded, similarity: 0.99 - Float(index) * 0.01))
    }
    let eligible = try await insertTask(owner.pool, "eligible-eleventh", now: now)
    matches.append(.init(localRowId: eligible, similarity: 0.8))

    let related = try await owner.storage.relatedOpenActionItems(
      conversationId: handle.conversationId, matches: matches, now: now)

    XCTAssertEqual(related.map(\.localRowId), [eligible])
  }

  func testSeparateActionRequestUsesOpaqueTokenAndCommitsExactLocalSourceAtomically() async throws {
    let owner = try makeActionOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let now = Date(timeIntervalSince1970: 1_700_001_000)
    let existing = try await insertTask(owner.pool, "original", now: now)
    let requestGeneration = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    let computer = ActionComputerStub(candidates: [
      .init(action: .update, description: "updated", targetTaskToken: "t0", dueAt: now.addingTimeInterval(600)),
      .init(action: .create, description: "recent past task", targetTaskToken: nil, dueAt: now.addingTimeInterval(-10)),
      .init(
        action: .create, description: "stale past task", targetTaskToken: nil, dueAt: now.addingTimeInterval(-86_401)),
    ])
    let service = ConversationActionItemEnrichment(
      storage: owner.storage,
      computer: computer,
      similarityProvider: ActionSimilarityStub(
        matches: [.init(localRowId: existing, similarity: 0.9)], fails: false),
      requiresOwnerAuthorization: false,
      requestGeneration: { requestGeneration },
      now: { now })

    let result = await service.process(conversationId: handle.conversationId)
    let request = await computer.lastRequest()
    let rows = try await owner.pool.read { database in
      try Row.fetchAll(database, sql: "SELECT * FROM action_items ORDER BY id")
    }
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(result, .applied)
    XCTAssertEqual(request?.relatedTasks.map(\.token), ["t0"])
    XCTAssertEqual(request?.relatedTasks.map(\.description), ["original"])
    XCTAssertEqual(rows.count, 3)
    XCTAssertEqual(rows[0]["description"] as String, "updated")
    XCTAssertEqual(rows[1]["description"] as String, "recent past task")
    XCTAssertEqual(rows[1]["conversationId"] as String?, handle.conversationId)
    XCTAssertEqual(rows[1]["dueAt"] as Date?, now.addingTimeInterval(-10))
    XCTAssertEqual(rows[2]["description"] as String, "stale past task")
    XCTAssertNil(rows[2]["dueAt"] as Date?)
    XCTAssertEqual(work.first { $0.kind == .actionItems }?.state, .succeeded)
    XCTAssertEqual(work.first { $0.kind == .structure }?.state, .pending)
  }

  func testEmbeddingFailureSendsEmptyContextAndStillCreatesCandidate() async throws {
    let owner = try makeActionOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let now = Date(timeIntervalSince1970: 1_700_001_000)
    let computer = ActionComputerStub(candidates: [
      .init(action: .create, description: "offline context task", targetTaskToken: nil, dueAt: nil)
    ])
    let service = ConversationActionItemEnrichment(
      storage: owner.storage,
      computer: computer,
      similarityProvider: ActionSimilarityStub(matches: [], fails: true),
      requiresOwnerAuthorization: false,
      now: { now })

    let result = await service.process(conversationId: handle.conversationId)
    let request = await computer.lastRequest()
    XCTAssertEqual(result, .applied)
    XCTAssertEqual(request?.relatedTasks, [])
  }

  func testCandidateBatchRollsBackOnInjectedFailure() async throws {
    let owner = try makeActionOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let loaded = try await owner.storage.conversationDetail(id: handle.conversationId)
    let detail = try XCTUnwrap(loaded)
    let claimedAction = try await owner.storage.claimEnrichmentWork(
      conversationId: handle.conversationId, kind: .actionItems, authorization: .unrestricted)
    let actionClaim = try XCTUnwrap(claimedAction)
    let response = ConversationActionItemsComputeResponse(
      generationId: UUID(),
      candidates: [
        .init(action: .create, description: "one", targetTaskToken: nil, dueAt: nil),
        .init(action: .create, description: "two", targetTaskToken: nil, dueAt: nil),
      ])

    do {
      _ = try await owner.storage.completeActionItemsWork(
        conversationId: handle.conversationId,
        contentGeneration: detail.contentGeneration,
        attemptCount: actionClaim.attemptCount,
        response: response,
        tokenMap: [],
        authorization: .unrestricted,
        failAfterOperations: 1)
      XCTFail("expected injected failure")
    } catch {}
    let count = try await owner.pool.read { database in
      try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM action_items") ?? -1
    }
    XCTAssertEqual(count, 0)
  }

  private func processing(_ storage: TranscriptionStorage) async throws -> ConversationCaptureHandle {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: start)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        .init(
          segmentId: nil, speakerId: 0, text: "please follow up", startTime: 0, endTime: 2,
          isUser: true, translations: [])
      ])
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: start.addingTimeInterval(2))
    let loaded = try await storage.conversationDetail(id: handle.conversationId)
    let detail = try XCTUnwrap(loaded)
    let claimedDiscard = try await storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    let discardClaim = try XCTUnwrap(claimedDiscard)
    _ = try await storage.resolveDiscardWork(
      conversationId: handle.conversationId,
      contentGeneration: detail.contentGeneration,
      attemptCount: discardClaim.attemptCount,
      discard: false,
      authorization: .unrestricted)
    return handle
  }

  private func makeActionOwner() throws -> ActionStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationActionItemEnrichmentTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    try pool.write { database in
      try database.create(table: "action_items") { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("backendSynced", .boolean).notNull().defaults(to: false)
        table.column("description", .text).notNull()
        table.column("completed", .boolean).notNull().defaults(to: false)
        table.column("deleted", .boolean).notNull().defaults(to: false)
        table.column("source", .text)
        table.column("conversationId", .text)
        table.column("dueAt", .datetime)
        table.column("completedAt", .datetime)
        table.column("createdAt", .datetime).notNull()
        table.column("updatedAt", .datetime).notNull()
        table.column("fromStaged", .boolean).notNull().defaults(to: false)
      }
    }
    return ActionStorageOwner(
      directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }

  private func insertTask(
    _ pool: DatabasePool,
    _ description: String,
    conversationId: String? = nil,
    completed: Bool = false,
    now: Date
  ) async throws -> Int64 {
    try await pool.write { database in
      try database.execute(
        sql: """
          INSERT INTO action_items
            (description, completed, deleted, source, conversationId, createdAt, updatedAt)
          VALUES (?, ?, 0, 'conversation', ?, ?, ?)
          """,
        arguments: [description, completed, conversationId, now, now])
      return database.lastInsertedRowID
    }
  }
}

private struct ActionStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
