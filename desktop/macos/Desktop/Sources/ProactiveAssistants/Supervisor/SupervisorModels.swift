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

struct SupervisorTranscriptInput: Encodable, Equatable, Sendable {
  let id: String
  let text: String
  let source: SupervisorTranscriptSource
}

struct SupervisorConversationInput: Encodable, Equatable, Sendable {
  let turnID: String
  let role: String
  let text: String
  let outcome: String?
  enum CodingKeys: String, CodingKey {
    case turnID = "turn_id"
    case role, text, outcome
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
  enum CodingKeys: String, CodingKey {
    case observationID = "observation_id"
    case sessionID = "session_id"
    case contextEpoch = "context_epoch"
    case evaluationSharing = "evaluation_sharing"
    case screen, transcripts, conversation, memories, profile
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
}

enum SupervisorState: String, Sendable {
  case idle, observing, evaluating, paused, disabled
}

struct SupervisorMemoryContext: Sendable {
  let memories: [String]
  let profile: String
  static let empty = Self(memories: [], profile: "")
}
