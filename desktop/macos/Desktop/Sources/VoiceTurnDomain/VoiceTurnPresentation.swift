package struct VoiceTurnUIProjection: Equatable, Sendable {
  package var isListening = false
  package var isLocked = false
  package var transcript = ""
  package var hint = ""
  package var isThinking = false
  package var isResponseWaiting = false
  package var isResponseActive = false

  package static let idle = VoiceTurnUIProjection()
}

/// Pure copy / status-banner projections over reducer state and terminal reasons.
/// Every string here is derived from existing `VoiceTurnUIProjection` / `VoiceTurnTerminalReason`
/// — not a second lifecycle enum.
package enum VoiceTurnUICopy {
  package static let transcribingProgress = "Transcribing…"

  /// Banner text is reserved for actionable capture/provider failures. Normal
  /// recording, transcription, fallback, and barge-in state stays visual.
  package static func statusBannerText(for projection: VoiceTurnUIProjection) -> String {
    projection.hint
  }

  /// User-facing terminal hint. Branches on typed reason only.
  package static func terminalHint(for reason: VoiceTurnTerminalReason) -> String? {
    switch reason {
    case .tooShort:
      return "Hold longer to record"
    case .captureFailed:
      return "Microphone unavailable — try again"
    case .transcriptionFailed:
      return "Couldn't transcribe that — try again"
    case .journalFailed:
      return "Couldn't save that reply — try again"
    case .providerFailed, .providerNoResponse, .deferredCommitTimeout:
      return "Couldn't get a voice reply — try again"
    case .bargeInReplacementTimeout:
      return "Previous reply was interrupted — try again"
    case .toolTimeout:
      return "A tool took too long — try again"
    case .playbackFailed:
      return "Audio playback failed"
    case .interruptedByBargeIn:
      // Applied on the replacement turn in `.start` (this turn is replaced immediately).
      return nil
    case .success, .silentRejected, .cancelled, .ownerChanged, .explicitInterrupt,
      .permissionDenied, .hubWarmTimeout, .cleanup:
      return nil
    }
  }
}

package enum VoiceTurnDebugPresentationState: String, Equatable, Sendable {
  case idle
  case listening
  case thinking
  case answering

  package var projection: VoiceTurnUIProjection {
    switch self {
    case .idle:
      return .idle
    case .listening:
      return VoiceTurnUIProjection(isListening: true)
    case .thinking:
      return VoiceTurnUIProjection(isThinking: true)
    case .answering:
      return VoiceTurnUIProjection(isResponseActive: true)
    }
  }
}
