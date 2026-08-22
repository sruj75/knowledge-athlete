import GRDB
import XCTest

@testable import Omi_Computer

@MainActor
final class PTTLocalConversationToolTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    ownerFixture = fixture
    await fixture.establish(authOwnerID: "conversation-tool-owner")
  }

  override func tearDown() async throws {
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
  }

  func testDispatcherListsLocalSummariesNewestFirstWithDatesPaginationAndNoTranscript() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let day = Date(timeIntervalSince1970: 1_700_006_400)
    _ = try await seed(
      owner.storage,
      startedAt: day.addingTimeInterval(10),
      title: "Older local title",
      overview: "Older local summary",
      transcript: "PRIVATE TRANSCRIPT MUST NOT LEAK")
    _ = try await seed(
      owner.storage,
      startedAt: day.addingTimeInterval(20),
      title: "Newest local title",
      overview: "Newest local summary",
      transcript: "ANOTHER PRIVATE TRANSCRIPT")
    _ = try await seed(
      owner.storage,
      startedAt: day.addingTimeInterval(86_400),
      title: "Outside range",
      overview: "Not returned",
      transcript: nil)

    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let tools = LocalConversationToolService(storage: owner.storage)
    let result = await ChatToolExecutor.execute(
      ToolCall(
        name: "get_conversations",
        arguments: [
          "start_date": ISO8601DateFormatter().string(from: day),
          "end_date": ISO8601DateFormatter().string(from: day.addingTimeInterval(86_400)),
          "limit": 1,
          "offset": 0,
          "include_transcript": true,
        ],
        thoughtSignature: nil),
      expectedOwnerID: snapshot.ownerID,
      authorizationSnapshot: snapshot,
      localConversationTools: tools)

    XCTAssertTrue(result.contains("Newest local title"))
    XCTAssertTrue(result.contains("Newest local summary"))
    XCTAssertFalse(result.contains("Older local title"))
    XCTAssertFalse(result.contains("PRIVATE TRANSCRIPT"))
    XCTAssertFalse(result.contains("ANOTHER PRIVATE TRANSCRIPT"))

    let restarted = LocalConversationToolService(
      storage: TranscriptionStorage(databasePool: owner.pool))
    let secondPage = await ChatToolExecutor.execute(
      ToolCall(
        name: "get_conversations",
        arguments: [
          "start_date": ISO8601DateFormatter().string(from: day),
          "end_date": ISO8601DateFormatter().string(from: day.addingTimeInterval(86_400)),
          "limit": 1,
          "offset": 1,
        ],
        thoughtSignature: nil),
      expectedOwnerID: snapshot.ownerID,
      authorizationSnapshot: snapshot,
      localConversationTools: restarted)
    XCTAssertTrue(secondPage.contains("Older local title"))
    XCTAssertFalse(secondPage.contains("Newest local title"))
  }

  private func seed(
    _ storage: TranscriptionStorage,
    startedAt: Date,
    title: String,
    overview: String,
    transcript: String?
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
    try await ownerPool(storage).write { db in
      try db.execute(
        sql: """
          UPDATE transcription_sessions
          SET title = ?, overview = ?, status = 'completed'
          WHERE conversationId = ?
          """,
        arguments: [title, overview, handle.conversationId])
    }
    return handle
  }

  private func ownerPool(_ storage: TranscriptionStorage) async throws -> DatabasePool {
    try await storage.ensureInitializedForLocalAuthority()
  }

  private func makeOwner() throws -> PTTConversationToolStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PTTLocalConversationToolTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return PTTConversationToolStorageOwner(
      directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct PTTConversationToolStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
