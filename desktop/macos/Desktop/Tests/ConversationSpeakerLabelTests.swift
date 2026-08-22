import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationSpeakerLabelTests: XCTestCase {
  func testSingleSelectionRenamesOnlyChosenSegmentFromSharedSpeaker() async throws {
    let owner = try makeSpeakerOwner()
    defer { owner.cleanup() }
    let handle = try await owner.storage.beginConversation(configuration: .testDefault)
    let firstId = "10000000-0000-4000-8000-000000000001"
    let secondId = "10000000-0000-4000-8000-000000000002"
    try await owner.storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        .init(
          segmentId: firstId, speakerId: 2, text: "First thought.", startTime: 0, endTime: 1,
          isUser: false, translations: []),
        .init(
          segmentId: secondId, speakerId: 3, text: "Second thought.", startTime: 3, endTime: 4,
          isUser: false, translations: []),
      ])
    try await owner.pool.write { database in
      try database.execute(
        sql: "UPDATE transcription_segments SET speakerId = 2 WHERE segmentId = ?",
        arguments: [secondId])
    }

    try await owner.storage.setConversationSpeakerLabel(
      conversationId: handle.conversationId,
      speakerId: 2,
      name: "Alice",
      isUser: false,
      applyToExisting: false,
      segmentIds: [firstId],
      authorization: .unrestricted)

    let loadedDetail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let detail = try XCTUnwrap(loadedDetail)
    let first = try XCTUnwrap(detail.segments.first { $0.segmentId == firstId })
    let second = try XCTUnwrap(detail.segments.first { $0.segmentId == secondId })
    XCTAssertNotEqual(first.speakerId, 2)
    XCTAssertEqual(detail.speakerLabels[first.speakerId]?.name, "Alice")
    XCTAssertEqual(second.speakerId, 2)
    XCTAssertNil(detail.speakerLabels[2])
  }

  func testLabelIsConversationScopedAtomicAndAppliesToFutureSameSpeakerSegments() async throws {
    let owner = try makeSpeakerOwner()
    defer { owner.cleanup() }
    let first = try await active(owner.storage, text: "hello")
    let second = try await active(owner.storage, text: "other conversation")

    try await owner.storage.setConversationSpeakerLabel(
      conversationId: first.conversationId,
      speakerId: 2,
      name: "  Alice  ",
      isUser: false,
      authorization: .unrestricted)
    try await owner.storage.upsertSegments(
      conversationId: first.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: UUID().uuidString, speakerId: 2, text: "future", startTime: 2, endTime: 3,
          isUser: false, translations: [])
      ])

    let firstDetail = try await owner.storage.conversationDetail(id: first.conversationId)
    let secondDetail = try await owner.storage.conversationDetail(id: second.conversationId)
    XCTAssertEqual(firstDetail?.speakerLabels[2]?.name, "Alice")
    XCTAssertEqual(firstDetail?.segments.filter { $0.speakerId == 2 }.map(\.text), ["hello future"])
    XCTAssertNil(secondDetail?.speakerLabels[2])
  }

  func testRevokedOrBlankSaveLeavesExistingLabelUntouched() async throws {
    let owner = try makeSpeakerOwner()
    defer { owner.cleanup() }
    let handle = try await active(owner.storage, text: "hello")
    try await owner.storage.setConversationSpeakerLabel(
      conversationId: handle.conversationId, speakerId: 2, name: "Alice", isUser: false,
      authorization: .unrestricted)

    for attempt in [
      ("Bob", LocalMutationAuthorization { false }),
      ("   ", LocalMutationAuthorization.unrestricted),
    ] {
      do {
        try await owner.storage.setConversationSpeakerLabel(
          conversationId: handle.conversationId, speakerId: 2, name: attempt.0, isUser: false,
          authorization: attempt.1)
        XCTFail("Expected rejected speaker-label save")
      } catch {
        // Expected.
      }
    }

    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    XCTAssertEqual(detail?.speakerLabels[2]?.name, "Alice")
  }

  func testPostCaptureLabelChangeCreatesNewWorkGenerationAndFencesOldResponse() async throws {
    let owner = try makeSpeakerOwner()
    defer { owner.cleanup() }
    let handle = try await active(owner.storage, text: "rename me")
    _ = try await owner.storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop)
    let claimedDiscard = try await owner.storage.claimDiscardWork(
      conversationId: handle.conversationId, authorization: .unrestricted)
    let discard = try XCTUnwrap(claimedDiscard)
    _ = try await owner.storage.resolveDiscardWork(
      conversationId: handle.conversationId,
      contentGeneration: discard.contentGeneration,
      attemptCount: discard.attemptCount,
      discard: false,
      authorization: .unrestricted)
    let claimedStructure = try await owner.storage.claimEnrichmentWork(
      conversationId: handle.conversationId,
      kind: .structure,
      authorization: .unrestricted)
    let oldStructure = try XCTUnwrap(claimedStructure)
    let loadedBefore = try await owner.storage.conversationDetail(id: handle.conversationId)
    let before = try XCTUnwrap(loadedBefore)

    try await owner.storage.setConversationSpeakerLabel(
      conversationId: handle.conversationId,
      speakerId: 2,
      name: "Alice",
      isUser: false,
      authorization: .unrestricted)

    let stale = try await owner.storage.completeStructureWork(
      conversationId: handle.conversationId,
      contentGeneration: oldStructure.contentGeneration,
      attemptCount: oldStructure.attemptCount,
      response: ConversationStructureComputeResponse(
        generationId: UUID(), title: "Stale", overview: "Stale", emoji: "✅", category: "other",
        commitments: []),
      authorization: .unrestricted)
    let loadedAfter = try await owner.storage.conversationDetail(id: handle.conversationId)
    let after = try XCTUnwrap(loadedAfter)
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(stale, .stale)
    XCTAssertEqual(after.contentGeneration, before.contentGeneration + 1)
    XCTAssertEqual(after.status, .processing)
    XCTAssertNil(after.title)
    XCTAssertEqual(
      work.filter { $0.contentGeneration == before.contentGeneration && $0.kind == .structure }
        .map(\.state),
      [.superseded])
    XCTAssertEqual(
      work.filter { $0.contentGeneration == after.contentGeneration }.map(\.state),
      [.pending, .pending])
  }

  private func active(_ storage: TranscriptionStorage, text: String) async throws -> ConversationCaptureHandle {
    let handle = try await storage.beginConversation(configuration: .testDefault)
    try await storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: UUID().uuidString, speakerId: 2, text: text, startTime: 0, endTime: 1,
          isUser: false, translations: [ConversationSegmentTranslation(language: "es", text: "hola")])
      ])
    return handle
  }

  private func makeSpeakerOwner() throws -> SpeakerStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationSpeakerLabelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return SpeakerStorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct SpeakerStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
