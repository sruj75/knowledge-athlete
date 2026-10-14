import Foundation

struct AIManagedPrompt: Codable, Equatable, Sendable {
  let text: String
  let name: String
  let version: String
  let source: String
}

enum SupervisorAction: String, Codable, Sendable {
  case wait
  case guideNextTurn = "guide_next_turn"
  case intervene
}

enum SupervisorTranscriptSource: String, Codable, Sendable {
  case microphone, system, mixed, user, assistant
}

struct SupervisorTranscriptProvenance: Equatable, Sendable {
  let producerID: UUID
  let source: SupervisorTranscriptSource
  let capture: SupervisorCaptureInterval
}

struct SupervisorScreenInput: Encodable, Sendable {
  let jpegBase64: String
  let appName: String
  let windowTitle: String?
  let capturedAt: String
  enum CodingKeys: String, CodingKey {
    case jpegBase64 = "jpeg_base64"
    case appName = "app_name"
    case windowTitle = "window_title"
    case capturedAt = "captured_at"
  }
}

struct SupervisorWebcamInput: Encodable, Sendable {
  let jpegBase64: String
  let capturedAt: String
  enum CodingKeys: String, CodingKey {
    case jpegBase64 = "jpeg_base64"
    case capturedAt = "captured_at"
  }
}

enum SupervisorInputAvailability: String, Encodable, Sendable {
  case available, disabled, denied, unavailable, stale, suspended
}

struct SupervisorInputStatus: Encodable, Sendable {
  var status: SupervisorInputAvailability = .unavailable
  var capturedAt: String?
  var ageMs: Int?
  enum CodingKeys: String, CodingKey {
    case status
    case capturedAt = "captured_at"
    case ageMs = "age_ms"
  }
}

struct SupervisorInputStatuses: Encodable, Sendable {
  var screen = SupervisorInputStatus()
  var webcam = SupervisorInputStatus(status: .disabled)
  var microphone = SupervisorInputStatus()
  var system = SupervisorInputStatus()
}

enum SupervisorConversationState: String, Encodable, Sendable {
  case closed, connecting, open, reconnecting, ending
}

struct SupervisorActiveConversation: Encodable, Equatable, Sendable {
  let id: String
  let state: SupervisorConversationState
}

struct SupervisorTranscriptInput: Encodable, Equatable, Sendable {
  let id: String
  let text: String
  let source: SupervisorTranscriptSource
  var revision: Int = 0
  var final: Bool = true
}

struct SupervisorConversationInput: Encodable, Equatable, Sendable {
  let turnID: String
  let role: String
  let text: String
  let outcome: String?
  var revision: Int = 0
  var final: Bool = true
  enum CodingKeys: String, CodingKey {
    case turnID = "turn_id"
    case role, text, outcome, revision, final
  }
}

struct SupervisorEvaluationRequest: Encodable, Sendable {
  let observationID: String
  let sessionID: String
  let contextEpoch: UInt64
  let screen: SupervisorScreenInput?
  let transcripts: [SupervisorTranscriptInput]
  let conversation: [SupervisorConversationInput]
  let memories: [String]
  let profile: String
  let evaluationSharing: Bool
  var observedAt: String = ""
  var contentRevision: UInt64 = 0
  var webcam: SupervisorWebcamInput?
  var inputStatus = SupervisorInputStatuses()
  var activeConversation: SupervisorActiveConversation?
  enum CodingKeys: String, CodingKey {
    case observationID = "observation_id"
    case sessionID = "session_id"
    case contextEpoch = "context_epoch"
    case evaluationSharing = "evaluation_sharing"
    case observedAt = "observed_at"
    case contentRevision = "content_revision"
    case inputStatus = "input_status"
    case activeConversation = "active_conversation"
    case screen, webcam, transcripts, conversation, memories, profile
  }
}

struct SupervisorEvaluationResponse: Decodable, Sendable {
  let decisionID: String
  let observationID: String
  let sessionID: String
  let contextEpoch: UInt64
  let action: SupervisorAction
  let note: String?
  let prompt: AIManagedPrompt
  let outcome: String
  enum CodingKeys: String, CodingKey {
    case decisionID = "decision_id"
    case observationID = "observation_id"
    case sessionID = "session_id"
    case contextEpoch = "context_epoch"
    case action, note, prompt, outcome
  }
}

struct SupervisorGuidance: Sendable {
  let id: String
  let observationID: String
  let sessionID: String
  let contextEpoch: UInt64
  let note: String
  let expiresAt: Date
  let authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  let action: SupervisorAction
  var context: String = ""
  var relevantObservationEpoch: UInt64 = 0
}

enum SupervisorState: String, Sendable {
  case idle, observing, evaluating, paused, suspended, disabled
}

struct SupervisorObservationMetrics: Equatable, Sendable {
  var admitted = 0
  var budgetDeferrals = 0
  var replacedPending = 0
  var queueMs = 0
  var providerMs = 0
  var endToEndMs = 0
}

enum SupervisorRequestError: Error {
  case payloadTooLarge
  case rateLimited(reason: String, retryAfterSeconds: Int)
}

struct SupervisorMemoryContext: Sendable {
  let memories: [String]
  let profile: String
  static let empty = Self(memories: [], profile: "")
}
