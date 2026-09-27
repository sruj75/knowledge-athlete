import Foundation

enum AIVoiceTurnOutcome: String, Encodable, Sendable {
  case completed, cancelled, failed, suppressed
}

/// Content is deliberately an allowlist. Screens, memories, profiles, tools and
/// model input bundles cannot enter this representation.
enum AIEvaluationObservation: Sendable {
  case terminal(
    sessionID: String, turnID: String, decisionID: String?, prompt: AIManagedPrompt,
    outcome: AIVoiceTurnOutcome, durationMs: Int, conversation: [SupervisorConversationInput])
  case decision(
    sessionID: String, decisionID: String, observationID: String, prompt: AIManagedPrompt,
    transcripts: [SupervisorTranscriptInput], conversation: [SupervisorConversationInput], note: String?)
  case chatTerminal(
    sessionID: String, turnID: String, requestID: String, outcome: AIVoiceTurnOutcome,
    durationMs: Int, conversation: [SupervisorConversationInput])
  case score(sessionID: String, turnID: String, decisionID: String?, value: Int, requestID: String? = nil)

  func encoded(sharing: Bool) throws -> Data {
    try JSONEncoder().encode(Export(observation: self, sharing: sharing))
  }

  private struct PromptReference: Encodable {
    let name: String
    let version: String
    let source: String
    init(_ prompt: AIManagedPrompt) {
      name = prompt.name
      version = prompt.version
      source = prompt.source
    }
  }

  private struct Export: Encodable {
    let observation: AIEvaluationObservation
    let sharing: Bool
    enum CodingKeys: String, CodingKey {
      case kind, prompt, outcome, conversation, transcripts, note, value
      case sessionID = "session_id"
      case turnID = "turn_id"
      case decisionID = "decision_id"
      case requestID = "request_id"
      case observationID = "observation_id"
      case durationMs = "duration_ms"
      case evaluationSharing = "evaluation_sharing"
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(sharing, forKey: .evaluationSharing)
      switch observation {
      case .terminal(
        let sessionID, let turnID, let decisionID, let prompt, let outcome, let durationMs, let conversation):
        try container.encode("terminal_turn", forKey: .kind)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeIfPresent(decisionID, forKey: .decisionID)
        try container.encode(PromptReference(prompt), forKey: .prompt)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(max(0, min(durationMs, 3_600_000)), forKey: .durationMs)
        if sharing { try container.encode(bounded(conversation), forKey: .conversation) }
      case .decision(
        let sessionID, let decisionID, let observationID, let prompt, let transcripts, let conversation, let note):
        try container.encode("supervisor_decision", forKey: .kind)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(decisionID, forKey: .decisionID)
        try container.encode(observationID, forKey: .observationID)
        try container.encode(PromptReference(prompt), forKey: .prompt)
        if sharing {
          try container.encode(
            transcripts.suffix(32).map {
              SupervisorTranscriptInput(id: $0.id, text: String($0.text.prefix(2_000)), source: $0.source)
            }, forKey: .transcripts)
          try container.encode(bounded(conversation), forKey: .conversation)
          try container.encodeIfPresent(note.map { String($0.prefix(2_000)) }, forKey: .note)
        }
      case .chatTerminal(let sessionID, let turnID, let requestID, let outcome, let durationMs, let conversation):
        try container.encode("chat_terminal", forKey: .kind)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(max(0, min(durationMs, 3_600_000)), forKey: .durationMs)
        if sharing { try container.encode(bounded(conversation), forKey: .conversation) }
      case .score(let sessionID, let turnID, let decisionID, let value, let requestID):
        try container.encode("score", forKey: .kind)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeIfPresent(decisionID, forKey: .decisionID)
        try container.encode(min(1, max(0, value)), forKey: .value)
        try container.encodeIfPresent(requestID, forKey: .requestID)
      }
    }

    private func bounded(_ conversation: [SupervisorConversationInput]) -> [SupervisorConversationInput] {
      conversation.suffix(16).map {
        SupervisorConversationInput(
          turnID: $0.turnID, role: $0.role, text: String($0.text.prefix(2_000)), outcome: $0.outcome)
      }
    }
  }
}

/// A queued content export belongs to one uninterrupted opt-in period. Turning
/// sharing back on never releases content queued before revocation.
struct AIEvaluationConsent: Sendable {
  struct Ticket: Equatable, Sendable {
    let sessionID: String
    let epoch: UInt64
    let sharing: Bool
  }
  private(set) var ticket: Ticket

  init(sessionID: String) { ticket = Ticket(sessionID: sessionID, epoch: 0, sharing: false) }

  mutating func update(sessionID: String, sharing: Bool) {
    guard ticket.sessionID != sessionID || ticket.sharing != sharing else { return }
    ticket = Ticket(sessionID: sessionID, epoch: ticket.epoch &+ 1, sharing: sharing)
  }

  func permitsContent(_ captured: Ticket) -> Bool { captured.sharing && captured == ticket }
}
