import CryptoKit
import Foundation
@preconcurrency import GRDB

struct ConversationSemanticIndexSource: Equatable, Sendable {
  let conversationId: String
  let contentGeneration: Int
  let contentHash: String
  let text: String
  let indexedGeneration: Int?
  let indexedHash: String?

  var needsEmbedding: Bool {
    indexedGeneration != contentGeneration || indexedHash != contentHash
  }
}

struct ConversationSemanticMatch: Equatable, Sendable {
  let conversation: LocalConversationSummary
  let score: Double
}

extension TranscriptionStorage {
  func conversationSemanticIndexSources(
    limit: Int = 5_000,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationSemanticIndexSource] {
    try await withConversationSemanticRead(authorizationSnapshot) { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT s.conversationId, s.contentGeneration, s.title, s.overview,
                 e.contentGeneration AS indexedGeneration, e.contentHash AS indexedHash
          FROM transcription_sessions s
          LEFT JOIN conversation_embeddings e ON e.conversationId = s.conversationId
          WHERE s.status NOT IN ('recording', 'merging')
            AND TRIM(COALESCE(s.title, '') || ' ' || COALESCE(s.overview, '')) != ''
          ORDER BY s.startedAt DESC, s.id DESC
          LIMIT ?
          """,
        arguments: [max(1, min(limit, 5_000))]
      ).map { row in
        let text = Self.conversationSemanticText(title: row["title"], overview: row["overview"])
        return ConversationSemanticIndexSource(
          conversationId: row["conversationId"],
          contentGeneration: row["contentGeneration"],
          contentHash: Self.conversationSemanticHash(text),
          text: text,
          indexedGeneration: row["indexedGeneration"],
          indexedHash: row["indexedHash"])
      }
    }
  }

  func commitConversationEmbedding(
    conversationId: String,
    contentGeneration: Int,
    contentHash: String,
    vector: [Float],
    model: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Bool {
    guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return false }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    let pool = try await ensureInitializedForLocalAuthority()
    let vectorData = try JSONEncoder().encode(vector)
    let vectorJSON = String(decoding: vectorData, as: UTF8.self)
    return try await authorization.withCommitLease {
      try await pool.write { db in
        try authorization.require()
        guard
          let row = try Row.fetchOne(
            db,
            sql: "SELECT contentGeneration, title, overview FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return false }
        let currentGeneration: Int = row["contentGeneration"]
        let currentText = Self.conversationSemanticText(title: row["title"], overview: row["overview"])
        guard currentGeneration == contentGeneration,
          Self.conversationSemanticHash(currentText) == contentHash
        else { return false }
        try db.execute(
          sql: """
            INSERT INTO conversation_embeddings
              (conversationId, contentGeneration, contentHash, vectorJson, model, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(conversationId) DO UPDATE SET
              contentGeneration = excluded.contentGeneration,
              contentHash = excluded.contentHash,
              vectorJson = excluded.vectorJson,
              model = excluded.model,
              updatedAt = excluded.updatedAt
            """,
          arguments: [conversationId, contentGeneration, contentHash, vectorJSON, model, Date()])
        try authorization.require()
        return true
      }
    }
  }

  func keywordConversationMatches(
    query: String,
    startDate: Date?,
    endDate: Date?,
    limit: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalConversationSummary] {
    let matchQuery = Self.conversationFTSQuery(query)
    guard !matchQuery.isEmpty else { return [] }
    return try await withConversationSemanticRead(authorizationSnapshot) { db in
      var clauses = [
        "conversation_search_fts MATCH ?",
        "s.status NOT IN ('recording', 'merging')",
      ]
      var arguments: StatementArguments = [matchQuery]
      if let startDate {
        clauses.append("s.startedAt >= ?")
        arguments += [startDate]
      }
      if let endDate {
        clauses.append("s.startedAt < ?")
        arguments += [endDate]
      }
      arguments += [max(1, min(limit, 20))]
      return try Row.fetchAll(
        db,
        sql: """
          SELECT s.*,
                 (SELECT COUNT(*) FROM transcription_segments seg WHERE seg.sessionId = s.id) AS segmentCount
          FROM conversation_search_fts
          JOIN transcription_sessions s ON s.id = conversation_search_fts.rowid
          WHERE \(clauses.joined(separator: " AND "))
          ORDER BY bm25(conversation_search_fts), s.startedAt DESC, s.id DESC
          LIMIT ?
          """,
        arguments: arguments
      ).map(Self.makeLocalConversationSummary)
    }
  }

  func semanticConversationMatches(
    queryVector: [Float],
    startDate: Date?,
    endDate: Date?,
    limit: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationSemanticMatch] {
    guard !queryVector.isEmpty, queryVector.allSatisfy(\.isFinite) else { return [] }
    return try await withConversationSemanticRead(authorizationSnapshot) { db in
      var clauses = ["s.status NOT IN ('recording', 'merging')"]
      var arguments: StatementArguments = []
      if let startDate {
        clauses.append("s.startedAt >= ?")
        arguments += [startDate]
      }
      if let endDate {
        clauses.append("s.startedAt < ?")
        arguments += [endDate]
      }
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT s.*, e.vectorJson,
                 (SELECT COUNT(*) FROM transcription_segments seg WHERE seg.sessionId = s.id) AS segmentCount
          FROM conversation_embeddings e
          JOIN transcription_sessions s ON s.conversationId = e.conversationId
          WHERE e.contentGeneration = s.contentGeneration
            AND \(clauses.joined(separator: " AND "))
          """,
        arguments: arguments)
      return rows.compactMap { row -> ConversationSemanticMatch? in
        guard let json: String = row["vectorJson"],
          let data = json.data(using: .utf8),
          let vector = try? JSONDecoder().decode([Float].self, from: data),
          vector.count == queryVector.count,
          let score = Self.conversationCosine(queryVector, vector)
        else { return nil }
        return ConversationSemanticMatch(
          conversation: Self.makeLocalConversationSummary(row), score: score)
      }
      .sorted {
        $0.score == $1.score
          ? $0.conversation.startedAt > $1.conversation.startedAt
          : $0.score > $1.score
      }
      .prefix(max(1, min(limit, 20)))
      .map { $0 }
    }
  }

  private func withConversationSemanticRead<T: Sendable>(
    _ snapshot: RuntimeOwnerAuthorizationSnapshot,
    operation: @escaping @Sendable (Database) throws -> T
  ) async throws -> T {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    let pool = try await ensureInitializedForLocalAuthority()
    return try await authorization.withReadLease {
      try authorization.require()
      let value = try await pool.read { db in
        try authorization.require()
        return try operation(db)
      }
      try authorization.require()
      return value
    }
  }

  nonisolated private static func conversationSemanticText(title: String?, overview: String?) -> String {
    [title, overview]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  nonisolated private static func conversationSemanticHash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  nonisolated private static func conversationFTSQuery(_ query: String) -> String {
    query.split { !$0.isLetter && !$0.isNumber }
      .map { "\"\(String($0).replacingOccurrences(of: "\"", with: "\"\""))\"*" }
      .joined(separator: " OR ")
  }

  nonisolated private static func conversationCosine(_ lhs: [Float], _ rhs: [Float]) -> Double? {
    var dot = 0.0
    var lhsMagnitude = 0.0
    var rhsMagnitude = 0.0
    for index in lhs.indices {
      let left = Double(lhs[index])
      let right = Double(rhs[index])
      dot += left * right
      lhsMagnitude += left * left
      rhsMagnitude += right * right
    }
    guard lhsMagnitude > 0, rhsMagnitude > 0 else { return nil }
    return dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
  }
}
