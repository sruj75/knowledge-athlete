import Foundation
import VoiceTurnDomain

/// Owns only the audible transition around a real PTT capture. The voice-turn
/// reducer remains the lifecycle authority; this seam makes the ordering of the
/// AppKit sound and CoreAudio mute effects deterministic and testable.
final class PTTCaptureAudioTransition {
  enum Terminal: Equatable {
    case completed
    case cancelled
    case failed
    case ownerChanged
  }

  static func terminal(for reason: VoiceTurnTerminalReason) -> Terminal {
    switch reason {
    case .success:
      return .completed
    case .ownerChanged:
      return .ownerChanged
    case .cancelled, .interruptedByBargeIn, .explicitInterrupt, .cleanup:
      return .cancelled
    case .tooShort, .silentRejected, .permissionDenied, .captureFailed,
      .transcriptionFailed, .providerFailed, .providerNoResponse, .hubWarmTimeout,
      .deferredCommitTimeout, .bargeInReplacementTimeout, .toolTimeout,
      .playbackFailed, .journalFailed:
      return .failed
    }
  }

  private let playStartCue: () -> Void
  private let playEndCue: () -> Void
  private let muteOutput: () -> Void
  private let restoreOutput: () -> Void
  private var captureStarted = false
  private var captureEndedAwaitingTerminal = false
  private var soundsEnabled = false

  init(
    playStartCue: @escaping () -> Void,
    playEndCue: @escaping () -> Void,
    muteOutput: @escaping () -> Void,
    restoreOutput: @escaping () -> Void
  ) {
    self.playStartCue = playStartCue
    self.playEndCue = playEndCue
    self.muteOutput = muteOutput
    self.restoreOutput = restoreOutput
  }

  func begin(soundsEnabled: Bool, muteEnabled: Bool) {
    guard !captureStarted else { return }
    captureStarted = true
    captureEndedAwaitingTerminal = false
    self.soundsEnabled = soundsEnabled
    if soundsEnabled { playStartCue() }
    if muteEnabled { muteOutput() }
  }

  /// Restore playback as soon as capture physically ends, while deferring the
  /// completion cue until the captured audio passes its admission fence.
  func finishCapture() {
    guard captureStarted else { return }
    restoreOutput()
    captureStarted = false
    captureEndedAwaitingTerminal = true
  }

  func end(_ terminal: Terminal) {
    if captureStarted {
      restoreOutput()
      captureStarted = false
      captureEndedAwaitingTerminal = true
    } else if !captureEndedAwaitingTerminal {
      restoreOutput()
      return
    }
    captureEndedAwaitingTerminal = false
    defer { soundsEnabled = false }
    guard terminal == .completed, soundsEnabled else { return }
    playEndCue()
  }
}
