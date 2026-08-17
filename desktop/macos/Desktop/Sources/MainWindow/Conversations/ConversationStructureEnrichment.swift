import Foundation

private enum ConversationStructureCandidateValidator {
  static func normalized(_ response: ConversationStructureComputeResponse) throws
    -> ConversationStructureComputeResponse
  {
    let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.count <= 256,
      title.split(whereSeparator: \Character.isWhitespace).count <= 10
    else { throw TranscriptionStorageError.invalidState("invalid structure title") }
    let overview = response.overview.trimmingCharacters(in: .whitespacesAndNewlines)
    guard overview.count <= 50_000 else {
      throw TranscriptionStorageError.invalidState("invalid structure overview")
    }
    guard response.emoji.count == 1 else {
      throw TranscriptionStorageError.invalidState("invalid structure emoji")
    }
    guard response.commitments.count <= 100 else {
      throw TranscriptionStorageError.invalidState("too many structure commitments")
    }
    let commitments = try response.commitments.map { commitment in
      let commitmentTitle = commitment.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let description = commitment.description.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !commitmentTitle.isEmpty, commitmentTitle.count <= 256,
        description.count <= 50_000,
        commitment.durationMinutes > 0, commitment.durationMinutes <= 180,
        !commitment.created
      else { throw TranscriptionStorageError.invalidState("invalid structure commitment") }
      return ConversationCommitmentComputeCandidate(
        title: commitmentTitle, description: description, start: commitment.start,
        durationMinutes: commitment.durationMinutes, created: false)
    }
    return ConversationStructureComputeResponse(
      generationId: response.generationId, title: title, overview: overview,
      emoji: response.emoji, commitments: commitments)
  }
}

actor ConversationStructureEnrichment {
  static let shared = ConversationStructureEnrichment(
    storage: .shared, computer: APIClient.shared, requiresOwnerAuthorization: true)

  private let storage: TranscriptionStorage
  private let computer: any ConversationStructureComputing
  private let requiresOwnerAuthorization: Bool
  private let requestGeneration: @Sendable () -> UUID

  init(
    storage: TranscriptionStorage,
    computer: any ConversationStructureComputing,
    requiresOwnerAuthorization: Bool = true,
    requestGeneration: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.storage = storage
    self.computer = computer
    self.requiresOwnerAuthorization = requiresOwnerAuthorization
    self.requestGeneration = requestGeneration
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
          conversationId: conversationId, kind: .structure, authorization: authorization)
      else { return .noPendingWork }
      activeClaim = claim
      let generationId = requestGeneration()
      let response = try await computer.computeStructure(
        ConversationStructureComputeRequest(
          generationId: generationId,
          transcript: LocalTranscriptFormatter.format(
            segments: claim.conversation.segments,
            speakerLabels: claim.conversation.speakerLabels.mapValues(\.name),
            userName: nil,
            includeTimestamps: false),
          startedAt: claim.conversation.startedAt,
          language: claim.conversation.language,
          outputLanguage: claim.conversation.language,
          timezone: claim.conversation.timezone),
        authorizationSnapshot: snapshot)
      guard response.generationId == generationId else {
        _ = try await storage.failEnrichmentWork(
          conversationId: conversationId, contentGeneration: claim.contentGeneration,
          attemptCount: claim.attemptCount,
          kind: .structure, reason: "response_generation_mismatch", authorization: authorization)
        return .failed
      }
      let normalizedResponse = try ConversationStructureCandidateValidator.normalized(response)
      let result = try await storage.completeStructureWork(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        response: normalizedResponse,
        authorization: authorization)
      return result == .stale ? .stale : (result == .applied ? .applied : .noPendingWork)
    } catch LocalMutationAuthorizationError.revoked {
      return .stale
    } catch {
      do {
        if let claim = activeClaim {
          _ = try await storage.failEnrichmentWork(
            conversationId: conversationId, contentGeneration: claim.contentGeneration,
            attemptCount: claim.attemptCount,
            kind: .structure, reason: "compute_failed", authorization: authorization)
        }
      } catch {}
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "conversation_structure", from: "model_enrichment", to: "local_transcript",
        reason: "compute_failed", outcome: .degraded)
      return .failed
    }
  }
}
