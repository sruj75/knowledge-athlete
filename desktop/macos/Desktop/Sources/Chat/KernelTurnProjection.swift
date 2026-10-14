import CryptoKit
import Foundation

struct KernelAutomationTurnRange: Equatable, Sendable {
  let conversationId: String
  let generation: Int
  let turns: [KernelJournalTurn]
}

/// Main-chat projection over the kernel-owned journal. Runtime notifications
/// are wakeups only; every mutation is replayed in contiguous turnSeq order.
@MainActor
final class KernelTurnProjection {
  private struct OwnerLease: Equatable {
    let ownerID: String
    let epoch: UInt64
    let authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  }

  struct ExchangeTurn {
    let message: ChatMessage
    let status: KernelJournalTurnStatus
  }

  typealias JournalListOperation = (
    _ client: AgentClient.Session,
    _ surface: AgentSurfaceReference,
    _ ownerID: String,
    _ afterTurnSeq: Int,
    _ limit: Int
  ) async throws -> AgentRuntimeProcess.JournalOperationResult

  typealias JournalClearOperation = (
    _ client: AgentClient.Session,
    _ surface: AgentSurfaceReference,
    _ ownerID: String,
    _ expectedGeneration: Int,
    _ deleteBackend: Bool
  ) async throws -> Int

  typealias KernelReadyOperation = () async -> Bool
  typealias JournalRecordExchangeOperation = (
    _ client: AgentClient.Session,
    _ surface: AgentSurfaceReference,
    _ ownerID: String,
    _ writes: [KernelJournalTurnWrite],
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> AgentRuntimeProcess.JournalOperationResult

  private weak var host: ChatProvider?
  private var client: AgentClient.Session?
  private var eventToken: UUID?
  private let ownerIDProvider: () -> String?
  private let journalListOperation: JournalListOperation?
  private let journalClearOperation: JournalClearOperation?
  private let kernelReadyOperation: KernelReadyOperation?
  private let journalRecordExchangeOperation: JournalRecordExchangeOperation?
  private var projectionEpoch: UInt64 = 0
  private var boundOwnerID: String?
  private var highWaterByConversation: [String: Int] = [:]
  private var generationByConversation: [String: Int] = [:]
  private var conversationBySurface: [String: String] = [:]
  private var refreshingSurfaceEpochs: [String: UInt64] = [:]
  private var refreshRequestedSurfaceEpochs: [String: UInt64] = [:]

  init(
    host: ChatProvider,
    client: AgentClient.Session? = nil,
    ownerIDProvider: @escaping () -> String? = { RuntimeOwnerIdentity.currentOwnerId() },
    journalListOperation: JournalListOperation? = nil,
    journalClearOperation: JournalClearOperation? = nil,
    kernelReadyOperation: KernelReadyOperation? = nil,
    journalRecordExchangeOperation: JournalRecordExchangeOperation? = nil
  ) {
    self.host = host
    self.client = client
    self.ownerIDProvider = ownerIDProvider
    self.journalListOperation = journalListOperation
    self.journalClearOperation = journalClearOperation
    self.kernelReadyOperation = kernelReadyOperation
    self.journalRecordExchangeOperation = journalRecordExchangeOperation
  }

  func attachClient(_ client: AgentClient.Session) async {
    self.client = client
    guard let lease = captureOwnerLease() else { return }
    KernelJournalEventHub.shared.unsubscribe(eventToken)
    await KernelJournalEventHub.shared.attach(client: client)
    guard isCurrent(lease) else { return }
    eventToken = KernelJournalEventHub.shared.subscribe(surface: nil) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, let surface = self.host?.mainChatSurfaceReference() else { return }
        await self.refresh(surface: surface)
      }
    }
    // The visible-chat loader owns the first replay so it can keep the
    // transcript in its loading state until the complete snapshot is ready.
    // Event notifications above still refresh an already-mounted surface.
  }

  /// Attach the owner-bound client for a non-production journal control action
  /// without starting a model session or scheduling projection refresh work.
  func attachControlClient(_ client: AgentClient.Session) {
    self.client = client
  }

  /// Synchronous owner teardown. Suspended work retains its old epoch and can
  /// neither mutate checkpoints nor project owner A rows after owner B starts.
  func invalidateOwnerState() {
    projectionEpoch &+= 1
    boundOwnerID = nil
    highWaterByConversation.removeAll()
    generationByConversation.removeAll()
    conversationBySurface.removeAll()
    refreshingSurfaceEpochs.removeAll()
    refreshRequestedSurfaceEpochs.removeAll()
    if let host {
      host.resetJournalProjection(surface: host.mainChatSurfaceReference())
    }
  }

  /// Ordered replay. A gap never advances the checkpoint: the next page starts
  /// from the last contiguous turnSeq, so out-of-order wakeups cannot drop data.
  @discardableResult
  func refresh(surface: AgentSurfaceReference) async -> Bool {
    guard let lease = captureOwnerLease() else { return false }
    return await refresh(surface: surface, lease: lease, publishPartialResults: true)
  }

  private func refresh(
    surface: AgentSurfaceReference,
    lease: OwnerLease,
    publishPartialResults: Bool
  ) async -> Bool {
    guard isCurrent(lease), let client else { return false }
    let surfaceKey = surface.key
    if refreshingSurfaceEpochs[surfaceKey] == lease.epoch {
      refreshRequestedSurfaceEpochs[surfaceKey] = lease.epoch
      return true
    }
    refreshingSurfaceEpochs[surfaceKey] = lease.epoch
    defer {
      if refreshingSurfaceEpochs[surfaceKey] == lease.epoch {
        refreshingSurfaceEpochs.removeValue(forKey: surfaceKey)
      }
    }

    // A restored conversation is not live streaming. Collect all contiguous
    // turns fetched by this refresh, then publish one coherent transcript
    // snapshot after the journal range is settled. Publishing each durable row
    // independently makes first launch look like the user is watching old
    // history arrive in real time, and causes the chat viewport to chase it.
    var pendingProjectionTurns: [KernelJournalTurn] = []
    var shouldResetProjection = false
    var refreshSucceeded = true

    repeat {
      guard isCurrent(lease) else { return false }
      // A queued request is a fresh attempt. Its outcome supersedes an earlier
      // failed pass once the accumulated replacement snapshot is complete.
      refreshSucceeded = true
      if refreshRequestedSurfaceEpochs[surfaceKey] == lease.epoch {
        refreshRequestedSurfaceEpochs.removeValue(forKey: surfaceKey)
      }
      var shouldContinue = true
      while shouldContinue {
        guard isCurrent(lease) else { return false }
        let knownConversation = conversationBySurface[surfaceKey]
        let knownCheckpoint = knownConversation.map {
          checkpointKeyFor(conversationId: $0, surface: surface)
        }
        let after = knownCheckpoint.flatMap { highWaterByConversation[$0] } ?? 0
        do {
          let page = try await listJournalTurns(
            client: client,
            surface: surface,
            ownerID: lease.ownerID,
            afterTurnSeq: after,
            limit: 100
          )
          guard isCurrent(lease) else { return false }
          let conversationId = page.conversationId
          guard !conversationId.isEmpty else {
            shouldContinue = false
            break
          }
          conversationBySurface[surfaceKey] = conversationId
          let checkpointKey = checkpointKeyFor(conversationId: conversationId, surface: surface)
          let currentGeneration = generationByConversation[checkpointKey]
          if currentGeneration != page.conversationGeneration {
            highWaterByConversation[checkpointKey] = page.generationBaseTurnSeq
            generationByConversation[checkpointKey] = page.conversationGeneration
            guard isCurrent(lease) else { return false }
            // A newer generation invalidates every accumulated row from the
            // prior one. Keep the reset and its replacement snapshot atomic.
            pendingProjectionTurns.removeAll()
            shouldResetProjection = true
          }
          generationByConversation[checkpointKey] = page.conversationGeneration
          var contiguous = highWaterByConversation[checkpointKey] ?? 0
          let contiguousPage = KernelJournalReplay.contiguousTurns(
            from: page.turns,
            after: contiguous
          )
          for turn in contiguousPage {
            guard isCurrent(lease) else { return false }
            pendingProjectionTurns.append(turn)
            contiguous = turn.turnSeq
            highWaterByConversation[checkpointKey] = contiguous
          }
          let firstUnapplied = page.turns
            .filter { $0.turnSeq > contiguous }
            .min { $0.turnSeq < $1.turnSeq }
          if let firstUnapplied {
            log(
              "KernelTurnProjection: journal gap detected "
                + "(conversation=\(conversationId), expected=\(contiguous + 1), got=\(firstUnapplied.turnSeq))"
            )
            shouldContinue = false
          } else if contiguousPage.isEmpty || contiguous >= page.highWaterTurnSeq {
            shouldContinue = false
          } else if !shouldContinue {
            // Leave the checkpoint at the last contiguous sequence. A later
            // wakeup or explicit refresh requests the missing range again.
            break
          }
        } catch {
          if isCurrent(lease) {
            log("KernelTurnProjection: journal replay failed (code=journal_range_fetch_failed)")
          }
          refreshSucceeded = false
          shouldContinue = false
        }
      }
    } while isCurrent(lease) && refreshRequestedSurfaceEpochs[surfaceKey] == lease.epoch

    guard isCurrent(lease) else { return false }
    if !refreshSucceeded, !publishPartialResults {
      return false
    }
    if host?.shouldProjectJournalSurface(surface) == true {
      if shouldResetProjection {
        host?.resetJournalProjection(surface: surface)
      }
      host?.projectJournalTurns(pendingProjectionTurns)
    }
    return refreshSucceeded
  }

  @discardableResult
  func reload(surface: AgentSurfaceReference) async -> Bool {
    guard let lease = captureOwnerLease(), isCurrent(lease) else { return false }
    let surfaceKey = surface.key
    if refreshingSurfaceEpochs[surfaceKey] == lease.epoch {
      refreshRequestedSurfaceEpochs[surfaceKey] = lease.epoch
      return false
    }
    let previousConversationId = conversationBySurface.removeValue(forKey: surfaceKey)
    let previousCheckpointKey = previousConversationId.map {
      checkpointKeyFor(conversationId: $0, surface: surface)
    }
    let previousHighWater = previousCheckpointKey.flatMap { highWaterByConversation[$0] }
    let previousGeneration = previousCheckpointKey.flatMap { generationByConversation[$0] }
    if let conversationId = previousConversationId {
      let key = checkpointKeyFor(conversationId: conversationId, surface: surface)
      highWaterByConversation.removeValue(forKey: key)
      generationByConversation.removeValue(forKey: key)
    }
    guard isCurrent(lease) else { return false }
    // The refresh builds a complete replacement snapshot and publishes it
    // atomically. Keep the current projection visible if fetching fails.
    let reloaded = await refresh(
      surface: surface,
      lease: lease,
      publishPartialResults: false
    )
    guard !reloaded, isCurrent(lease) else { return reloaded }

    if let failedConversationId = conversationBySurface.removeValue(forKey: surfaceKey) {
      let failedKey = checkpointKeyFor(conversationId: failedConversationId, surface: surface)
      highWaterByConversation.removeValue(forKey: failedKey)
      generationByConversation.removeValue(forKey: failedKey)
    }
    if let previousConversationId, let previousCheckpointKey {
      conversationBySurface[surfaceKey] = previousConversationId
      if let previousHighWater {
        highWaterByConversation[previousCheckpointKey] = previousHighWater
      }
      if let previousGeneration {
        generationByConversation[previousCheckpointKey] = previousGeneration
      }
    }
    return false
  }

  @discardableResult
  func recordTurn(
    surface: AgentSurfaceReference,
    message: ChatMessage,
    origin: String,
    status: KernelJournalTurnStatus,
    continuityKey: String? = nil,
    sessionId: String? = nil,
    messageSource: String? = nil,
    ownerID: String? = nil
  ) async -> KernelJournalTurn? {
    guard let lease = captureOwnerLease(ownerID: ownerID), let host else { return nil }
    guard await host.ensureBridgeStartedForKernel(), isCurrent(lease), let client else { return nil }
    do {
      let turn = try await client.recordJournalTurn(
        surface: surface,
        ownerID: lease.ownerID,
        turn: message.journalWrite(
          origin: origin,
          status: status,
          continuityKey: continuityKey,
          sessionId: sessionId,
          messageSource: messageSource
        ),
        expectedGeneration: try await currentGeneration(client: client, surface: surface, lease: lease)
      )
      guard isCurrent(lease) else { return nil }
      _ = await refresh(surface: surface, lease: lease, publishPartialResults: true)
      guard isCurrent(lease) else { return nil }
      return turn
    } catch {
      log("KernelTurnProjection: journal record failed (code=journal_record_failed)")
      return nil
    }
  }

  @discardableResult
  func updateTurn(
    surface: AgentSurfaceReference,
    message: ChatMessage,
    status: KernelJournalTurnStatus? = nil,
    ownerID: String? = nil
  ) async -> KernelJournalTurn? {
    guard let lease = captureOwnerLease(ownerID: ownerID), let host else { return nil }
    guard await host.ensureBridgeStartedForKernel(), isCurrent(lease), let client else { return nil }
    do {
      let result = try await client.updateJournalTurnWithReceipt(
        surface: surface,
        ownerID: lease.ownerID,
        update: message.journalUpdate(status: status),
        expectedGeneration: try await currentGeneration(client: client, surface: surface, lease: lease)
      )
      guard let turn = result.turn else { return nil }
      guard isCurrent(lease) else { return nil }
      _ = await refresh(surface: surface, lease: lease, publishPartialResults: true)
      guard isCurrent(lease) else { return nil }
      if result.firstCompletedRealPair, let exchange = result.firstCompletedRealExchange {
        scheduleCatalogTitleGeneration(
          host: host,
          chatID: surface.externalRefId,
          ownerID: lease.ownerID,
          userText: exchange.userText,
          assistantText: exchange.assistantText
        )
      }
      return turn
    } catch {
      log("KernelTurnProjection: journal update failed (code=journal_update_failed)")
      return nil
    }
  }

  @discardableResult
  func repairNonterminalTurns(
    surface: AgentSurfaceReference,
    turnIDs: [String],
    ownerID: String
  ) async -> Int {
    guard !turnIDs.isEmpty,
      let lease = captureOwnerLease(ownerID: ownerID),
      let host
    else { return 0 }
    guard await host.ensureBridgeStartedForKernel(), isCurrent(lease), let client else { return 0 }
    do {
      let repaired = try await client.repairJournalTurns(
        surface: surface,
        ownerID: lease.ownerID,
        turnIDs: turnIDs,
        expectedGeneration: try await currentGeneration(client: client, surface: surface, lease: lease)
      )
      guard isCurrent(lease) else { return 0 }
      _ = await refresh(surface: surface, lease: lease, publishPartialResults: true)
      return isCurrent(lease) ? repaired.count : 0
    } catch {
      log("KernelTurnProjection: journal repair failed (code=journal_repair_failed)")
      return 0
    }
  }

  /// The query result is the authoritative final material. The streaming row is
  /// an optimistic projection and can lag its terminal callback; use it only
  /// when the final result intentionally contains no text.
  static func acceptedTerminalContent(message: ChatMessage?, acceptedContent: String?) -> String? {
    if let acceptedContent, !acceptedContent.isEmpty { return acceptedContent }
    return message.flatMap { $0.text.isEmpty ? nil : $0.text }
  }

  static func acceptedTerminalContentBlocks(
    message: ChatMessage?,
    acceptedContent: String?
  ) -> [ChatContentBlock] {
    guard let acceptedContent, !acceptedContent.isEmpty else { return message?.contentBlocks ?? [] }
    let nonTextBlocks =
      message?.contentBlocks.filter {
        if case .text = $0 { return false }
        return true
      } ?? []
    let messageID = message?.id ?? "terminal"
    return [.text(id: "\(messageID):terminal", text: acceptedContent)] + nonTextBlocks
  }

  /// Terminalize an existing turn without sourcing payload from the current UI
  /// projection. Stopped turns can legitimately have no visible placeholder;
  /// lifecycle durability must not depend on one being present.
  @discardableResult
  func updateTurnStatus(
    surface: AgentSurfaceReference,
    turnId: String,
    status: KernelJournalTurnStatus,
    ownerID: String? = nil
  ) async -> KernelJournalTurn? {
    guard let lease = captureOwnerLease(ownerID: ownerID), let host else { return nil }
    guard await host.ensureBridgeStartedForKernel(), isCurrent(lease), let client else { return nil }
    do {
      let turn = try await client.updateJournalTurn(
        surface: surface,
        ownerID: lease.ownerID,
        update: .statusOnly(turnId: turnId, status: status),
        expectedGeneration: try await currentGeneration(client: client, surface: surface, lease: lease)
      )
      guard isCurrent(lease) else { return nil }
      _ = await refresh(surface: surface, lease: lease, publishPartialResults: true)
      guard isCurrent(lease) else { return nil }
      return turn
    } catch {
      log("KernelTurnProjection: journal status update failed (code=journal_status_update_failed)")
      return nil
    }
  }

  /// Convenience for a logical exchange. IDs derive from the opaque continuity
  /// key, so retries cannot create a second user/assistant row.
  @discardableResult
  func recordExchange(
    surface: AgentSurfaceReference,
    userText: String,
    assistantText: String,
    origin: String,
    continuityKey: String,
    assistantContentBlocks: [ChatContentBlock] = [],
    resources: [ChatResource] = [],
    ownerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    expectedGeneration: Int? = nil
  ) async -> Bool {
    let baseDate = Date()
    var writes: [KernelJournalTurnWrite] = []
    if !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let user = ChatMessage(
        id: Self.stableTurnID(continuityKey: continuityKey, role: "user"),
        clientTurnId: continuityKey,
        text: userText,
        createdAt: baseDate,
        sender: .user
      )
      writes.append(
        user.journalWrite(
          origin: origin,
          status: .completed,
          continuityKey: continuityKey,
          messageSource: origin
        ))
    }
    if !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !assistantContentBlocks.isEmpty || !resources.isEmpty
    {
      let assistant = ChatMessage(
        id: Self.stableTurnID(continuityKey: continuityKey, role: "assistant"),
        clientTurnId: continuityKey,
        text: assistantText.isEmpty ? "Done." : assistantText,
        createdAt: baseDate.addingTimeInterval(0.001),
        sender: .ai,
        contentBlocks: assistantContentBlocks,
        resources: resources
      )
      writes.append(
        assistant.journalWrite(
          origin: origin,
          status: .completed,
          continuityKey: continuityKey,
          messageSource: origin
        ))
    }

    return await recordExchange(
      surface: surface,
      writes: writes,
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot,
      expectedGeneration: expectedGeneration
    ) != nil
  }

  /// Admit prebuilt visible turns under one journal transaction. This is the
  /// canonical typed-chat entry point because it preserves caller-owned
  /// message IDs, attachments, and a deliberately empty streaming placeholder.
  @discardableResult
  func recordExchange(
    surface: AgentSurfaceReference,
    turns: [ExchangeTurn],
    origin: String,
    continuityKey: String,
    sessionId: String? = nil,
    messageSource: String,
    ownerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    expectedGeneration: Int? = nil
  ) async -> [KernelJournalTurn]? {
    let writes = turns.map { entry in
      entry.message.journalWrite(
        origin: origin,
        status: entry.status,
        continuityKey: continuityKey,
        sessionId: sessionId,
        messageSource: messageSource
      )
    }
    return await recordExchange(
      surface: surface,
      writes: writes,
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot, expectedGeneration: expectedGeneration)
  }

  @discardableResult
  private func recordExchange(
    surface: AgentSurfaceReference,
    writes: [KernelJournalTurnWrite],
    ownerID: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?,
    expectedGeneration: Int? = nil,
    revise: Bool = false
  ) async -> [KernelJournalTurn]? {
    guard !writes.isEmpty, writes.count <= 2 else { return nil }
    let roles = writes.map(\.role)
    guard
      roles == ["user"] || roles == ["assistant"]
        || roles == ["user", "assistant"]
    else { return nil }
    guard
      let lease = captureOwnerLease(
        ownerID: ownerID,
        authorizationSnapshot: authorizationSnapshot),
      let host
    else { return nil }
    let kernelReady =
      if let kernelReadyOperation {
        await kernelReadyOperation()
      } else {
        await host.ensureBridgeStartedForKernel()
      }
    guard kernelReady, isCurrent(lease), let client else { return nil }

    do {
      let result =
        if let journalRecordExchangeOperation {
          try await journalRecordExchangeOperation(
            client,
            surface,
            lease.ownerID,
            writes,
            lease.authorizationSnapshot)
        } else {
          try await persistExchange(
            client: client, surface: surface, lease: lease,
            writes: writes, expectedGeneration: expectedGeneration, revise: revise)
        }
      guard isCurrent(lease), result.operation == "record_exchange" else { return nil }
      let expectedTurnIDs = Set(writes.map(\.turnId))
      guard
        result.turns.count == writes.count,
        Set(result.turns.map(\.turnId)) == expectedTurnIDs,
        !result.conversationId.isEmpty
      else {
        log("KernelTurnProjection: journal exchange returned an invalid receipt")
        return nil
      }
      applyAcceptedExchange(result, surface: surface, lease: lease)
      if result.firstCompletedRealPair, let exchange = result.firstCompletedRealExchange {
        scheduleCatalogTitleGeneration(
          host: host,
          chatID: surface.externalRefId,
          ownerID: lease.ownerID,
          userText: exchange.userText,
          assistantText: exchange.assistantText
        )
      }
      return isCurrent(lease) ? result.turns : nil
    } catch {
      if isCurrent(lease) {
        log("KernelTurnProjection: journal exchange failed (code=journal_exchange_failed)")
      }
      return nil
    }
  }

  /// Revisions preserve stable IDs and use explicit update semantics; a cleared
  /// generation can never be resurrected by a delayed partial or final response.
  @discardableResult
  func recordOrReviseConversationExchange(
    surface: AgentSurfaceReference,
    turns: [ExchangeTurn],
    origin: String,
    continuityKey: String,
    messageSource: String,
    ownerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    expectedGeneration: Int
  ) async -> [KernelJournalTurn]? {
    let writes = turns.map {
      $0.message.journalWrite(
        origin: origin, status: $0.status,
        continuityKey: continuityKey, messageSource: messageSource)
    }
    return await recordExchange(
      surface: surface, writes: writes, ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot, expectedGeneration: expectedGeneration, revise: true)
  }

  private func currentGeneration(client: AgentClient.Session, surface: AgentSurfaceReference, lease: OwnerLease)
    async throws -> Int
  {
    let page = try await listJournalTurns(
      client: client, surface: surface, ownerID: lease.ownerID, afterTurnSeq: 0, limit: 1)
    guard isCurrent(lease) else { throw BridgeError.authMissing }
    return page.conversationGeneration
  }

  private func persistExchange(
    client: AgentClient.Session, surface: AgentSurfaceReference, lease: OwnerLease,
    writes: [KernelJournalTurnWrite], expectedGeneration: Int?, revise: Bool
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    let generation: Int
    if let expectedGeneration {
      generation = expectedGeneration
    } else {
      generation = try await currentGeneration(client: client, surface: surface, lease: lease)
    }
    guard isCurrent(lease) else { throw BridgeError.authMissing }
    if revise {
      return try await client.recordOrReviseConversationExchange(
        surface: surface, ownerID: lease.ownerID,
        turns: writes, authorizationSnapshot: lease.authorizationSnapshot, expectedGeneration: generation)
    }
    return try await client.recordJournalExchange(
      surface: surface, ownerID: lease.ownerID,
      turns: writes, authorizationSnapshot: lease.authorizationSnapshot, expectedGeneration: generation)
  }

  private func scheduleCatalogTitleGeneration(
    host: ChatProvider,
    chatID: String,
    ownerID: String,
    userText: String,
    assistantText: String
  ) {
    Task { @MainActor [weak host] in
      await host?.catalogDidAcceptFirstCompletedExchange(
        chatID: chatID,
        ownerID: ownerID,
        userText: userText,
        assistantText: assistantText
      )
    }
  }

  func clear(
    surface: AgentSurfaceReference,
    ownerID: String? = nil,
    requiresModelReadiness: Bool = true,
    deleteBackend: Bool = true
  ) async -> Bool {
    guard let lease = captureOwnerLease(ownerID: ownerID), let host else { return false }
    let kernelReady =
      if !requiresModelReadiness {
        client != nil
      } else if let kernelReadyOperation {
        await kernelReadyOperation()
      } else {
        await host.ensureBridgeStartedForKernel()
      }
    guard kernelReady, isCurrent(lease), let client else { return false }
    do {
      let surfaceKey = surface.key
      let checkpointKey = conversationBySurface[surfaceKey].map {
        checkpointKeyFor(conversationId: $0, surface: surface)
      }
      var expectedGeneration = checkpointKey.flatMap { generationByConversation[$0] }
      if expectedGeneration.map({ $0 <= 0 }) ?? true {
        let page: AgentRuntimeProcess.JournalOperationResult
        if let journalListOperation {
          page = try await journalListOperation(client, surface, lease.ownerID, 0, 1)
        } else if requiresModelReadiness {
          page = try await client.listJournalTurns(
            surface: surface,
            ownerID: lease.ownerID,
            afterTurnSeq: 0,
            limit: 1
          )
        } else {
          page = try await client.listJournalTurnsForControl(
            surface: surface,
            ownerID: lease.ownerID,
            afterTurnSeq: 0,
            limit: 1
          )
        }
        guard isCurrent(lease),
          !page.conversationId.isEmpty,
          page.conversationGeneration > 0
        else { return false }
        let bootstrapCheckpointKey = checkpointKeyFor(
          conversationId: page.conversationId,
          surface: surface
        )
        conversationBySurface[surfaceKey] = page.conversationId
        generationByConversation[bootstrapCheckpointKey] = page.conversationGeneration
        expectedGeneration = page.conversationGeneration
      }
      guard isCurrent(lease), let expectedGeneration, expectedGeneration > 0 else { return false }
      if let journalClearOperation {
        _ = try await journalClearOperation(
          client,
          surface,
          lease.ownerID,
          expectedGeneration,
          deleteBackend
        )
      } else if requiresModelReadiness {
        _ = try await client.clearJournalTurns(
          surface: surface,
          ownerID: lease.ownerID,
          expectedGeneration: expectedGeneration,
          deleteBackend: deleteBackend
        )
      } else {
        _ = try await client.clearJournalTurnsForControl(
          surface: surface,
          ownerID: lease.ownerID,
          expectedGeneration: expectedGeneration,
          deleteBackend: deleteBackend
        )
      }
      guard isCurrent(lease) else { return false }
      // A refresh admitted before this clear may still be suspended in its
      // journal read. Advance the projection epoch before mutating local
      // checkpoints so that late page can neither restore the cleared rows nor
      // overwrite the new generation's checkpoint after this method returns.
      projectionEpoch &+= 1
      boundOwnerID = lease.ownerID
      refreshingSurfaceEpochs.removeAll()
      refreshRequestedSurfaceEpochs.removeAll()
      for key in highWaterByConversation.keys where key.hasSuffix("|\(surface.key)") {
        highWaterByConversation.removeValue(forKey: key)
        generationByConversation.removeValue(forKey: key)
      }
      conversationBySurface.removeValue(forKey: surfaceKey)
      host.resetJournalProjection(surface: surface)
      return true
    } catch {
      log("KernelTurnProjection: journal clear failed (code=journal_clear_failed)")
      return false
    }
  }

  func clearOwnerSurfaceState(chatId: String = "default") async -> Bool {
    await clear(
      surface: .mainChat(chatId: chatId),
      requiresModelReadiness: false,
      deleteBackend: false
    )
  }

  func fetchJournalTurnTail(
    surface: AgentSurfaceReference,
    limit: Int = 8
  ) async -> KernelAutomationTurnRange? {
    guard let lease = captureOwnerLease(), let host else { return nil }
    guard await host.ensureBridgeStartedForKernel(), isCurrent(lease), let client else { return nil }
    do {
      let page = try await client.listJournalTurnTail(
        surface: surface, ownerID: lease.ownerID, limit: limit,
        authorizationSnapshot: lease.authorizationSnapshot)
      guard isCurrent(lease) else { return nil }
      // Storage returns latest payloads in their original admission order.
      // Sorting by revision sequence would reorder an earlier revised turn.
      return KernelAutomationTurnRange(
        conversationId: page.conversationId, generation: page.conversationGeneration,
        turns: page.turns)
    } catch {
      log("KernelTurnProjection: journal tail fetch failed (code=journal_tail_failed)")
      return nil
    }
  }

  private func checkpointKeyFor(
    conversationId: String,
    surface: AgentSurfaceReference
  ) -> String {
    "\(conversationId)|\(surface.key)"
  }

  private func applyAcceptedExchange(
    _ result: AgentRuntimeProcess.JournalOperationResult,
    surface: AgentSurfaceReference,
    lease: OwnerLease
  ) {
    guard isCurrent(lease), let host else { return }
    let surfaceKey = surface.key
    conversationBySurface[surfaceKey] = result.conversationId
    let checkpointKey = checkpointKeyFor(
      conversationId: result.conversationId,
      surface: surface
    )
    if let generation = generationByConversation[checkpointKey],
      generation != result.conversationGeneration
    {
      highWaterByConversation[checkpointKey] = result.generationBaseTurnSeq
      generationByConversation[checkpointKey] = result.conversationGeneration
      guard isCurrent(lease) else { return }
      host.resetJournalProjection(surface: surface)
    } else if generationByConversation[checkpointKey] == nil {
      highWaterByConversation[checkpointKey] = result.generationBaseTurnSeq
      generationByConversation[checkpointKey] = result.conversationGeneration
    }

    if host.shouldProjectJournalSurface(surface) {
      for turn in result.turns.sorted(by: { $0.turnSeq < $1.turnSeq }) {
        guard isCurrent(lease) else { return }
        host.projectJournalTurn(turn)
      }
    }

    let checkpoint =
      highWaterByConversation[checkpointKey]
      ?? result.generationBaseTurnSeq
    let contiguous = KernelJournalReplay.contiguousTurns(
      from: result.turns,
      after: checkpoint
    )
    if let last = contiguous.last {
      highWaterByConversation[checkpointKey] = last.turnSeq
    }
  }

  private func listJournalTurns(
    client: AgentClient.Session,
    surface: AgentSurfaceReference,
    ownerID: String,
    afterTurnSeq: Int,
    limit: Int
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    if let journalListOperation {
      return try await journalListOperation(
        client,
        surface,
        ownerID,
        afterTurnSeq,
        limit
      )
    }
    return try await client.listJournalTurns(
      surface: surface,
      ownerID: ownerID,
      afterTurnSeq: afterTurnSeq,
      limit: limit
    )
  }

  private func captureOwnerLease(
    ownerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) -> OwnerLease? {
    guard let currentOwnerID = Self.normalizedOwnerID(ownerIDProvider()) else {
      return nil
    }
    if let ownerID {
      guard
        let requestedOwnerID = Self.normalizedOwnerID(ownerID),
        requestedOwnerID == currentOwnerID
      else { return nil }
    }
    if let authorizationSnapshot {
      guard authorizationSnapshot.ownerID == currentOwnerID,
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
      else { return nil }
    }
    if let boundOwnerID, boundOwnerID != currentOwnerID {
      invalidateOwnerState()
    }
    boundOwnerID = currentOwnerID
    return OwnerLease(
      ownerID: currentOwnerID,
      epoch: projectionEpoch,
      authorizationSnapshot: authorizationSnapshot)
  }

  private func isCurrent(_ lease: OwnerLease) -> Bool {
    projectionEpoch == lease.epoch
      && boundOwnerID == lease.ownerID
      && Self.normalizedOwnerID(ownerIDProvider()) == lease.ownerID
      && lease.authorizationSnapshot.map(RuntimeOwnerIdentity.isAuthorizationCurrent) != false
  }

  nonisolated private static func normalizedOwnerID(_ ownerID: String?) -> String? {
    guard let ownerID else { return nil }
    let normalized = ownerID.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  /// Reads one immutable 100-revision page at a time. If clear/reset advances
  /// the generation mid-read, restart from that generation's base rather than
  /// mixing two histories into the lifecycle match.
  private func journalRevisions(
    client: AgentClient.Session,
    surface: AgentSurfaceReference,
    lease: OwnerLease
  ) async throws -> [KernelJournalTurn] {
    var revisions: [KernelJournalTurn] = []
    var afterTurnSeq = 0
    var expectedGeneration: Int?
    var generationRestarts = 0
    while true {
      guard isCurrent(lease) else { throw CancellationError() }
      let page = try await listJournalTurns(
        client: client,
        surface: surface,
        ownerID: lease.ownerID,
        afterTurnSeq: afterTurnSeq,
        limit: 100
      )
      guard isCurrent(lease) else { throw CancellationError() }
      if let currentGeneration = expectedGeneration,
        currentGeneration != page.conversationGeneration
      {
        generationRestarts += 1
        guard generationRestarts <= 2 else {
          throw NSError(
            domain: "KernelTurnProjection",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "journal generation changed repeatedly"]
          )
        }
        revisions = []
        afterTurnSeq = page.generationBaseTurnSeq
        expectedGeneration = page.conversationGeneration
        continue
      }
      expectedGeneration = page.conversationGeneration
      revisions.append(contentsOf: page.turns)
      guard let lastTurnSeq = page.turns.map(\.turnSeq).max() else { break }
      afterTurnSeq = lastTurnSeq
      if afterTurnSeq >= page.highWaterTurnSeq { break }
    }
    return revisions
  }

  nonisolated static func stableTurnIDs(continuityKey: String) -> Set<String> {
    [
      stableTurnID(continuityKey: continuityKey, role: "user"),
      stableTurnID(continuityKey: continuityKey, role: "assistant"),
    ]
  }

  /// Canonical message identity for every projection of one logical journal turn.
  /// Optimistic UI rows must use this before SQLite/backend acknowledgement so
  /// reconciliation promotes them in place instead of replacing their identity.
  nonisolated static func stableTurnID(continuityKey: String, role: String) -> String {
    let digest = SHA256.hash(data: Data("\(continuityKey)\u{0}\(role)".utf8))
    return "turn_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
  }

}
