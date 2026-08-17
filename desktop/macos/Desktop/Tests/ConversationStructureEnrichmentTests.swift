import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

private actor StructureComputerStub: ConversationStructureComputing {
  enum Behavior: Sendable {
    case response(ConversationStructureComputeResponse)
    case failure
  }
  private let behavior: Behavior
  init(_ behavior: Behavior) { self.behavior = behavior }

  func computeStructure(
    _ request: ConversationStructureComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationStructureComputeResponse {
    switch behavior {
    case .response(let response): return response
    case .failure: throw APIError.invalidResponse
    }
  }
}

final class ConversationStructureEnrichmentTests: XCTestCase {
  func testStructureCommitsRetainedFieldsLocallyWithoutCalendarSideEffects() async throws {
    let owner = try makeStructureOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let loaded = try await owner.storage.conversationDetail(id: handle.conversationId)
    let generation = try XCTUnwrap(loaded?.contentGeneration)
    let requestGeneration = UUID()
    let computer = StructureComputerStub(
      .response(
        ConversationStructureComputeResponse(
          generationId: requestGeneration,
          title: "Local Conversation",
          overview: "Stored only in GRDB",
          emoji: "✅",
          commitments: [
            ConversationCommitmentComputeCandidate(
              title: "Review", description: "Review result", start: Date(), durationMinutes: 30, created: false)
          ])))
    let service = ConversationStructureEnrichment(
      storage: owner.storage, computer: computer, requiresOwnerAuthorization: false,
      requestGeneration: { requestGeneration })

    let result = await service.process(conversationId: handle.conversationId)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(result, .applied)
    XCTAssertEqual(detail?.contentGeneration, generation)
    XCTAssertEqual(detail?.title, "Local Conversation")
    XCTAssertEqual(detail?.overview, "Stored only in GRDB")
    XCTAssertEqual(detail?.emoji, "✅")
    XCTAssertNotNil(detail?.commitmentsJson)
    XCTAssertEqual(work.first { $0.kind == .structure }?.state, .succeeded)
    XCTAssertEqual(work.first { $0.kind == .actionItems }?.state, .pending)
  }

  func testStructureFailureIsIndependentAndDurableAcrossRestart() async throws {
    let owner = try makeStructureOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let service = ConversationStructureEnrichment(
      storage: owner.storage,
      computer: StructureComputerStub(.failure),
      requiresOwnerAuthorization: false)

    let result = await service.process(conversationId: handle.conversationId)
    XCTAssertEqual(result, .failed)
    let restarted = TranscriptionStorage(databasePool: owner.pool)
    let work = try await restarted.enrichmentWork(conversationId: handle.conversationId)
    XCTAssertEqual(work.first { $0.kind == .structure }?.state, .pending)
    XCTAssertEqual(work.first { $0.kind == .structure }?.attemptCount, 1)
    XCTAssertEqual(work.first { $0.kind == .actionItems }?.state, .pending)
  }

  func testMalformedStructureCandidateFailsWithoutPartialCommit() async throws {
    let owner = try makeStructureOwner()
    defer { owner.cleanup() }
    let handle = try await processing(owner.storage)
    let requestGeneration = UUID()
    let service = ConversationStructureEnrichment(
      storage: owner.storage,
      computer: StructureComputerStub(
        .response(
          ConversationStructureComputeResponse(
            generationId: requestGeneration,
            title: "This title has more than ten words and must never be committed locally",
            overview: "Untrusted candidate",
            emoji: "✅✅",
            commitments: [
              ConversationCommitmentComputeCandidate(
                title: "Calendar side effect", description: "", start: Date(),
                durationMinutes: 30, created: true)
            ]))),
      requiresOwnerAuthorization: false,
      requestGeneration: { requestGeneration })

    let result = await service.process(conversationId: handle.conversationId)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(result, .failed)
    XCTAssertNil(detail?.title)
    XCTAssertNil(detail?.overview)
    XCTAssertNil(detail?.emoji)
    XCTAssertNil(detail?.commitmentsJson)
    XCTAssertEqual(work.first { $0.kind == .structure }?.state, .pending)
  }

  private func processing(_ storage: TranscriptionStorage) async throws -> ConversationCaptureHandle {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: start)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: nil, speakerId: 0, text: "content", startTime: 0, endTime: 2,
          isUser: true, translations: [])
      ])
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: start.addingTimeInterval(2))
    let loaded = try await storage.conversationDetail(id: handle.conversationId)
    let generation = try XCTUnwrap(loaded?.contentGeneration)
    let claimedDiscard = try await storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    let discardClaim = try XCTUnwrap(claimedDiscard)
    _ = try await storage.resolveDiscardWork(
      conversationId: handle.conversationId,
      contentGeneration: generation,
      attemptCount: discardClaim.attemptCount,
      discard: false,
      authorization: .unrestricted)
    return handle
  }

  private func makeStructureOwner() throws -> StructureStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationStructureEnrichmentTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return StructureStorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct StructureStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage
  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
