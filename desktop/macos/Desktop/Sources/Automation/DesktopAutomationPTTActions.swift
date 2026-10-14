import Foundation

extension DesktopAutomationActionRegistry {
  func registerPTTActions() {
    register(
      name: "conversation_open", summary: "Open the conversational voice surface through the production lifecycle."
    ) { _ in
      ConversationVoiceController.shared.open()
      return ["conversation_state": ConversationVoiceController.shared.conversationState.rawValue]
    }
    register(name: "conversation_close", summary: "End the open conversational voice surface.") { _ in
      ConversationVoiceController.shared.close()
      return ["conversation_state": ConversationVoiceController.shared.conversationState.rawValue]
    }
  }
}
