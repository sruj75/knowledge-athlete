import Foundation

// MARK: - Realtime Hub
//
// "Realtime-as-hub": instead of the cascade (STT → router → Claude → TTS), one
// realtime model is the single hub. It does in-session STT, reasoning, routing
// (as tool choice), and speaks the answer. Its tools call the EXISTING backend
// endpoints / app code — no new backend routes.
//
// The hub is the default voice path — there is no opt-in toggle. Every PTT turn
// routes through it whenever a signed-in entitled user can obtain a server-minted
// ephemeral token. When minting fails or the account is not entitled, the turn falls
// back to the legacy STT cascade. The provider follows the user's "Voice
// Model" choice in Advanced settings (RealtimeOmniSettings) — no separate picker.

enum RealtimeHubProvider: String, Sendable, Equatable {
  case openai
  case gemini

  var displayName: String {
    switch self {
    case .openai: return "OpenAI Realtime"
    case .gemini: return "Gemini Live"
    }
  }

  /// Concrete model identifier sent to the provider.
  var modelID: String {
    switch self {
    case .openai: return "gpt-realtime-2"
    // Same Live model OMI already uses (RealtimeOmniProvider.geminiFlashLive).
    // NOTE (deviation): the original plan called for a TEXT-modality half-cascade
    // model spoken via AVSpeechSynthesizer, but Google deprecated the half-cascade
    // Live models — every model that currently exposes bidiGenerateContent is
    // native-audio and rejects TEXT modality (close 1007). Verified this model does
    // AUDIO + function calling; it speaks via native audio (24k PCM) played by
    // StreamingPCMPlayer, same as OpenAI.
    case .gemini: return "gemini-3.1-flash-live-preview"
    }
  }

  /// The other realtime provider — used by the hub's failover chain: when the
  /// Auto-selected provider can't connect, the hub tries this one before dropping to
  /// the legacy Claude cascade.
  var alternate: RealtimeHubProvider {
    switch self {
    case .openai: return .gemini
    case .gemini: return .openai
    }
  }
}

@MainActor
final class RealtimeHubSettings {
  static let shared = RealtimeHubSettings()

  private init() {}

  /// The hub provider follows the user's "Voice Model" choice in Advanced settings —
  /// there is no separate hub picker. The two map 1:1 (same underlying models), and
  /// `.auto` is already resolved to a concrete provider by `effectiveProvider`.
  var provider: RealtimeHubProvider {
    switch RealtimeOmniSettings.shared.effectiveProvider {
    case .gptRealtime2: return .openai
    case .geminiFlashLive, .auto: return .gemini
    }
  }
}
