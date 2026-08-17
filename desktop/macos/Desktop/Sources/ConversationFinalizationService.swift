import Foundation

struct ConversationFinalizationProjectionFlow {
  static func run(
    finish: @escaping @Sendable () async throws -> String,
    refresh: @escaping @MainActor @Sendable () async -> Void,
    postProcess: @escaping @Sendable (String) async -> Void
  ) async throws {
    let conversationId = try await finish()
    await refresh()
    await postProcess(conversationId)
    await refresh()
  }
}

struct ConversationPostProcessProjectionFlow {
  static func run(
    conversationId: String,
    refresh: @escaping @MainActor @Sendable () async -> Void,
    postProcess: @escaping @Sendable (String) async -> Void
  ) async {
    await refresh()
    await postProcess(conversationId)
    await refresh()
  }
}

@MainActor
enum ConversationDeferredPostProcessFlow {
  static func launch(
    conversationId: String,
    postProcess: @escaping @Sendable (String) async -> Void,
    refresh: @escaping @MainActor @Sendable () async -> Void
  ) {
    Task {
      await postProcess(conversationId)
      await refresh()
    }
  }
}

/// Closes local capture and drives the three independent, durable compute work items.
/// Conversation authority never leaves the owner-scoped GRDB database.
actor ConversationFinalizationService {
  static let shared = ConversationFinalizationService(
    storage: .shared,
    discard: .shared,
    structure: .shared,
    actionItems: .shared)

  private let storage: TranscriptionStorage
  private let discard: ConversationDiscardAdmission
  private let structure: ConversationStructureEnrichment
  private let actionItems: ConversationActionItemEnrichment

  init(
    storage: TranscriptionStorage,
    discard: ConversationDiscardAdmission,
    structure: ConversationStructureEnrichment,
    actionItems: ConversationActionItemEnrichment
  ) {
    self.storage = storage
    self.discard = discard
    self.structure = structure
    self.actionItems = actionItems
  }

  func finalizeSession(
    id sessionId: Int64,
    reason: TranscriptionFinalizationReason
  ) async {
    do {
      let conversation = try await storage.finishConversation(sessionId: sessionId, reason: reason)
      await processFinishedConversation(conversationId: conversation.conversationId)
    } catch LocalMutationAuthorizationError.revoked {
      log("ConversationFinalization: Owner changed before local finalization commit")
    } catch {
      logError("ConversationFinalization: Failed to finalize local session \(sessionId)", error: error)
    }
  }

  func processFinishedConversation(conversationId: String) async {
    await processAdmissionAndEnrichment(conversationId: conversationId)
  }

  func processEnrichmentWithoutDiscard(conversationId: String) async {
    async let structureResult = structure.process(conversationId: conversationId)
    async let actionResult = actionItems.process(conversationId: conversationId)
    _ = await (structureResult, actionResult)
  }

  /// Mutations can invalidate either pre-admission or post-admission work. Inspect the current
  /// generation so callers do not have to infer the durable lifecycle from presentation status.
  func processCurrentWork(conversationId: String) async {
    do {
      guard let detail = try await storage.conversationDetail(id: conversationId) else { return }
      let work = try await storage.enrichmentWork(conversationId: conversationId)
        .filter { $0.contentGeneration == detail.contentGeneration }
      if work.contains(where: { $0.kind == .discard && $0.state == .pending }) {
        await processAdmissionAndEnrichment(conversationId: conversationId)
      } else {
        await processEnrichmentWithoutDiscard(conversationId: conversationId)
      }
    } catch {
      logError("ConversationFinalization: Failed to inspect current local work", error: error)
    }
  }

  func recoverPendingFinalizations() async {
    do {
      _ = try await storage.recoverLocalFinalization()
      let work = try await storage.recoverAndListPendingEnrichmentWork()
      let discardIds = Set(work.filter { $0.kind == .discard }.map(\.conversationId))
      for conversationId in discardIds {
        await processAdmissionAndEnrichment(conversationId: conversationId)
      }
      let structureIds = Set(work.filter { $0.kind == .structure }.map(\.conversationId))
      for conversationId in structureIds where !discardIds.contains(conversationId) {
        _ = await structure.process(conversationId: conversationId)
      }
      let actionIds = Set(work.filter { $0.kind == .actionItems }.map(\.conversationId))
      for conversationId in actionIds where !discardIds.contains(conversationId) {
        _ = await actionItems.process(conversationId: conversationId)
      }
    } catch {
      logError("ConversationFinalization: Local recovery failed", error: error)
    }
  }

  private func processAdmissionAndEnrichment(conversationId: String) async {
    let admission = await discard.process(conversationId: conversationId)
    switch admission {
    case .kept, .failedKeep:
      async let structureResult = structure.process(conversationId: conversationId)
      async let actionResult = actionItems.process(conversationId: conversationId)
      _ = await (structureResult, actionResult)
    case .deleted, .stale, .noPendingWork:
      break
    }
  }
}
