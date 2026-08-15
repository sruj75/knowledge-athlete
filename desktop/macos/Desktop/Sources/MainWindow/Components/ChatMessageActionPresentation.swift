enum AssistantMessageSurface: CaseIterable {
  case normalChat
  case floatingChat
}

enum ChatMessageAction: Equatable {
  case copy
  case info
  case timestamp
}

enum ChatMessageActionPresentation {
  static func actions(
    for surface: AssistantMessageSurface,
    isStreaming: Bool,
    copyableText: String,
    hasMetadata: Bool
  ) -> [ChatMessageAction] {
    _ = surface
    guard !isStreaming else { return [] }

    var actions: [ChatMessageAction] = []
    if !copyableText.isEmpty {
      actions.append(.copy)
      if hasMetadata {
        actions.append(.info)
      }
    }
    actions.append(.timestamp)
    return actions
  }
}
