import Foundation
@preconcurrency import GRDB

/// Owner-scoped authority for locally captured desktop conversations.
actor TranscriptionStorage {
  static let shared = TranscriptionStorage()

  private var databasePool: DatabasePool?
  private var databaseGeneration = -1
  let injectedDatabasePool: DatabasePool?

  private init() {
    injectedDatabasePool = nil
  }

  init(databasePool: DatabasePool) {
    injectedDatabasePool = databasePool
    self.databasePool = databasePool
  }

  func invalidateCache() {
    databasePool = nil
    databaseGeneration = -1
  }

  private func ensureInitialized() async throws -> DatabasePool {
    if let injectedDatabasePool {
      return injectedDatabasePool
    }
    if let databasePool,
      await RewindDatabase.shared.poolGeneration() == databaseGeneration
    {
      return databasePool
    }

    do {
      try await RewindDatabase.shared.initialize()
    } catch {
      log("TranscriptionStorage: Database initialization failed: \(error.localizedDescription)")
      throw error
    }

    let (pool, generation) = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    guard let pool else {
      throw TranscriptionStorageError.databaseNotInitialized
    }
    databasePool = pool
    databaseGeneration = generation
    return pool
  }

  func ensureInitializedForLocalAuthority() async throws -> DatabasePool {
    try await ensureInitialized()
  }

  func conversationArchivePage(after conversationId: String?, limit: Int) async throws -> [ConversationArchiveRecord] {
    let databasePool = try await ensureInitialized()
    let pageLimit = max(1, min(limit, 200))
    return try await databasePool.read { database in
      var arguments: StatementArguments = []
      var cursorClause = ""
      if let conversationId {
        guard
          let cursor = try Row.fetchOne(
            database,
            sql: "SELECT createdAt, id FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return [] }
        let createdAt: Date = cursor["createdAt"]
        let id: Int64 = cursor["id"]
        cursorClause = "WHERE (createdAt < ? OR (createdAt = ? AND id < ?))"
        arguments += [createdAt, createdAt, id]
      }
      arguments += [pageLimit]

      let rows = try Row.fetchAll(
        database,
        sql: """
          SELECT * FROM transcription_sessions
          \(cursorClause)
          ORDER BY createdAt DESC, id DESC
          LIMIT ?
          """,
        arguments: arguments)

      return try rows.map { row in
        let sessionId: Int64 = row["id"]
        let segments = try Row.fetchAll(
          database,
          sql: "SELECT * FROM transcription_segments WHERE sessionId = ? ORDER BY segmentOrder, id",
          arguments: [sessionId]
        ).map { segment in
          ConversationArchiveSegment(
            segmentId: segment["segmentId"],
            speakerId: segment["speakerId"],
            text: segment["text"],
            startTime: segment["startTime"],
            endTime: segment["endTime"],
            segmentOrder: segment["segmentOrder"],
            isUser: segment["isUser"],
            translationsJson: segment["translationsJson"],
            createdAt: segment["createdAt"],
            updatedAt: segment["updatedAt"])
        }
        return ConversationArchiveRecord(
          conversationId: row["conversationId"],
          startedAt: row["startedAt"],
          finishedAt: row["finishedAt"],
          language: row["language"],
          timezone: row["timezone"],
          inputDeviceName: row["inputDeviceName"],
          status: row["status"],
          title: row["title"],
          overview: row["overview"],
          emoji: row["emoji"],
          commitmentsJson: row["commitmentsJson"],
          geolocationJson: row["geolocationJson"],
          starred: row["starred"],
          folderId: row["folderId"],
          createdAt: row["createdAt"],
          updatedAt: row["updatedAt"],
          contentGeneration: row["contentGeneration"],
          segments: segments)
      }
    }
  }
}
