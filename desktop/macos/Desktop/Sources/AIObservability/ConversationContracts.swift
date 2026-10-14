import CryptoKit
import Foundation

struct ConversationPromptReference: Codable, Equatable, Sendable {
  let name: String
  let version: String
  let source: String
  let sha256: String
}

struct ConversationPromptReceipt: Codable, Equatable, Sendable {
  let text: String
  let name: String
  let version: String
  let source: String
  let sha256: String

  var reference: ConversationPromptReference {
    .init(name: name, version: version, source: source, sha256: sha256)
  }

  func validate() throws {
    let actual = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    guard name == "intentive-live-system", !version.isEmpty, !text.isEmpty, actual == sha256 else {
      throw ConversationAPIError.invalidPromptReceipt
    }
  }
}

struct ConversationHistoryMessage: Codable, Equatable, Sendable {
  let role: String
  let text: String
}

struct ConversationImage: Codable, Sendable {
  let jpegBase64: String
  enum CodingKeys: String, CodingKey { case jpegBase64 = "jpeg_base64" }
}

struct ConversationResponseRequest: Encodable, Sendable {
  let conversationID: String
  let turnID: String
  let promptReference: ConversationPromptReference
  let history: [ConversationHistoryMessage]
  let message: String
  let context: String
  var guidance: String? = nil
  var image: ConversationImage? = nil

  enum CodingKeys: String, CodingKey {
    case conversationID = "conversation_id"
    case turnID = "turn_id"
    case promptReference = "prompt_ref"
    case history, message, context, guidance, image
  }
}

struct ConversationResponseCompletion: Decodable, Sendable {
  let endConversation: Bool
  let promptReference: ConversationPromptReference
  let modelVersion: String?
  let usage: ConversationTokenUsage?

  enum CodingKeys: String, CodingKey {
    case endConversation = "end_conversation"
    case promptReference = "prompt_ref"
    case modelVersion = "model_version"
    case usage
  }
}

/// All buckets are exclusive; cached input is not included again in inputTokens.
struct ConversationTokenUsage: Decodable, Sendable {
  let inputTokens: Int
  let cachedInputTokens: Int
  let outputTokens: Int
  let thinkingTokens: Int
  let totalTokens: Int
  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case cachedInputTokens = "cached_input_tokens"
    case outputTokens = "output_tokens"
    case thinkingTokens = "thinking_tokens"
    case totalTokens = "total_tokens"
  }
}

enum ConversationDeliveryOutcome: String, Sendable {
  case completed, interrupted, failed
  case notSpoken = "not_spoken"
}

enum ConversationAPIError: Error, Equatable {
  case invalidPromptReceipt
  case requestTooLarge
  case invalidStream
  case incompleteResponse
  case provider(code: String, retryable: Bool)
}
