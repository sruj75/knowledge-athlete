import Foundation

struct ConversationJournalContext: Sendable {
  let authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  let surface: AgentSurfaceReference
  let conversationID: String
  let generation: Int
  let history: [ConversationHistoryMessage]
}

struct ConversationPromptScope: Equatable, Sendable {
  let authorization: RuntimeOwnerAuthorizationSnapshot
  let journalID: String
  let generation: Int
}

enum ConversationJournalError: Error {
  case unavailable
  case writeRejected
}

extension ChatProvider {
  /// Snapshot the selected durable chat before opening a logical conversation.
  /// A later selection change never redirects an in-flight utterance's write.
  func snapshotConversationJournal(surface requestedSurface: AgentSurfaceReference? = nil) async throws
    -> ConversationJournalContext
  {
    guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw AuthError.userChangedDuringRequest
    }
    let surface = requestedSurface ?? realtimeVoiceSurfaceReference()
    guard let tail = await kernelTurnProjection.fetchJournalTurnTail(surface: surface, limit: 100) else {
      throw ConversationJournalError.unavailable
    }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorization) else {
      throw AuthError.userChangedDuringRequest
    }
    let history = Self.conversationHistory(from: tail.turns)
    return ConversationJournalContext(
      authorizationSnapshot: authorization, surface: surface,
      conversationID: tail.conversationId, generation: tail.generation, history: history)
  }

  /// The storage tail is already in original admission order, with the latest
  /// revision for each identity. Timestamps and hashed IDs cannot order ties.
  nonisolated static func conversationHistory(from turns: [KernelJournalTurn]) -> [ConversationHistoryMessage] {
    turns.filter { ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty }
      .suffix(64)
      .map { ConversationHistoryMessage(role: $0.role, text: String($0.content.suffix(4_000))) }
  }

  func pinnedConversation(context: ConversationJournalContext) async throws -> ConversationPromptBinding {
    try await conversationPromptBindings.resolve(
      key: ConversationPromptScope(
        authorization: context.authorizationSnapshot, journalID: context.conversationID,
        generation: context.generation))
  }

  func endPinnedConversation(id: String) { conversationPromptBindings.end(id: id) }

  func endPinnedConversation(context: ConversationJournalContext) {
    conversationPromptBindings.end(
      key: ConversationPromptScope(
        authorization: context.authorizationSnapshot, journalID: context.conversationID,
        generation: context.generation))
  }

  func conversationContextText(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> String {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return "" }
    let memories =
      (try? await MemoryStorage.shared.list(
        limit: 20, authorizationSnapshot: authorizationSnapshot)) ?? []
    let profile = await AIUserProfileService.shared.getLatestProfile(authorizationSnapshot: authorizationSnapshot)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return "" }
    let memoryText = memories.map { String($0.content.prefix(500)) }.joined(separator: "\n")
    let profileText = String((profile?.profileText ?? "").prefix(5_000))
    return String("Saved memories:\n\(memoryText)\nSaved profile:\n\(profileText)".prefix(16_000))
  }

  func recordConversationExchange(
    context: ConversationJournalContext,
    turnID: String,
    userText: String,
    assistantText: String,
    origin: String,
    delivery: ConversationDeliveryOutcome,
    isFinal: Bool = true,
    createdAt: Date = Date(),
    attachments: [ChatAttachment] = []
  ) async throws {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(context.authorizationSnapshot) else {
      throw AuthError.userChangedDuringRequest
    }
    var turns: [KernelTurnProjection.ExchangeTurn] = []
    if !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let message = ChatMessage(
        id: KernelTurnProjection.stableTurnID(continuityKey: turnID, role: "user"),
        clientTurnId: turnID, text: userText, createdAt: createdAt, sender: .user,
        attachments: attachments)
      turns.append(.init(message: message, status: isFinal ? .completed : .streaming))
    }
    do {
      let message = ChatMessage(
        id: KernelTurnProjection.stableTurnID(continuityKey: turnID, role: "assistant"),
        clientTurnId: turnID, text: assistantText,
        createdAt: createdAt.addingTimeInterval(0.001), sender: .ai, isStreaming: !isFinal,
        voiceDeliveryOutcome: isFinal ? (AIVoiceTurnOutcome(rawValue: delivery.rawValue) ?? .suppressed) : nil)
      turns.append(.init(message: message, status: isFinal ? .completed : .streaming))
    }
    guard !turns.isEmpty else { return }
    let accepted = await kernelTurnProjection.recordOrReviseConversationExchange(
      surface: context.surface, turns: turns, origin: "realtime_voice", continuityKey: turnID,
      messageSource: origin, ownerID: context.authorizationSnapshot.ownerID,
      authorizationSnapshot: context.authorizationSnapshot, expectedGeneration: context.generation)
    guard accepted != nil else { throw ConversationJournalError.writeRejected }
  }
}
