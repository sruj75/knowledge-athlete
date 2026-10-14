import Foundation

/// Read-only visual projection of the logical conversation and its physical
/// input/output. It owns no capture, provider, history, or conversation state.
struct ConversationPresentation: Equatable, Sendable {
  enum Phase: String, Sendable { case closed, opening, listening, thinking, speaking }

  let phase: Phase
  let microphoneOpen: Bool
  var isOpen: Bool { phase != .closed }
  static let closed = Self(phase: .closed, microphoneOpen: false)

  static func resolve(
    state: ConversationLifecycle.State,
    microphoneOpen: Bool,
    userSpeaking: Bool,
    replyPending: Bool,
    playbackActive: Bool
  ) -> Self {
    guard state != .closed else { return .closed }
    if userSpeaking, microphoneOpen { return Self(phase: .listening, microphoneOpen: true) }
    if playbackActive { return Self(phase: .speaking, microphoneOpen: microphoneOpen) }
    if state == .connecting || state == .reconnecting {
      return Self(phase: .opening, microphoneOpen: microphoneOpen)
    }
    if replyPending { return Self(phase: .thinking, microphoneOpen: microphoneOpen) }
    if state == .open, microphoneOpen { return Self(phase: .listening, microphoneOpen: true) }
    return Self(phase: .opening, microphoneOpen: microphoneOpen)
  }
}
