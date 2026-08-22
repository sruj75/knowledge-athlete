import GRDB
import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationSemanticRecallTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    ownerFixture = fixture
    await fixture.establish(authOwnerID: "conversation-semantic-owner")
  }

  override func tearDown() async throws {
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
  }

  func testHybridSearchPutsKeywordFirstDeduplicatesAndReusesPersistedVectorsAfterRestart() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let day = Date(timeIntervalSince1970: 1_700_006_400)
    let keyword = try await seed(
      owner, startedAt: day.addingTimeInterval(10), title: "Project ORBIT",
      overview: "A precise acronym match")
    let semantic = try await seed(
      owner, startedAt: day.addingTimeInterval(20), title: "Quarterly planning",
      overview: "Roadmap priorities and delivery sequencing")
    let embedder = ConversationEmbeddingFake()
    let recall = ConversationSemanticRecall(storage: owner.storage, embedder: embedder)
    let tools = LocalConversationToolService(storage: owner.storage, semanticRecall: recall)
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    let first = await ChatToolExecutor.execute(
      ToolCall(
        name: "search_conversations",
        arguments: ["query": "ORBIT", "limit": 2],
        thoughtSignature: nil),
      expectedOwnerID: snapshot.ownerID,
      authorizationSnapshot: snapshot,
      localConversationTools: tools)

    XCTAssertLessThan(
      try XCTUnwrap(first.range(of: keyword.conversationId)?.lowerBound),
      try XCTUnwrap(first.range(of: semantic.conversationId)?.lowerBound))
    XCTAssertEqual(first.components(separatedBy: keyword.conversationId).count - 1, 1)
    let firstBatchCount = await embedder.documentBatchCount()
    XCTAssertEqual(firstBatchCount, 1)

    await embedder.setDocumentComputeOffline(true)
    let restartedRecall = ConversationSemanticRecall(
      storage: TranscriptionStorage(databasePool: owner.pool), embedder: embedder)
    let restarted = try await restartedRecall.search(
      query: "ORBIT", startDate: nil, endDate: nil, limit: 2,
      authorizationSnapshot: snapshot)

    XCTAssertEqual(restarted.map(\.conversationId), [keyword.conversationId, semantic.conversationId])
    let restartedBatchCount = await embedder.documentBatchCount()
    XCTAssertEqual(restartedBatchCount, 1, "persisted document vectors must survive restart")
  }

  func testSameGenerationEditInvalidatesVectorAndDeletionRemovesAllSearchRows() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let conversation = try await seed(
      owner, startedAt: Date(timeIntervalSince1970: 1_700_006_400),
      title: "Quarterly planning", overview: "Initial summary")
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let sources = try await owner.storage.conversationSemanticIndexSources(authorizationSnapshot: snapshot)
    let source = try XCTUnwrap(sources.first)
    let embedder = ConversationEmbeddingFake()
    let recall = ConversationSemanticRecall(storage: owner.storage, embedder: embedder)

    let initial = try await recall.search(
      query: "semantic-only-query", startDate: nil, endDate: nil, limit: 5,
      authorizationSnapshot: snapshot)
    XCTAssertEqual(initial.map(\.conversationId), [conversation.conversationId])

    try await owner.pool.write { db in
      try db.execute(
        sql: """
          UPDATE transcription_sessions
          SET title = 'Replacement topic'
          WHERE conversationId = ?
          """,
        arguments: [conversation.conversationId])
    }
    await embedder.setDocumentComputeOffline(true)
    let afterEditWhileRefreshIsOffline = try await recall.search(
      query: "semantic-only-query", startDate: nil, endDate: nil, limit: 5,
      authorizationSnapshot: snapshot)
    XCTAssertTrue(
      afterEditWhileRefreshIsOffline.isEmpty,
      "an edited row must not rank through its stale persisted vector")

    let staleCommit = try await owner.storage.commitConversationEmbedding(
      conversationId: source.conversationId,
      contentGeneration: source.contentGeneration,
      contentHash: source.contentHash,
      vector: [1, 0],
      model: "test",
      authorizationSnapshot: snapshot)
    XCTAssertFalse(staleCommit)

    await embedder.setDocumentComputeOffline(false)
    _ = try await recall.search(
      query: "Replacement", startDate: nil, endDate: nil, limit: 5,
      authorizationSnapshot: snapshot)
    try await owner.storage.deleteConversationCascade(
      id: conversation.conversationId, authorization: .unrestricted)

    let residue = try await owner.pool.read { db in
      let fts =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM conversation_search_fts WHERE conversationId = ?",
          arguments: [conversation.conversationId]) ?? -1
      let vectors =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM conversation_embeddings WHERE conversationId = ?",
          arguments: [conversation.conversationId]) ?? -1
      return (fts, vectors)
    }
    XCTAssertEqual(residue.0, 0)
    XCTAssertEqual(residue.1, 0)
  }

  private func seed(
    _ owner: SemanticConversationStorageOwner,
    startedAt: Date,
    title: String,
    overview: String
  ) async throws -> ConversationCaptureHandle {
    let handle = try await owner.storage.beginConversation(configuration: .testDefault, startedAt: startedAt)
    _ = try await owner.storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: startedAt.addingTimeInterval(5))
    try await owner.pool.write { db in
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

  private func makeOwner() throws -> SemanticConversationStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationSemanticRecallTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return SemanticConversationStorageOwner(
      directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private actor ConversationEmbeddingFake: ConversationEmbeddingComputing {
  private var documentsOffline = false
  private var batches = 0

  func setDocumentComputeOffline(_ value: Bool) { documentsOffline = value }
  func documentBatchCount() -> Int { batches }

  func embed(
    text: String,
    taskType: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Float] {
    [1, 0]
  }

  func embedBatch(
    texts: [String],
    taskType: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [[Float]] {
    batches += 1
    if documentsOffline { throw ConversationEmbeddingFakeError.offline }
    return texts.map { text in
      text.contains("ORBIT") || text.contains("Original") || text.contains("Replacement")
        ? [0, 1]
        : [1, 0]
    }
  }
}

private enum ConversationEmbeddingFakeError: Error { case offline }

private struct SemanticConversationStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
