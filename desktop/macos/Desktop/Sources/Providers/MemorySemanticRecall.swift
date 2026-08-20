import Foundation

/// Bridges transient embedding compute to owner-local vector persistence.
actor MemorySemanticRecall {
  static let shared = MemorySemanticRecall()

  func search(query: String, limit: Int) async throws -> [MemorySemanticMatch] {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    try await RewindDatabase.shared.initialize()
    let generation = await RewindDatabase.shared.poolGeneration()
    let work = try await MemoryStorage.shared.leaseDueWork(
      kind: .embed,
      ownerGeneration: generation,
      limit: 64)

    for lease in work {
      guard lease.work.kind == MemoryProcessingKind.embed.rawValue,
        let memory = lease.memory
      else { continue }
      do {
        let vector = try await EmbeddingService.shared.embed(
          text: memory.content,
          taskType: "RETRIEVAL_DOCUMENT")
        try await authorization.withCommitLease {
          try await MemoryStorage.shared.storeEmbedding(
            workId: lease.work.id,
            memoryId: memory.id,
            expectedRevision: lease.work.inputRevision,
            model: EmbeddingService.modelName,
            vector: vector.map(Double.init),
            ownerGeneration: generation)
        }
      } catch {
        if RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
          try? await MemoryStorage.shared.retryWork(
            id: lease.work.id,
            errorCode: "embedding_compute_failed")
        }
      }
    }

    let queryVector = try await EmbeddingService.shared.embed(
      text: query,
      taskType: "RETRIEVAL_QUERY")
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    return try await MemoryStorage.shared.semanticMatches(
      queryVector: queryVector.map(Double.init),
      limit: max(1, min(limit, 20)))
  }
}
