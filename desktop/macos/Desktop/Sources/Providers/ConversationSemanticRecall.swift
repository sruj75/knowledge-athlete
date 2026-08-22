import Foundation

protocol ConversationEmbeddingComputing: Sendable {
  func embed(
    text: String,
    taskType: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Float]

  func embedBatch(
    texts: [String],
    taskType: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [[Float]]
}

extension EmbeddingService: ConversationEmbeddingComputing {}

/// Bridges transient embedding compute to the owner-local Conversation FTS and
/// vector tables. Failed or stale compute is discarded; there is no hosted
/// Conversation-search fallback.
actor ConversationSemanticRecall {
  static let shared = ConversationSemanticRecall(storage: .shared, embedder: EmbeddingService.shared)

  private let storage: TranscriptionStorage
  private let embedder: any ConversationEmbeddingComputing

  init(storage: TranscriptionStorage, embedder: any ConversationEmbeddingComputing) {
    self.storage = storage
    self.embedder = embedder
  }

  func search(
    query: String,
    startDate: Date?,
    endDate: Date?,
    limit: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalConversationSummary] {
    let normalized = query.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    guard !normalized.isEmpty else { return [] }
    let boundedLimit = max(1, min(limit, 20))

    try await refreshDocumentIndex(authorizationSnapshot: authorizationSnapshot)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }

    let keyword = try await storage.keywordConversationMatches(
      query: normalized,
      startDate: startDate,
      endDate: endDate,
      limit: boundedLimit,
      authorizationSnapshot: authorizationSnapshot)

    let semantic: [ConversationSemanticMatch]
    do {
      let queryVector = try await embedder.embed(
        text: normalized,
        taskType: "RETRIEVAL_QUERY",
        authorizationSnapshot: authorizationSnapshot)
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
        throw LocalMutationAuthorizationError.revoked
      }
      semantic = try await storage.semanticConversationMatches(
        queryVector: queryVector,
        startDate: startDate,
        endDate: endDate,
        limit: boundedLimit,
        authorizationSnapshot: authorizationSnapshot)
    } catch LocalMutationAuthorizationError.revoked {
      throw LocalMutationAuthorizationError.revoked
    } catch {
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "other",
        from: "hybrid_search",
        to: "keyword_search",
        reason: "other",
        outcome: .degraded,
        extra: [
          "fallback_detail": "query_embedding_unavailable",
          "user_visible": true,
        ])
      log("ConversationSemanticRecall: query embedding unavailable; returning keyword matches")
      semantic = []
    }

    var seen = Set<String>()
    return (keyword + semantic.map(\.conversation)).filter {
      seen.insert($0.conversationId).inserted
    }
    .prefix(boundedLimit)
    .map { $0 }
  }

  private func refreshDocumentIndex(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws {
    let sources = try await storage.conversationSemanticIndexSources(
      authorizationSnapshot: authorizationSnapshot
    ).filter(\.needsEmbedding)
    guard !sources.isEmpty else { return }

    for chunkStart in stride(from: 0, to: sources.count, by: 100) {
      let chunk = Array(sources[chunkStart..<min(chunkStart + 100, sources.count)])
      do {
        let vectors = try await embedder.embedBatch(
          texts: chunk.map(\.text),
          taskType: "RETRIEVAL_DOCUMENT",
          authorizationSnapshot: authorizationSnapshot)
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
          throw LocalMutationAuthorizationError.revoked
        }
        guard vectors.count == chunk.count else {
          DesktopDiagnosticsManager.shared.recordFallback(
            area: "other",
            from: "embedding_refresh",
            to: "current_local_index",
            reason: "other",
            outcome: .degraded,
            extra: [
              "fallback_detail": "mismatched_response",
              "user_visible": false,
            ])
          log("ConversationSemanticRecall: discarded mismatched document embedding batch")
          continue
        }
        for (source, vector) in zip(chunk, vectors) {
          _ = try await storage.commitConversationEmbedding(
            conversationId: source.conversationId,
            contentGeneration: source.contentGeneration,
            contentHash: source.contentHash,
            vector: vector,
            model: EmbeddingService.modelName,
            authorizationSnapshot: authorizationSnapshot)
        }
      } catch LocalMutationAuthorizationError.revoked {
        throw LocalMutationAuthorizationError.revoked
      } catch {
        DesktopDiagnosticsManager.shared.recordFallback(
          area: "other",
          from: "embedding_refresh",
          to: "current_local_index",
          reason: "other",
          outcome: .degraded,
          extra: [
            "fallback_detail": "embedding_unavailable",
            "user_visible": false,
          ])
        log("ConversationSemanticRecall: document embedding unavailable; keeping existing local index")
        break
      }
    }
  }
}
