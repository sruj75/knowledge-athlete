import Foundation

/// Metadata-only observation, never conversation or journal authority. PCM byte
/// counts include silence; they establish input delivery, not human speech.
struct ConversationDiagnosticSnapshot: Codable, Equatable, Sendable {
  enum Outcome: String, Codable, Sendable {
    case completed, interrupted, failed
    case notSpoken = "not_spoken"
  }
  struct PromptReference: Codable, Equatable, Sendable {
    let name: String
    let version: String
    let source: String
    let sha256: String
    init(name: String, version: String, source: String, sha256: String) {
      self.name = String(name.prefix(128))
      self.version = String(version.prefix(128))
      self.source = String(source.prefix(32))
      self.sha256 = String(sha256.prefix(64))
    }
  }
  struct Delivery: Codable, Equatable, Sendable {
    let turnID: String
    let outcome: Outcome
    let renderObserved: Bool
    /// Observed a provider-sealed output queue drain, not human hearing or
    /// final journal acknowledgement. Completion requires `outcome == .completed`.
    let playbackDrainObserved: Bool
  }
  var state = "closed"
  var route = "none"
  var logicalConversationID: String?
  var journalID: String?
  /// Latest connection identity is retained after close for correlation only.
  var connectionID: String?
  var promptReference: PromptReference?
  var microphoneAvailable = false
  var userSpeaking = false
  var listening = false
  var rendering = false
  var acceptedProcessedPCMBytes = 0
  var acceptedProcessedPCMChunks = 0
  var currentTurnID: String?
  var completedCount = 0
  var interruptedCount = 0
  var failedCount = 0
  var notSpokenCount = 0
  var lastDelivery: Delivery?
}

/// Owner includes the authenticated-session epoch, so the same account signing
/// back in cannot inspect the previous session. No owner is ever serialized.
struct ConversationDiagnosticLedger<Owner: Equatable & Sendable> {
  private var owner: Owner?
  private var activeGeneration: UInt64?
  private var value = ConversationDiagnosticSnapshot()

  mutating func begin(owner: Owner, generation: UInt64, conversationID: String) {
    self.owner = owner
    activeGeneration = generation
    value = ConversationDiagnosticSnapshot(
      state: "connecting", route: "live", logicalConversationID: String(conversationID.prefix(128)))
  }

  mutating func updateMetadata(
    logicalID: String, journalID: String?, connectionID: String?,
    prompt: ConversationDiagnosticSnapshot.PromptReference?, owner: Owner?, generation: UInt64
  ) {
    guard admits(owner: owner, generation: generation) else { return }
    value.logicalConversationID = String(logicalID.prefix(128))
    value.journalID = journalID.map { String($0.prefix(128)) }
    if let connectionID { value.connectionID = String(connectionID.prefix(128)) }
    value.promptReference = prompt
  }

  mutating func updateRuntime(
    state: String, route: String, microphoneAvailable: Bool, userSpeaking: Bool,
    listening: Bool, rendering: Bool, owner: Owner?, generation: UInt64
  ) {
    guard admits(owner: owner, generation: generation) else { return }
    value.state = String(state.prefix(32))
    value.route = String(route.prefix(32))
    value.microphoneAvailable = microphoneAvailable
    value.userSpeaking = userSpeaking
    value.listening = listening
    value.rendering = rendering
  }

  mutating func recordProcessedPCM(byteCount: Int, owner: Owner?, generation: UInt64) {
    guard admits(owner: owner, generation: generation), byteCount > 0 else { return }
    value.acceptedProcessedPCMBytes = Self.add(value.acceptedProcessedPCMBytes, byteCount, limit: 1_000_000_000_000)
    value.acceptedProcessedPCMChunks = Self.add(value.acceptedProcessedPCMChunks)
  }

  mutating func beginTurn(id: String, owner: Owner?, generation: UInt64) {
    guard admits(owner: owner, generation: generation) else { return }
    value.currentTurnID = String(id.prefix(128))
  }

  mutating func recordDelivery(
    turnID: String, outcome: ConversationDiagnosticSnapshot.Outcome,
    renderObserved: Bool, playbackDrainObserved: Bool, owner: Owner?, generation: UInt64
  ) {
    guard admits(owner: owner, generation: generation), value.currentTurnID == turnID else { return }
    value.currentTurnID = nil
    switch outcome {
    case .completed: value.completedCount = Self.add(value.completedCount)
    case .interrupted: value.interruptedCount = Self.add(value.interruptedCount)
    case .failed: value.failedCount = Self.add(value.failedCount)
    case .notSpoken: value.notSpokenCount = Self.add(value.notSpokenCount)
    }
    value.lastDelivery = .init(
      turnID: String(turnID.prefix(128)), outcome: outcome,
      renderObserved: renderObserved, playbackDrainObserved: playbackDrainObserved)
  }

  mutating func close(owner: Owner?, generation: UInt64) {
    guard admits(owner: owner, generation: generation) else { return }
    activeGeneration = nil
    value.state = "closed"
    value.currentTurnID = nil
    value.microphoneAvailable = false
    value.userSpeaking = false
    value.listening = false
    value.rendering = false
  }

  mutating func snapshot(owner: Owner?) -> ConversationDiagnosticSnapshot {
    guard let owner, self.owner == owner else {
      reset()
      return value
    }
    return value
  }

  mutating func reset() {
    owner = nil
    activeGeneration = nil
    value = ConversationDiagnosticSnapshot()
  }

  private static func add(_ value: Int, _ amount: Int = 1, limit: Int = 1_000_000_000) -> Int {
    min(limit, value + min(limit, max(0, amount)))
  }

  private func admits(owner: Owner?, generation: UInt64) -> Bool {
    owner != nil && self.owner == owner && activeGeneration == generation
  }
}
