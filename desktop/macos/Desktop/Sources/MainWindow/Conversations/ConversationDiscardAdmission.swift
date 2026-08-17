import Foundation

actor ConversationDiscardAdmission {
  static let shared = ConversationDiscardAdmission(
    storage: .shared,
    computer: APIClient.shared,
    requiresOwnerAuthorization: true)

  private let storage: TranscriptionStorage
  private let computer: any ConversationDiscardComputing
  private let requiresOwnerAuthorization: Bool

  init(
    storage: TranscriptionStorage,
    computer: any ConversationDiscardComputing,
    requiresOwnerAuthorization: Bool = true
  ) {
    self.storage = storage
    self.computer = computer
    self.requiresOwnerAuthorization = requiresOwnerAuthorization
  }

  func process(conversationId: String) async -> ConversationDiscardAdmissionResult {
    let authorizationSnapshot =
      requiresOwnerAuthorization ? RuntimeOwnerIdentity.captureAuthorizationSnapshot() : nil
    if requiresOwnerAuthorization && authorizationSnapshot == nil {
      return .stale
    }
    let authorization =
      authorizationSnapshot.map { snapshot in
        LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
      } ?? .unrestricted

    let claim: ConversationDiscardWorkClaim
    do {
      guard
        let value = try await storage.claimDiscardWork(
          conversationId: conversationId,
          authorization: authorization)
      else { return .noPendingWork }
      claim = value
    } catch LocalMutationAuthorizationError.revoked {
      return .stale
    } catch {
      logError("Conversation discard admission could not claim local work", error: error)
      return .noPendingWork
    }

    let rawTranscript = claim.conversation.segments.map(\.text).joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if rawTranscript.isEmpty {
      return await resolve(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        discard: true,
        authorization: authorization)
    }

    if Self.wordCount(rawTranscript) > 100 {
      return await resolve(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        discard: false,
        authorization: authorization)
    }

    let labels = claim.conversation.speakerLabels.mapValues(\.name)
    let formattedTranscript = LocalTranscriptFormatter.format(
      segments: claim.conversation.segments,
      speakerLabels: labels,
      userName: nil,
      includeTimestamps: false)
    guard formattedTranscript.count <= 1_000_000 else {
      return await failKeep(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        authorization: authorization,
        reason: "transcript_too_large")
    }

    let requestGeneration = UUID()
    let duration = max(
      0,
      (claim.conversation.finishedAt ?? claim.conversation.updatedAt)
        .timeIntervalSince(claim.conversation.startedAt))
    do {
      let response = try await computer.computeDiscard(
        ConversationDiscardComputeRequest(
          generationId: requestGeneration,
          transcript: formattedTranscript,
          durationSeconds: duration),
        authorizationSnapshot: authorizationSnapshot)
      guard response.generationId == requestGeneration else {
        return await failKeep(
          conversationId: conversationId,
          contentGeneration: claim.contentGeneration,
          attemptCount: claim.attemptCount,
          authorization: authorization,
          reason: "response_generation_mismatch")
      }
      return await resolve(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        discard: response.discard,
        authorization: authorization)
    } catch LocalMutationAuthorizationError.revoked {
      return .stale
    } catch {
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "conversation_discard",
        from: "model_classification",
        to: "keep",
        reason: "compute_failed",
        outcome: .degraded)
      return await failKeep(
        conversationId: conversationId,
        contentGeneration: claim.contentGeneration,
        attemptCount: claim.attemptCount,
        authorization: authorization,
        reason: "compute_failed")
    }
  }

  private func resolve(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    discard: Bool,
    authorization: LocalMutationAuthorization
  ) async -> ConversationDiscardAdmissionResult {
    do {
      switch try await storage.resolveDiscardWork(
        conversationId: conversationId,
        contentGeneration: contentGeneration,
        attemptCount: attemptCount,
        discard: discard,
        authorization: authorization)
      {
      case .deleted: return .deleted
      case .kept: return .kept
      case .stale: return .stale
      case .missing: return .noPendingWork
      }
    } catch LocalMutationAuthorizationError.revoked {
      return .stale
    } catch {
      logError("Conversation discard admission could not commit a local decision", error: error)
      return .failedKeep
    }
  }

  private func failKeep(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    authorization: LocalMutationAuthorization,
    reason: String
  ) async -> ConversationDiscardAdmissionResult {
    do {
      let result = try await storage.failDiscardWorkKeepingConversation(
        conversationId: conversationId,
        contentGeneration: contentGeneration,
        attemptCount: attemptCount,
        authorization: authorization,
        reason: reason)
      return result == .stale ? .stale : .failedKeep
    } catch LocalMutationAuthorizationError.revoked {
      return .stale
    } catch {
      logError("Conversation discard admission could not persist fail-keep", error: error)
      return .failedKeep
    }
  }

  private static func wordCount(_ text: String) -> Int {
    let scalars = text.unicodeScalars
    let eastAsianCount = scalars.reduce(into: 0) { count, scalar in
      if isWideEastAsian(scalar.value) { count += 1 }
    }
    if eastAsianCount * 10 > scalars.count * 3 {
      return eastAsianCount / 2
    }
    return text.split(whereSeparator: \Character.isWhitespace).count
  }

  private static func isWideEastAsian(_ value: UInt32) -> Bool {
    switch value {
    case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
      0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF01...0xFF60, 0xFFE0...0xFFE6,
      0x1F300...0x1FAFF, 0x20000...0x3FFFD:
      return true
    default:
      return false
    }
  }
}
