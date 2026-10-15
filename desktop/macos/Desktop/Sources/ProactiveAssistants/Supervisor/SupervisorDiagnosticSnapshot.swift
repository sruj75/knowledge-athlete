import Foundation

/// Constant-size aggregates; no request content or unbounded event history.
struct SupervisorDiagnosticTiming: Encodable, Equatable, Sendable {
  private(set) var count = 0
  private(set) var totalMs = 0
  private(set) var minimumMs: Int?
  private(set) var maximumMs: Int?
  private(set) var lastMs: Int?

  mutating func record(seconds: TimeInterval) {
    let milliseconds = Int(min(86_400_000, max(0, seconds * 1_000)))
    count += 1
    totalMs += milliseconds
    minimumMs = min(minimumMs ?? milliseconds, milliseconds)
    maximumMs = max(maximumMs ?? milliseconds, milliseconds)
    lastMs = milliseconds
  }
}

struct SupervisorObservationMetrics: Encodable, Equatable, Sendable {
  struct Receipt: Equatable, Sendable {
    fileprivate let id = UUID()
    fileprivate let queuedAt: TimeInterval
    fileprivate let admittedAt: TimeInterval
  }

  enum Work: String, Encodable, Sendable { case none, preparing, evaluating }
  enum Outcome { case returned, failed, cancelled, discardedBeforeEvaluation }
  enum Skip: String, Sendable {
    case inFlight = "in_flight"
    case budget, disabled, suspended
    case noPending = "no_pending"
    case notDue = "not_due"
    case retryPause = "retry_pause"
    case noOwner = "no_owner"
    case invalidatedObservation = "invalidated_observation"
    case excludedInput = "excluded_input"
    case rejectedResponse = "rejected_response"
  }

  private(set) var admitted = 0
  var budgetDeferrals = 0
  var replacedPending = 0
  private(set) var evaluatorStarts = 0
  private(set) var evaluatorReturns = 0
  private(set) var evaluatorFailures = 0
  private(set) var evaluatorCancellations = 0
  private(set) var discardedBeforeEvaluation = 0
  private(set) var skipped: [String: Int] = [:]
  private(set) var queue = SupervisorDiagnosticTiming()
  private(set) var evaluatorRoundTrip = SupervisorDiagnosticTiming()
  private(set) var admissionToCompletion = SupervisorDiagnosticTiming()
  private(set) var observationToCompletion = SupervisorDiagnosticTiming()
  private var active: Receipt?
  private var evaluatorStartedAt: TimeInterval?

  enum CodingKeys: String, CodingKey {
    case admitted, budgetDeferrals, replacedPending, evaluatorStarts, evaluatorReturns
    case evaluatorFailures, evaluatorCancellations, discardedBeforeEvaluation, skipped
    case queue, evaluatorRoundTrip, admissionToCompletion, observationToCompletion
  }

  var currentWork: Work { active == nil ? .none : evaluatorStartedAt == nil ? .preparing : .evaluating }

  mutating func skip(_ reason: Skip) { skipped[reason.rawValue, default: 0] += 1 }

  mutating func admit(queuedAt: TimeInterval, at time: TimeInterval) -> Receipt {
    let receipt = Receipt(queuedAt: queuedAt, admittedAt: time)
    active = receipt
    evaluatorStartedAt = nil
    admitted += 1
    queue.record(seconds: time - queuedAt)
    return receipt
  }

  mutating func startEvaluator(_ receipt: Receipt, at time: TimeInterval) {
    guard active == receipt, evaluatorStartedAt == nil else { return }
    evaluatorStartedAt = time
    evaluatorStarts += 1
  }

  mutating func finish(_ receipt: Receipt, at time: TimeInterval, outcome: Outcome) {
    guard active == receipt else { return }
    switch outcome {
    case .returned: evaluatorReturns += 1
    case .failed: evaluatorFailures += 1
    case .cancelled: evaluatorCancellations += 1
    case .discardedBeforeEvaluation: discardedBeforeEvaluation += 1
    }
    if let evaluatorStartedAt { evaluatorRoundTrip.record(seconds: time - evaluatorStartedAt) }
    admissionToCompletion.record(seconds: time - receipt.admittedAt)
    observationToCompletion.record(seconds: time - receipt.queuedAt)
    active = nil
    evaluatorStartedAt = nil
  }
}

/// Read-only diagnostic projection. Strings originate only from fixed local
/// enums and the opaque session UUID; no captured content enters this type.
struct SupervisorDiagnosticSnapshot: Encodable, Sendable {
  struct Input: Encodable, Sendable {
    var status = "unavailable"
    var ageMs: Int?
  }

  struct Inputs: Encodable, Sendable {
    var screen = Input()
    var webcam = Input(status: "disabled")
    var microphone = Input()
    var system = Input()
  }

  enum RetryReason: String, Encodable, Sendable {
    case dailyQuota = "daily_quota"
    case burstQuota = "burst_quota"
    case evaluatorFailure = "evaluator_failure"
  }

  let schemaVersion = 1
  var sessionID: String?
  var sampledUptimeMs = 0
  var monitoringEnabled = false
  var suspended = false
  var ownerAuthorized = false
  var state = "idle"
  var pendingChangedObservation = false
  var evaluationSlotOccupied = false
  var currentWork = SupervisorObservationMetrics.Work.none
  var nextDueInMs: Int?
  var budgetTokens: Double = 0
  var retryReason: RetryReason?
  var retryRemainingMs = 0
  var inputs = Inputs()
  var metrics = SupervisorObservationMetrics()
}
