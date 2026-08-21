import Foundation

protocol ConversationTaskSimilarityProviding: Sendable {
  func similarActionItems(
    for transcript: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationTaskSimilarityMatch]
}

struct LiveConversationTaskSimilarityProvider: ConversationTaskSimilarityProviding {
  func similarActionItems(
    for transcript: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationTaskSimilarityMatch] {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    if !(await EmbeddingService.shared.indexLoaded(authorizationSnapshot: authorizationSnapshot)) {
      await EmbeddingService.shared.loadIndex(authorizationSnapshot: authorizationSnapshot)
    }
    guard
      await EmbeddingService.shared.indexLoaded(
        authorizationSnapshot: authorizationSnapshot)
    else { return [] }
    let embedding = try await EmbeddingService.shared.embed(
      text: transcript,
      taskType: "RETRIEVAL_QUERY",
      authorizationSnapshot: authorizationSnapshot)
    return await EmbeddingService.shared.searchSimilar(
      query: embedding,
      topK: 30,
      authorizationSnapshot: authorizationSnapshot
    ).map { result in
      return ConversationTaskSimilarityMatch(localRowId: result.id, similarity: result.similarity)
    }
  }
}

actor ConversationActionItemEnrichment {
  static let shared = ConversationActionItemEnrichment(
    storage: .shared,
    computer: APIClient.shared,
    similarityProvider: LiveConversationTaskSimilarityProvider(),
    requiresOwnerAuthorization: true)

  private let storage: TranscriptionStorage
  private let computer: any ConversationActionItemsComputing
  private let similarityProvider: any ConversationTaskSimilarityProviding
  private let requiresOwnerAuthorization: Bool
  private let requestGeneration: @Sendable () -> UUID
  private let now: @Sendable () -> Date

  init(
    storage: TranscriptionStorage,
    computer: any ConversationActionItemsComputing,
    similarityProvider: any ConversationTaskSimilarityProviding,
    requiresOwnerAuthorization: Bool = true,
    requestGeneration: @escaping @Sendable () -> UUID = { UUID() },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.storage = storage
    self.computer = computer
    self.similarityProvider = similarityProvider
    self.requiresOwnerAuthorization = requiresOwnerAuthorization
    self.requestGeneration = requestGeneration
    self.now = now
  }

  func process(conversationId: String) async -> ConversationEnrichmentProcessResult {
    let snapshot = requiresOwnerAuthorization ? RuntimeOwnerIdentity.captureAuthorizationSnapshot() : nil
    if requiresOwnerAuthorization && snapshot == nil { return .stale }
    let authorization =
      snapshot.map { value in
        LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(value) }
      } ?? .unrestricted
    var activeClaim: ConversationDiscardWorkClaim?
    do {
      guard
        let claim = try await storage.claimEnrichmentWork(
          conversationId: conversationId, kind: .actionItems, authorization: authorization)
      else { return .noPendingWork }
      activeClaim = claim
      let transcript = LocalTranscriptFormatter.format(
        segments: claim.conversation.segments,
        speakerLabels: claim.conversation.speakerLabels.mapValues(\.name),
        userName: nil,
        includeTimestamps: false)
      let matches: [ConversationTaskSimilarityMatch]
      if let snapshot {
        matches =
          (try? await similarityProvider.similarActionItems(
            for: transcript,
            authorizationSnapshot: snapshot)) ?? []
      } else {
        matches = []
      }
      if let snapshot, !RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) { return .stale }
      let related = try await storage.relatedOpenActionItems(
        conversationId: conversationId, matches: matches, now: now())
      let tokenMap = related.enumerated().map {
        ConversationActionTaskToken(token: "t\($0.offset)", localRowId: $0.element.localRowId)
      }
      let requestTasks = zip(tokenMap, related).map { token, task in
        ConversationRelatedTaskComputeCandidate(
          token: token.token, description: task.description, dueAt: task.dueAt, completed: false)
      }
      let generationId = requestGeneration()
      let response = try await computer.computeActionItems(
        ConversationActionItemsComputeRequest(
          generationId: generationId,
          transcript: transcript,
          startedAt: claim.conversation.startedAt,
          language: claim.conversation.language,
          outputLanguage: claim.conversation.language,
          timezone: claim.conversation.timezone,
          relatedTasks: requestTasks),
        authorizationSnapshot: snapshot)
      guard response.generationId == generationId else {
        _ = try await storage.failEnrichmentWork(
          conversationId: conversationId,
          contentGeneration: claim.contentGeneration,
          attemptCount: claim.attemptCount,
          kind: .actionItems,
          reason: "response_generation_mismatch",
          authorization: authorization)
        return .failed
      }
      guard response.candidates.count <= 100 else {
        throw TranscriptionStorageError.invalidState("too many action item candidates")
      }
      let result = try await storage.completeActionItemsWork(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        response: response,
        tokenMap: tokenMap,
        authorization: authorization,
        now: now())
      return result == .stale ? .stale : (result == .applied ? .applied : .noPendingWork)
    } catch LocalMutationAuthorizationError.revoked {
      return .stale
    } catch {
      do {
        if let claim = activeClaim {
          _ = try await storage.failEnrichmentWork(
            conversationId: conversationId, contentGeneration: claim.contentGeneration,
            attemptCount: claim.attemptCount,
            kind: .actionItems,
            reason: "compute_or_commit_failed",
            authorization: authorization)
        }
      } catch {}
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "conversation_action_items", from: "model_enrichment", to: "local_transcript",
        reason: "compute_or_commit_failed", outcome: .degraded)
      return .failed
    }
  }
}
