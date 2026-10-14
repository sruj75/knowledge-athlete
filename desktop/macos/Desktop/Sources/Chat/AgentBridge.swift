import Foundation

struct AgentSurfaceSession: Equatable, Sendable {
  let created: Bool
  let conversationId: String
  let sessionId: String
}

/// Owner-bound access to the single retained catalog/journal database.
actor AgentBridge {
  private let runtime: AgentRuntimeProcess
  init(runtime: AgentRuntimeProcess = .shared) { self.runtime = runtime }
  var isAlive: Bool { get async { await runtime.isAlive } }
  func start() async throws { try await runtime.start(authorization: authorization()) }
  func restart() async throws {
    await runtime.stop()
    try await start()
  }
  func prepareForCrashRecovery() async { await runtime.stop() }
  func stop() async { await runtime.stop() }
  func stopAndWaitForExit() async { await runtime.stop() }
  func setJournalTurnChangedHandler(_ handler: @escaping AgentRuntimeProcess.JournalTurnChangedHandler) async {
    await runtime.setJournalTurnChangedHandler(handler)
  }
  private func authorization(_ supplied: RuntimeOwnerAuthorizationSnapshot? = nil, ownerID: String? = nil) throws
    -> RuntimeOwnerAuthorizationSnapshot
  {
    guard let value = supplied ?? RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID),
      RuntimeOwnerIdentity.isAuthorizationCurrent(value), ownerID == nil || ownerID == value.ownerID
    else { throw BridgeError.authMissing }
    return value
  }
  private func send(
    _ type: String, surface: AgentSurfaceReference? = nil, fields: [String: Any] = [:], ownerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> [String: Any] {
    let lease = try authorization(authorizationSnapshot, ownerID: ownerID)
    var payload = fields
    payload["type"] = type
    if let surface {
      payload["surfaceKind"] = surface.surfaceKind
      payload["externalRefKind"] = surface.externalRefKind
      payload["externalRefId"] = surface.externalRefId
    }
    let response = try await runtime.request(RuntimeJSONPayloadBox(payload), authorization: lease)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(lease) else { throw BridgeError.authMissing }
    return response.value
  }
  func resolveSurfaceSession(_ surface: AgentSurfaceReference, title: String? = nil) async throws -> AgentSurfaceSession
  {
    let value = try await send("resolve_surface_session", surface: surface)
    guard let conversation = value["conversationId"] as? String, let session = value["sessionId"] as? String else {
      throw BridgeError.encodingError
    }
    return AgentSurfaceSession(
      created: value["created"] as? Bool ?? false, conversationId: conversation, sessionId: session)
  }
  func listChatCatalog(authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil) async throws
    -> LocalChatCatalogSnapshot
  {
    let value = try await send("chat_catalog_list", authorizationSnapshot: authorizationSnapshot)
    return LocalChatCatalogSnapshot(
      chats: (value["chats"] as? [[String: Any]] ?? []).compactMap(LocalChatSummary.init(dictionary:)),
      retainedAttachmentURIs: Set(value["retainedAttachmentUris"] as? [String] ?? []))
  }
  func createChatCatalog(
    chatID: String, title: String? = nil, authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> LocalChatSummary {
    var fields: [String: Any] = ["chatId": chatID]
    if let title { fields["title"] = title }
    let value = try await send("chat_catalog_create", fields: fields, authorizationSnapshot: authorizationSnapshot)
    guard let row = value["chat"] as? [String: Any], let chat = LocalChatSummary(dictionary: row) else {
      throw BridgeError.encodingError
    }
    return chat
  }
  func updateChatCatalog(
    chatID: String, title: String? = nil, titleOrigin: LocalChatTitleOrigin? = nil,
    expectedTitleOrigin: LocalChatTitleOrigin? = nil, starred: Bool? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> LocalChatSummary {
    var fields: [String: Any] = ["chatId": chatID]
    if let title { fields["title"] = title }
    if let titleOrigin { fields["titleOrigin"] = titleOrigin.rawValue }
    if let expectedTitleOrigin { fields["expectedTitleOrigin"] = expectedTitleOrigin.rawValue }
    if let starred { fields["starred"] = starred }
    let value = try await send("chat_catalog_update", fields: fields, authorizationSnapshot: authorizationSnapshot)
    guard let row = value["chat"] as? [String: Any], let chat = LocalChatSummary(dictionary: row) else {
      throw BridgeError.encodingError
    }
    return chat
  }
  func deleteChatCatalog(chatID: String, authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil) async throws
    -> Set<String>
  {
    let value = try await send(
      "chat_catalog_delete", fields: ["chatId": chatID], authorizationSnapshot: authorizationSnapshot)
    return Set(value["retainedAttachmentUris"] as? [String] ?? [])
  }
  func listJournalTurns(
    surface: AgentSurfaceReference, ownerID: String? = nil, afterTurnSeq: Int = 0, limit: Int = 100,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    let value = try await send(
      "journal_list_turns", surface: surface, fields: ["afterTurnSeq": afterTurnSeq, "limit": limit], ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot)
    return try Self.journalResult(value, surface: surface)
  }
  func listJournalTurnTail(
    surface: AgentSurfaceReference, ownerID: String? = nil, limit: Int = 8,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    let value = try await send(
      "journal_tail_turns", surface: surface, fields: ["limit": max(1, min(limit, 100))], ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot)
    return try Self.journalResult(value, surface: surface)
  }
  func listJournalTurnsForControl(
    surface: AgentSurfaceReference, ownerID: String? = nil, afterTurnSeq: Int = 0, limit: Int = 100
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    try await listJournalTurns(surface: surface, ownerID: ownerID, afterTurnSeq: afterTurnSeq, limit: limit)
  }
  func recordJournalExchange(
    surface: AgentSurfaceReference, ownerID: String, turns: [KernelJournalTurnWrite],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil, expectedGeneration: Int
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    try await writeExchange(
      "journal_record_exchange", surface: surface, ownerID: ownerID, turns: turns,
      authorizationSnapshot: authorizationSnapshot, expectedGeneration: expectedGeneration)
  }
  func recordOrReviseConversationExchange(
    surface: AgentSurfaceReference, ownerID: String, turns: [KernelJournalTurnWrite],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil, expectedGeneration: Int
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    try await writeExchange(
      "journal_revise_exchange", surface: surface, ownerID: ownerID, turns: turns,
      authorizationSnapshot: authorizationSnapshot, expectedGeneration: expectedGeneration)
  }
  private func writeExchange(
    _ type: String, surface: AgentSurfaceReference, ownerID: String, turns: [KernelJournalTurnWrite],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?, expectedGeneration: Int
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    let value = try await send(
      type, surface: surface, fields: ["turns": turns.map(\.dictionary), "expectedGeneration": expectedGeneration],
      ownerID: ownerID, authorizationSnapshot: authorizationSnapshot)
    return try Self.journalResult(value, surface: surface)
  }
  func recordJournalTurn(
    surface: AgentSurfaceReference, ownerID: String? = nil, turn: KernelJournalTurnWrite, expectedGeneration: Int
  ) async throws -> KernelJournalTurn {
    let lease = try authorization(ownerID: ownerID)
    let result = try await recordJournalExchange(
      surface: surface, ownerID: lease.ownerID, turns: [turn], authorizationSnapshot: lease,
      expectedGeneration: expectedGeneration)
    guard let turn = result.turns.first else { throw BridgeError.encodingError }
    return turn
  }
  func updateJournalTurnWithReceipt(
    surface: AgentSurfaceReference, ownerID: String? = nil, update: KernelJournalTurnUpdate, expectedGeneration: Int
  ) async throws -> AgentRuntimeProcess.JournalOperationResult {
    let value = try await send(
      "journal_update_turn", surface: surface,
      fields: ["update": update.dictionary, "expectedGeneration": expectedGeneration], ownerID: ownerID)
    return try Self.journalResult(value, surface: surface)
  }
  func updateJournalTurn(
    surface: AgentSurfaceReference, ownerID: String? = nil, update: KernelJournalTurnUpdate, expectedGeneration: Int
  ) async throws -> KernelJournalTurn {
    let result = try await updateJournalTurnWithReceipt(
      surface: surface, ownerID: ownerID, update: update, expectedGeneration: expectedGeneration)
    guard let turn = result.turn else { throw BridgeError.encodingError }
    return turn
  }
  func repairJournalTurns(surface: AgentSurfaceReference, ownerID: String, turnIDs: [String], expectedGeneration: Int)
    async throws -> [KernelJournalTurn]
  {
    let value = try await send(
      "journal_repair_turns", surface: surface, fields: ["turnIds": turnIDs, "expectedGeneration": expectedGeneration],
      ownerID: ownerID)
    return try Self.journalResult(value, surface: surface).turns
  }
  func clearJournalTurns(
    surface: AgentSurfaceReference, ownerID: String? = nil, expectedGeneration: Int, deleteBackend: Bool = false
  ) async throws -> Int {
    let value = try await send(
      "journal_clear_turns", surface: surface, fields: ["expectedGeneration": expectedGeneration], ownerID: ownerID)
    return try Self.journalResult(value, surface: surface).clearedCount
  }
  func clearJournalTurnsForControl(
    surface: AgentSurfaceReference, ownerID: String? = nil, expectedGeneration: Int, deleteBackend: Bool = false
  ) async throws -> Int {
    try await clearJournalTurns(surface: surface, ownerID: ownerID, expectedGeneration: expectedGeneration)
  }
  nonisolated static func journalResult(_ value: [String: Any], surface: AgentSurfaceReference) throws
    -> AgentRuntimeProcess.JournalOperationResult
  {
    guard let conversation = value["conversationId"] as? String,
      let generation = value["conversationGeneration"] as? Int, generation > 0,
      let highWater = value["highWaterTurnSeq"] as? Int, let base = value["generationBaseTurnSeq"] as? Int
    else { throw BridgeError.encodingError }
    func decode(_ row: [String: Any]) -> KernelJournalTurn? {
      KernelJournalTurn(
        dictionary: row, surfaceFallback: surface, conversationGenerationFallback: generation,
        generationBaseTurnSeqFallback: base)
    }
    let rows = value["turns"] as? [[String: Any]] ?? []
    let turns = rows.compactMap(decode)
    guard turns.count == rows.count else { throw BridgeError.encodingError }
    let exchange = value["firstCompletedRealExchange"] as? [String: Any]
    let first: AgentRuntimeProcess.JournalFirstCompletedRealExchange?
    if let exchange, let key = exchange["continuityKey"] as? String, let user = exchange["userText"] as? String,
      let assistant = exchange["assistantText"] as? String
    {
      first = .init(continuityKey: key, userText: user, assistantText: assistant)
    } else {
      first = nil
    }
    return .init(
      operation: value["operation"] as? String ?? "", conversationId: conversation,
      turn: (value["turn"] as? [String: Any]).flatMap(decode), turns: turns,
      clearedCount: value["clearedCount"] as? Int ?? 0, highWaterTurnSeq: highWater, conversationGeneration: generation,
      generationBaseTurnSeq: base, firstCompletedRealPair: value["firstCompletedRealPair"] as? Bool ?? false,
      firstCompletedRealExchange: first)
  }
}

enum BridgeError: LocalizedError {
  case nodeNotFound, bridgeScriptNotFound, notRunning, encodingError, timeout, processExited, stopped, authMissing
  case agentError(String)
  var isSessionAuthenticationFailure: Bool {
    if case .authMissing = self { return true }
    return false
  }
  var errorDescription: String? {
    switch self {
    case .nodeNotFound: return "Conversation storage requires the bundled Node runtime."
    case .bridgeScriptNotFound: return "Conversation storage is missing from this app."
    case .notRunning, .processExited: return "Conversation storage stopped unexpectedly."
    case .encodingError: return "Conversation storage returned an invalid response."
    case .timeout: return "Conversation storage did not respond in time."
    case .stopped: return "Conversation storage was stopped."
    case .authMissing: return "Please sign in to access your conversations."
    case .agentError(let message): return message
    }
  }
}
