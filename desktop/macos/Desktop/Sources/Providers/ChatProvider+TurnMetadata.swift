import Foundation

/// Canonical turn identity and bounded telemetry classification shared by Chat entry points.
extension ChatProvider {
  nonisolated static func chatTelemetrySurface(
    turnOwner: ChatTurnOwner,
    isOnboarding: Bool,
    systemPromptStyle: ChatSystemPromptStyle
  ) -> String {
    if isOnboarding { return "onboarding" }
    switch turnOwner {
    case .floatingDefault: return "floating_text"
    case .floatingVoice: return "floating_voice"
    case .agentPill: return "agent_pill"
    case .mainChat:
      return systemPromptStyle == .floating ? "floating_text" : "main_chat"
    }
  }

  nonisolated static func chatTelemetryHasImage(
    explicitImagePresent: Bool,
    stagedImageAttachmentPresent: Bool
  ) -> Bool {
    explicitImagePresent || stagedImageAttachmentPresent
  }

  nonisolated static func messageIds(forAttemptId attemptId: String) -> (
    user: String,
    assistant: String
  ) {
    (user: attemptId, assistant: "\(attemptId)-assistant")
  }
}
