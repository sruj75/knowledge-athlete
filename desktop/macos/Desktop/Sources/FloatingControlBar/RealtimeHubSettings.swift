import Foundation

// MARK: - Realtime Hub
//
// "Realtime-as-hub": instead of the batch cascade (STT → Gemini Chat → TTS), one
// realtime model is the single hub. It does in-session STT, reasoning, routing
// (as tool choice), and speaks the answer. Its tools call the EXISTING backend
// endpoints / app code — no new backend routes.
//
// The hub is the default voice path — there is no opt-in toggle. Every PTT turn
// routes through it whenever a signed-in entitled user can obtain a server-minted
// ephemeral token. When minting fails or the account is not entitled, the turn falls
// back to the legacy STT cascade. Gemini Live is server-pinned; there is no
// client provider picker.

enum RealtimeHubProvider: String, Sendable, Equatable {
  case gemini

  var displayName: String { "Gemini Live" }

  /// Concrete model identifier sent to the provider.
  var modelID: String {
    return "gemini-3.1-flash-live-preview"
  }
}
