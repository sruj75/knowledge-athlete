import Foundation
import OmiSupport
import VoiceTurnDomain

extension RealtimeHubController {
  /// A deterministic screen-verification failure becomes visible before the provider can
  /// continue. Successful reports do not use this path: they keep provider narration open.
  /// Register its canonical journal obligation through the same retained receipt
  /// path as other authoritative local results before the reducer closes the turn.
  @discardableResult
  func enqueueAuthoritativeScreenEvidenceFailurePersistence(
    ownerID: String,
    assistantText: String
  ) -> Task<Bool, Never> {
    let idempotencyKey = turnIdempotencyKey
    let userText = turnTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    return enqueueTurnPersistence(idempotencyKey: idempotencyKey, retainingReceipt: true) { [weak self] in
      await self?.persistTurnDirectlyToKernel(
        ownerID: ownerID,
        userText: userText,
        assistantText: assistantText,
        interrupted: false,
        idempotencyKey: idempotencyKey,
        acceptedSpawnOwnerID: nil) ?? false
    }
  }

  /// The kernel journal is the only durable transcript authority. Swift may
  /// retry this idempotent RPC in-process, but never stores a second durable
  /// queue or projects the turn to a backend Chat store.
  func persistTurnDirectlyToKernel(
    ownerID: String,
    userText: String,
    assistantText: String,
    interrupted: Bool,
    idempotencyKey: String,
    acceptedSpawnOwnerID: String?
  ) async -> Bool {
    guard AuthorizedToolExecution.isOwnerCurrent(ownerID) else {
      log("RealtimeHub: refusing voice journal write after authenticated owner changed")
      return false
    }
    guard let surface = journalPinsByContinuityKey[idempotencyKey]?.surface else {
      log("RealtimeHub: refusing voice journal write without a pinned chat surface")
      return false
    }
    guard chatClearBarrierAllowsPersistence(to: surface) else {
      log("RealtimeHub: refusing voice journal write across an active chat clear barrier")
      return false
    }
    let kernelOwnsExchange = RealtimeHubContinuityRestore.kernelOwnsExchange(
      continuityKey: idempotencyKey,
      kernelTurnIDs: prefetchedVoiceContextTurnIDs)
    if acceptedSpawnOwnerID == ownerID
      || (kernelOwnsExchange && !streamingJournalWriteLedger.contains(continuityKey: idempotencyKey))
    {
      return await RealtimeTurnJournalAuthority.persist(
        turnOwnerID: ownerID,
        acceptedSpawnOwnerID: acceptedSpawnOwnerID,
        kernelOwnsExchange: kernelOwnsExchange,
        refreshAcceptedSpawn: {
          guard AuthorizedToolExecution.isOwnerCurrent(ownerID) else { return false }
          await FloatingControlBarManager.shared.refreshKernelJournal(surface: surface)
          return AuthorizedToolExecution.isOwnerCurrent(ownerID)
        },
        recordProviderExchange: { false })
    }

    switch await finalizeStreamingRealtimeProjection(
      ownerID: ownerID,
      userText: userText,
      assistantText: assistantText,
      continuityKey: idempotencyKey,
      status: idempotencyKey.hasPrefix("supervisor:") && interrupted ? .failed : .completed
    ) {
    case .completed(let accepted):
      return accepted
    case .absent, .recordRejected:
      break
    }

    return await RealtimeTurnJournalAuthority.persist(
      turnOwnerID: ownerID,
      acceptedSpawnOwnerID: acceptedSpawnOwnerID,
      kernelOwnsExchange: kernelOwnsExchange,
      refreshAcceptedSpawn: {
        guard AuthorizedToolExecution.isOwnerCurrent(ownerID) else { return false }
        await FloatingControlBarManager.shared.refreshKernelJournal(surface: surface)
        return AuthorizedToolExecution.isOwnerCurrent(ownerID)
      },
      recordProviderExchange: {
        guard AuthorizedToolExecution.isOwnerCurrent(ownerID) else { return false }
        for attempt in 0..<2 {
          guard AuthorizedToolExecution.isOwnerCurrent(ownerID) else { return false }
          let accepted: Bool
          if idempotencyKey.hasPrefix("supervisor:") {
            accepted = await FloatingControlBarManager.shared.recordSupervisorRealtimeExchange(
              projection: RealtimeStreamingJournalProjection(
                ownerID: ownerID, continuityKey: idempotencyKey, admissionSurface: surface),
              assistantText: assistantText, interrupted: interrupted)
          } else {
            accepted = await FloatingControlBarManager.shared.recordExchange(
              surface: surface,
              ownerID: ownerID,
              userText: userText,
              assistantText: assistantText,
              origin: "realtime_voice",
              continuityKey: idempotencyKey)
          }
          guard AuthorizedToolExecution.isOwnerCurrent(ownerID) else { return false }
          if accepted { return true }
          if attempt == 0 { try? await Task.sleep(nanoseconds: 250_000_000) }
        }
        log("RealtimeHub: kernel journal rejected voice turn (code=journal_record_failed)")
        return false
      })
  }

  /// Completes the reducer-owned journal fence only after the canonical kernel
  /// has acknowledged this turn's stable idempotency key. Merely scheduling an
  /// in-process retry is not logical success.
  func finalizeJournal(turnID: VoiceTurnID, identity: VoiceEffectIdentity) {
    if VoiceTurnCoordinator.shared.activeTurn?.providerFinished == true,
      VoiceTurnCoordinator.shared.hasDeliveredVoiceOutput(turnID: turnID)
    {
      deliveredVoiceTurnIDs.insert(turnID)
    }
    if let payload = supervisorFinalJournalPayloads.removeValue(forKey: turnID) {
      guard deliveredVoiceTurnIDs.contains(turnID) else {
        // A provider turnComplete without any acknowledged playback is not a
        // delivered intervention. Terminal cleanup records generated text failed.
        VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .providerNoResponse))
        return
      }
      enqueueTurnPersistence(idempotencyKey: payload.continuityKey, retainingReceipt: true) { [weak self] in
        await self?.persistTurnDirectlyToKernel(
          ownerID: payload.ownerID, userText: "", assistantText: payload.assistantText,
          interrupted: false, idempotencyKey: payload.continuityKey, acceptedSpawnOwnerID: nil) ?? false
      }
    }
    let idempotencyKey = turnIdempotencyKey
    Task { @MainActor [weak self] in
      guard let self else { return }
      let receipt = await self.turnPersistenceLedger.consumeReceipt(for: idempotencyKey)
      guard VoiceTurnCoordinator.shared.activeTurnID == turnID else { return }
      let accepted = receipt?.accepted == true
      guard VoiceTurnCoordinator.shared.activeTurnID == turnID else { return }
      if accepted {
        VoiceTurnCoordinator.shared.publish(
          .journalAccepted(turnID: turnID, identity: identity))
        // Gemini owns the persistence-fenced refresh through its completed-turn
        // boundary; starting another handoff here would rotate the next warm socket.
      } else {
        VoiceTurnCoordinator.shared.publish(
          .journalFailed(
            turnID: turnID,
            identity: identity,
            message: "kernel journal did not acknowledge the turn"))
      }
    }
  }
}
