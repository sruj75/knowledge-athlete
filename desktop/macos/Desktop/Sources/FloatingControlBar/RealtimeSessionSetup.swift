import Foundation

/// Credential and prompt are captured together and pinned to one physical Live session.
struct RealtimeSessionSetup: Decodable, Sendable {
  let token: String
  let prompt: AIManagedPrompt?
}
