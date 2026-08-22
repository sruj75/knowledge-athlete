import Foundation

/// Bridges transient embedding compute to owner-local vector persistence.
actor MemorySemanticRecall {
  static let shared = MemorySemanticRecall()

  func search(
    query: String,
    limit: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [MemorySemanticMatch] {
    let queryVector = try await EmbeddingService.shared.embed(
      text: query,
      taskType: "RETRIEVAL_QUERY",
      authorizationSnapshot: authorizationSnapshot)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    return try await MemoryStorage.shared.semanticMatches(
      queryVector: queryVector.map(Double.init),
      limit: max(1, min(limit, 20)),
      authorizationSnapshot: authorizationSnapshot)
  }
}
