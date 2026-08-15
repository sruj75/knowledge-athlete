import Foundation

extension DesktopAutomationActionRegistry {
  func registerManagedAccessActions() {
    register(
      name: "advanced_settings_snapshot",
      summary: "Return safe Advanced settings and managed-access state",
      params: []
    ) { _ in
      let focus = FocusAssistantSettings.shared
      let task = TaskAssistantSettings.shared
      let insight = InsightAssistantSettings.shared
      let memory = MemoryAssistantSettings.shared
      let assistant = AssistantSettings.shared
      return [
        "focus_enabled": focus.isEnabled ? "true" : "false",
        "task_enabled": task.isEnabled ? "true" : "false",
        "task_chat_agent_enabled": TaskAgentSettings.shared.isChatEnabled ? "true" : "false",
        "insight_enabled": insight.isEnabled ? "true" : "false",
        "memory_enabled": memory.isEnabled ? "true" : "false",
        "screen_analysis_enabled": assistant.screenAnalysisEnabled ? "true" : "false",
        "transcription_enabled": assistant.transcriptionEnabled ? "true" : "false",
        "multi_chat_enabled": UserDefaults.standard.bool(forKey: .multiChatEnabled) ? "true" : "false",
        "ask_mode_enabled": UserDefaults.standard.bool(forKey: "askModeEnabled") ? "true" : "false",
        "access_model": "managed",
        "customer_key_controls_visible": "false",
      ]
    }

    register(
      name: "managed_ai_error_snapshot",
      summary: "Return managed-only Gemini and embedding product-gate messages",
      params: []
    ) { _ in
      let geminiError = GeminiClient.GeminiClientError.apiError("HTTP 402: trial_expired")
      let embeddingError = EmbeddingService.EmbeddingError.serverError(
        statusCode: 402,
        body: #"{"error":"trial_expired"}"#)
      return [
        "gemini_message": geminiError.localizedDescription,
        "gemini_expected_product_state": geminiError.isExpectedProductState ? "true" : "false",
        "embedding_message": embeddingError.localizedDescription,
        "embedding_reason": embeddingError.reasonCode,
      ]
    }
  }
}
