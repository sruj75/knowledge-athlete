import Foundation

struct AgentSurfaceReference: Hashable, Sendable {
  let surfaceKind: String
  let externalRefKind: String
  let externalRefId: String

  var key: String { "\(surfaceKind)|\(externalRefKind)|\(externalRefId)" }
  var displayRef: String { "\(externalRefKind):\(externalRefId)" }

  static func mainChat(chatId: String?) -> AgentSurfaceReference {
    AgentSurfaceReference(
      surfaceKind: "main_chat",
      externalRefKind: "chat",
      externalRefId: chatId?.isEmpty == false ? chatId! : "default"
    )
  }

  static func realtimeVoice(chatId: String? = nil) -> AgentSurfaceReference {
    AgentSurfaceReference(
      surfaceKind: "realtime_voice",
      externalRefKind: "chat",
      externalRefId: chatId?.isEmpty == false ? chatId! : "default"
    )
  }

  /// Typed and spoken turns share the same canonical conversation.
  func realtimeVoiceCompanion() -> AgentSurfaceReference {
    AgentSurfaceReference(
      surfaceKind: "realtime_voice",
      externalRefKind: externalRefKind,
      externalRefId: externalRefId
    )
  }

  static func floatingChat(chatId: String? = nil) -> AgentSurfaceReference {
    AgentSurfaceReference(
      surfaceKind: "floating_chat",
      externalRefKind: "chat",
      externalRefId: chatId?.isEmpty == false ? chatId! : "default"
    )
  }

  static func onboarding() -> AgentSurfaceReference {
    AgentSurfaceReference(surfaceKind: "onboarding", externalRefKind: "session", externalRefId: "default")
  }
}
