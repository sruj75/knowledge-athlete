import Combine
import Foundation

/// Session-scoped receipts connect canonical assistant messages to A's prompt
/// and B's decision. No private guidance is retained in message metadata.
@MainActor
final class AIEvaluationReporter: ObservableObject {
  static let shared = AIEvaluationReporter()

  struct Receipt {
    let sessionID: String
    let turnID: String
    let decisionID: String?
    let authorization: RuntimeOwnerAuthorizationSnapshot
    var score: Int?
    var requestID: String? = nil
  }
  private struct Admission {
    let sessionID: String
    let authorization: RuntimeOwnerAuthorizationSnapshot
    let startedAt: TimeInterval
    let consent: AIEvaluationConsent.Ticket
  }
  @Published private(set) var receipts: [String: Receipt] = [:]
  private var admissions: [String: Admission] = [:]
  private var decisionTickets: [String: AIEvaluationConsent.Ticket] = [:]
  private var pending: [UUID: Task<Void, Never>] = [:]
  private var subscriptions: Set<AnyCancellable> = []
  private var consent = AIEvaluationConsent(sessionID: "uninitialized")

  func captureTurnStart(
    turnID: String, authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) {
    startObserving()
    guard admissions[turnID] == nil,
      let authorization = authorizationSnapshot ?? RuntimeOwnerIdentity.captureAuthorizationSnapshot(),
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
    else { return }
    admissions[turnID] = Admission(
      sessionID: SupervisorService.shared.sessionID, authorization: authorization,
      startedAt: ProcessInfo.processInfo.systemUptime, consent: consent.ticket)
  }

  func discardTurnAdmission(turnID: String) {
    admissions.removeValue(forKey: turnID)
  }

  /// Called only after the canonical Chat journal accepts the completed turn.
  /// The backend resolves Chat's real prompt receipt from this managed request.
  func recordChatTerminal(
    turnID: String, requestID: String?, authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    userText: String, assistantText: String
  ) {
    guard let admission = admissions.removeValue(forKey: "chat:\(turnID)"), let requestID,
      admission.authorization == authorizationSnapshot,
      RuntimeOwnerIdentity.isAuthorizationCurrent(admission.authorization),
      admission.sessionID == SupervisorService.shared.sessionID
    else { return }
    receipts[turnID] = Receipt(
      sessionID: admission.sessionID, turnID: turnID, decisionID: nil,
      authorization: admission.authorization, requestID: requestID)
    if receipts.count > 256, let key = receipts.keys.first(where: { $0 != turnID }) {
      receipts.removeValue(forKey: key)
    }
    let conversation: [SupervisorConversationInput] =
      consent.permitsContent(admission.consent)
      ? [
        .init(turnID: turnID, role: "user", text: String(userText.prefix(2_000)), outcome: "completed"),
        .init(turnID: turnID, role: "assistant", text: String(assistantText.prefix(2_000)), outcome: "completed"),
      ] : []
    enqueue(
      .chatTerminal(
        sessionID: admission.sessionID, turnID: turnID, requestID: requestID, outcome: .completed,
        durationMs: Int(max(0, ProcessInfo.processInfo.systemUptime - admission.startedAt) * 1_000),
        conversation: conversation),
      authorization: admission.authorization, ticket: admission.consent)
  }

  func captureDecisionStart(observationID: String) {
    startObserving()
    // Only one evaluation is admitted, so a failed request leaves at most one receipt.
    decisionTickets = [observationID: consent.ticket]
  }

  func recordVoiceTerminal(
    turnID: String, continuityKey: String, decisionID: String?, prompt: AIManagedPrompt?,
    outcome: AIVoiceTurnOutcome, conversation: [SupervisorConversationInput]
  ) {
    guard let admission = admissions.removeValue(forKey: turnID),
      RuntimeOwnerIdentity.isAuthorizationCurrent(admission.authorization),
      admission.sessionID == SupervisorService.shared.sessionID,
      let prompt
    else { return }
    receipts[continuityKey] = Receipt(
      sessionID: admission.sessionID, turnID: turnID, decisionID: decisionID,
      authorization: admission.authorization)
    if receipts.count > 256, let key = receipts.keys.first(where: { $0 != continuityKey }) {
      receipts.removeValue(forKey: key)
    }
    enqueue(
      .terminal(
        sessionID: admission.sessionID, turnID: turnID, decisionID: decisionID, prompt: prompt,
        outcome: outcome,
        durationMs: Int(max(0, ProcessInfo.processInfo.systemUptime - admission.startedAt) * 1_000),
        conversation: conversation),
      authorization: admission.authorization, ticket: admission.consent)
  }

  func recordDecision(
    request: SupervisorEvaluationRequest, response: SupervisorEvaluationResponse,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    startObserving()
    guard request.sessionID == SupervisorService.shared.sessionID,
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    else { return }
    // A request started before opt-in is never retrospectively shared.
    guard let ticket = decisionTickets.removeValue(forKey: request.observationID) else { return }
    enqueue(
      .decision(
        sessionID: request.sessionID, decisionID: response.decisionID, observationID: request.observationID,
        prompt: response.prompt, transcripts: request.transcripts, conversation: request.conversation,
        note: response.note),
      authorization: authorizationSnapshot, ticket: ticket)
  }

  func score(continuityKey: String, helpful: Bool) {
    guard var receipt = receipts[continuityKey],
      receipt.sessionID == SupervisorService.shared.sessionID,
      RuntimeOwnerIdentity.isAuthorizationCurrent(receipt.authorization)
    else { return }
    receipt.score = helpful ? 1 : 0
    receipts[continuityKey] = receipt
    enqueue(
      .score(
        sessionID: receipt.sessionID, turnID: receipt.turnID, decisionID: receipt.decisionID,
        value: helpful ? 1 : 0, requestID: receipt.requestID),
      authorization: receipt.authorization, ticket: consent.ticket)
  }

  private func startObserving() {
    guard subscriptions.isEmpty else { return }
    let service = SupervisorService.shared
    consent.update(sessionID: service.sessionID, sharing: service.evaluationSharing)
    service.$evaluationSharing.dropFirst().sink { [weak self] sharing in
      MainActor.assumeIsolated {
        self?.updateConsent(sessionID: service.sessionID, sharing: sharing)
      }
    }.store(in: &subscriptions)
    service.$sessionID.dropFirst().sink { [weak self] sessionID in
      MainActor.assumeIsolated {
        self?.updateConsent(sessionID: sessionID, sharing: false)
        self?.receipts.removeAll()
        self?.admissions.removeAll()
        self?.decisionTickets.removeAll()
      }
    }.store(in: &subscriptions)
  }

  private func updateConsent(sessionID: String, sharing: Bool) {
    consent.update(sessionID: sessionID, sharing: sharing)
    for task in pending.values { task.cancel() }
    pending.removeAll()
  }

  private func enqueue(
    _ observation: AIEvaluationObservation, authorization: RuntimeOwnerAuthorizationSnapshot,
    ticket: AIEvaluationConsent.Ticket
  ) {
    // An outage cannot accumulate unbounded text or delay the voice path.
    guard pending.count < 32 else { return }
    let id = UUID()
    pending[id] = Task { @MainActor [weak self] in
      defer { self?.pending.removeValue(forKey: id) }
      do {
        try Task.checkCancellation()
        try await APIClient.shared.submitAIObservation(
          observation, authorizationSnapshot: authorization,
          permitsContent: { [weak self] in
            guard let self else { return false }
            return self.consent.permitsContent(ticket)
              && RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
          })
      } catch {
        // No content-bearing error, retries, user notification or sign-out.
      }
    }
  }
}
