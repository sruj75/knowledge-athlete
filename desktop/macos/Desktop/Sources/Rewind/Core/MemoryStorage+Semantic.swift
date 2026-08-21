import Foundation
@preconcurrency import GRDB

extension MemoryStorage {
  func semanticMatches(
    queryVector: [Double],
    scope: MemoryLayerScope = .defaultAccess,
    limit: Int = 20,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [MemorySemanticMatch] {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      guard !queryVector.isEmpty, queryVector.allSatisfy(\.isFinite) else {
        throw MemoryStorageError.invalidEmbedding
      }
      let pool = try await self.database()
      try authorization.require()
      let matches = try await pool.read { db in
        try authorization.require()
        let placeholders = scope.layers.map { _ in "?" }.joined(separator: ", ")
        let expiryClause =
          scope == .defaultAccess
          ? "AND (m.layer != ? OR m.expiresAt IS NULL OR m.expiresAt > ?)"
          : ""
        var arguments: [DatabaseValue] = scope.layers.map { $0.rawValue.databaseValue }
        if scope == .defaultAccess {
          arguments.append(MemoryLayer.shortTerm.rawValue.databaseValue)
          arguments.append(Date().databaseValue)
        }
        let rows = try Row.fetchAll(
          db,
          sql: """
            SELECT m.*, e.vectorJson
            FROM memories m JOIN memory_embeddings e ON e.memoryId = m.id AND e.revision = m.revision
            WHERE m.pendingDeleteDeadline IS NULL AND m.isDismissed = 0
              AND m.layer IN (\(placeholders))
              \(expiryClause)
            """,
          arguments: StatementArguments(arguments))
        let ranked = rows.compactMap { row -> (MemoryItem, Double)? in
          guard let record = try? MemoryRecord(row: row).toMemoryItem(),
            let json: String = row["vectorJson"],
            let data = json.data(using: .utf8),
            let vector = try? JSONDecoder().decode([Double].self, from: data),
            vector.count == queryVector.count,
            let score = Self.cosine(queryVector, vector)
          else { return nil }
          return (record, score)
        }
        .sorted { lhs, rhs in
          lhs.1 == rhs.1 ? lhs.0.createdAt > rhs.0.createdAt : lhs.1 > rhs.1
        }
        .prefix(max(0, limit))
        .map { MemorySemanticMatch(memory: $0.0, score: $0.1) }
        try authorization.require()
        return ranked
      }
      try authorization.require()
      return matches
    }
  }

  func semanticSearch(
    queryVector: [Double],
    scope: MemoryLayerScope = .defaultAccess,
    limit: Int = 20,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [MemoryItem] {
    try await semanticMatches(
      queryVector: queryVector,
      scope: scope,
      limit: limit,
      authorizationSnapshot: authorizationSnapshot
    ).map(\.memory)
  }

  /// Selects bounded active context by local vector similarity to the due
  /// candidates. No query or document vector leaves the owner database here.
  func relevantConsolidationMemories(
    candidateIDs: Set<String>,
    limitPerCandidate: Int = 8,
    totalLimit: Int = 128
  ) async throws -> [MemoryItem] {
    let rowIDs = try candidateIDs.map(Self.localID)
    guard !rowIDs.isEmpty else { return [] }
    let pool = try await database()
    return try await pool.read { db in
      let candidates = try rowIDs.compactMap { id -> (Int64, [Double])? in
        guard let record = try MemoryEmbeddingRecord.fetchOne(db, key: id),
          let data = record.vectorJson.data(using: .utf8),
          let vector = try? JSONDecoder().decode([Double].self, from: data)
        else { return nil }
        return (id, vector)
      }
      guard !candidates.isEmpty else { return [] }
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT m.*, e.vectorJson
          FROM memories m JOIN memory_embeddings e
            ON e.memoryId = m.id AND e.revision = m.revision
          WHERE m.pendingDeleteDeadline IS NULL AND m.isDismissed = 0
            AND m.layer IN (?, ?)
          """,
        arguments: [MemoryLayer.shortTerm.rawValue, MemoryLayer.longTerm.rawValue])
      var bestScores: [Int64: Double] = [:]
      var items: [Int64: MemoryItem] = [:]
      for (candidateID, candidateVector) in candidates {
        let ranked = rows.compactMap { row -> (Int64, MemoryItem, Double)? in
          let id: Int64 = row["id"]
          guard id != candidateID, !rowIDs.contains(id),
            let item = try? MemoryRecord(row: row).toMemoryItem(),
            let vectorJSON: String = row["vectorJson"],
            let data = vectorJSON.data(using: .utf8),
            let vector = try? JSONDecoder().decode([Double].self, from: data),
            vector.count == candidateVector.count,
            let score = Self.cosine(candidateVector, vector)
          else { return nil }
          return (id, item, score)
        }
        .sorted { $0.2 > $1.2 }
        .prefix(max(1, limitPerCandidate))
        for (id, item, score) in ranked {
          bestScores[id] = max(bestScores[id] ?? -1, score)
          items[id] = item
        }
      }
      return bestScores.sorted { lhs, rhs in
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
      }
      .prefix(max(1, totalLimit))
      .compactMap { items[$0.key] }
    }
  }

  private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double? {
    var dot = 0.0
    var lhsMagnitude = 0.0
    var rhsMagnitude = 0.0
    for index in lhs.indices {
      dot += lhs[index] * rhs[index]
      lhsMagnitude += lhs[index] * lhs[index]
      rhsMagnitude += rhs[index] * rhs[index]
    }
    guard lhsMagnitude > 0, rhsMagnitude > 0 else { return nil }
    return dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
  }
}
