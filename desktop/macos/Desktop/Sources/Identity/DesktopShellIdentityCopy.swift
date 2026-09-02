enum DesktopShellIdentityCopy {
  static let productName = "Intentive"
  static let chatWelcomeTitle = productName
  static let chatWelcomeDetail = "Can use your local memories and conversations when available."
  static let askAnything = "Ask Intentive anything"
  static let openChat = "Open Intentive chat"
  static let openChatHint = "Open the main Intentive chat window"
  static let closeChat = "Close Intentive Chat"
  static let chatTitle = "Intentive Chat"
  static let openApp = "Open Intentive"
  static let continueInApp = "Continue in Intentive"
  static let steerAgentHelp = "Open the Intentive app to steer this agent"
  static let keepChattingHelp = "Open the Intentive app to keep chatting"
  static let rewindMenuAccessibility = "Intentive Rewind"

  static func isProductWindowTitle(_ title: String) -> Bool {
    title.localizedCaseInsensitiveContains(productName)
      || title.lowercased().hasPrefix("omi-")
  }

  static let allText = [
    productName,
    chatWelcomeTitle,
    chatWelcomeDetail,
    askAnything,
    openChat,
    openChatHint,
    closeChat,
    chatTitle,
    openApp,
    continueInApp,
    steerAgentHelp,
    keepChattingHelp,
    rewindMenuAccessibility,
  ]
}
