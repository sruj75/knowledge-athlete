import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationDetailProjectionTests: XCTestCase {
  func testDetailProjectsOnlyAuthoritativeLocalRows() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let location = ConversationLocationSnapshot(latitude: 12.9, longitude: 77.6, label: "Bengaluru")
    let handle = try await owner.storage.beginConversation(
      configuration: ConversationCaptureConfiguration(
        language: "en",
        autoDetectLanguage: false,
        vocabulary: ["Omi"],
        timezone: "Asia/Kolkata",
        inputDeviceName: "Local microphone",
        location: location),
      startedAt: startedAt)
    try await owner.storage.upsertSegments(
      conversationId: handle.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: "segment-1",
          speakerId: 1,
          text: "Local transcript",
          startTime: 1,
          endTime: 3,
          isUser: false,
          translations: [.init(language: "es", text: "Transcripcion local")])
      ])
    _ = try await owner.storage.finishConversation(
      sessionId: handle.sessionId,
      reason: .userStop,
      finishedAt: startedAt.addingTimeInterval(4))
    try await owner.storage.setConversationSpeakerLabel(
      conversationId: handle.conversationId,
      speakerId: 1,
      name: "Guest",
      isUser: false,
      authorization: .unrestricted)
    let loadedCurrent = try await owner.storage.conversationDetail(id: handle.conversationId)
    let current = try XCTUnwrap(loadedCurrent)

    let commitment = ConversationCommitmentComputeCandidate(
      title: "Follow up",
      description: "Send the notes",
      start: startedAt.addingTimeInterval(3_600),
      durationMinutes: 30,
      created: false)
    let commitments = String(
      data: try JSONEncoder().encode([commitment]), encoding: .utf8)
    try await owner.pool.write { database in
      try database.execute(
        sql: """
          UPDATE transcription_sessions
          SET title = 'Local title', overview = 'Local overview', emoji = '✅', commitmentsJson = ?
          WHERE conversationId = ?
          """,
        arguments: [commitments, handle.conversationId])
      try database.execute(
        sql: """
            INSERT INTO action_items
              (description, completed, deleted, conversationId, createdAt, updatedAt)
            VALUES ('Local action', 0, 0, ?, ?, ?)
          """,
        arguments: [handle.conversationId, startedAt, startedAt])
      try database.execute(
        sql: """
          INSERT INTO conversation_enrichment_work
            (conversationId, contentGeneration, kind, state, attemptCount, lastError, createdAt, updatedAt)
          VALUES (?, ?, 'structure', 'failed', 5, 'sanitized_failure', ?, ?)
          """,
        arguments: [handle.conversationId, current.contentGeneration, startedAt, startedAt])
    }

    let detail = try await LocalAuthorityConversationDataSource(storage: owner.storage)
      .detail(id: handle.conversationId)

    XCTAssertEqual(detail.id, handle.conversationId)
    XCTAssertEqual(detail.structured.title, "Local title")
    XCTAssertEqual(detail.structured.overview, "Local overview")
    XCTAssertEqual(detail.structured.actionItems.map(\.description), ["Local action"])
    XCTAssertEqual(detail.structured.actionItems.compactMap(\.localRowId).count, 1)
    XCTAssertEqual(detail.structured.events.map(\.title), ["Follow up"])
    XCTAssertEqual(detail.transcriptSegments.map(\.speaker), ["Guest"])
    XCTAssertEqual(
      detail.transcriptSegments.first?.translations,
      [
        TranscriptTranslation(lang: "es", text: "Transcripcion local")
      ])
    XCTAssertEqual(detail.location, location)
    XCTAssertEqual(detail.inputDeviceName, "Local microphone")
    XCTAssertTrue(detail.transcriptSegmentsIncluded)
    XCTAssertEqual(detail.enrichmentFailures, [.summary])
    XCTAssertEqual(
      ConversationEnrichmentFailurePresentation.message(for: detail.enrichmentFailures),
      "Summary couldn't be generated.")
  }

  private func makeOwner() throws -> ProjectionOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationDetailProjectionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    try pool.write { database in
      try database.create(table: "action_items") { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("description", .text).notNull()
        table.column("completed", .boolean).notNull().defaults(to: false)
        table.column("deleted", .boolean).notNull().defaults(to: false)
        table.column("conversationId", .text)
        table.column("dueAt", .datetime)
        table.column("createdAt", .datetime).notNull()
        table.column("updatedAt", .datetime).notNull()
      }
    }
    return ProjectionOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct ProjectionOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
