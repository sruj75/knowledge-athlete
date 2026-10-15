import Foundation

extension DesktopAutomationActionRegistry {
  func registerConversationDiagnosticActions() {
    register(
      name: "conversation_diagnostics_snapshot",
      summary: "Read non-production conversation input, lifecycle and delivery metadata; no content or capture."
    ) { _ in
      guard AppBuild.isNonProduction,
        let snapshot = ConversationVoiceController.shared.diagnosticSnapshot()
      else { return ["error": "conversation diagnostics are disabled on production bundles"] }
      let encoded = try JSONEncoder().encode(snapshot)
      return ["scope": "physical_conversation", "snapshot_json": String(decoding: encoded, as: UTF8.self)]
    }
  }
}
