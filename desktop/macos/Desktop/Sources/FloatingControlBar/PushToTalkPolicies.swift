import Foundation
import VoiceTurnDomain

struct PTTSilentMicRecoveryPolicy {
  enum RecoveryOutcome: String, Equatable {
    case succeeded
    case failed
  }

  struct DiscardedTurnDecision: Equatable {
    let shouldRebuildCapture: Bool
    let recoveryOutcome: RecoveryOutcome?
  }

  static let deadMicPeakThreshold = 5
  static let minDeadTurnSeconds: TimeInterval = 0.25
  static let consecutiveDeadTurnThreshold = 2

  private(set) var consecutiveDeadMicTurns = 0
  private var awaitingRecoveryOutcome = false

  mutating func recordDiscardedTurn(totalSec: TimeInterval, peak: Int) -> DiscardedTurnDecision {
    let recoveryOutcome: RecoveryOutcome?
    let shouldRebuildCapture: Bool

    if peak > Self.deadMicPeakThreshold {
      // Audible input proves the mic is alive, whatever else went wrong with the turn.
      recoveryOutcome = resolveRecoveryOutcome(.succeeded)
      consecutiveDeadMicTurns = 0
      shouldRebuildCapture = false
    } else if totalSec >= Self.minDeadTurnSeconds {
      recoveryOutcome = resolveRecoveryOutcome(.failed)
      consecutiveDeadMicTurns += 1
      shouldRebuildCapture = consecutiveDeadMicTurns >= Self.consecutiveDeadTurnThreshold
      if shouldRebuildCapture {
        // Arm the outcome before issuing the side effect. This prevents a third
        // consecutive turn from asking for a second rebuild while the first awaits
        // its next judgeable turn.
        consecutiveDeadMicTurns = 0
        awaitingRecoveryOutcome = true
      }
    } else {
      // A turn too short to judge carries no evidence either way — an accidental
      // tap, or a release that beat CoreAudio's capture start and delivered no
      // frames. It must not erase a dead-mic streak or resolve a pending rebuild.
      recoveryOutcome = nil
      shouldRebuildCapture = false
    }
    return DiscardedTurnDecision(
      shouldRebuildCapture: shouldRebuildCapture,
      recoveryOutcome: recoveryOutcome)
  }

  mutating func recordSuccessfulTurn() -> RecoveryOutcome? {
    consecutiveDeadMicTurns = 0
    return resolveRecoveryOutcome(.succeeded)
  }

  /// Bluetooth silent-mic fallback only needs the dead-mic streak cleared. It must
  /// not arm `capture_rebuild` outcomes — that recovery uses `switch_to_built_in_mic`.
  mutating func recordCaptureRebuild() {
    consecutiveDeadMicTurns = 0
  }

  /// Arm truthful success/failure reporting for a CoreAudio capture rebuild. Used by
  /// both the dead-mic threshold path and the mid-turn silent-mic watchdog rebuild.
  mutating func armCaptureRebuildOutcome() {
    consecutiveDeadMicTurns = 0
    awaitingRecoveryOutcome = true
  }

  private mutating func resolveRecoveryOutcome(_ outcome: RecoveryOutcome) -> RecoveryOutcome? {
    guard awaitingRecoveryOutcome else { return nil }
    awaitingRecoveryOutcome = false
    return outcome
  }
}

/// Modifier-only shortcuts (Option, Fn, etc.) overlap with normal text editing:
/// Option-arrow navigation and dead-key entry first emit `flagsChanged`, then a
/// normal key-down. Do not let that first modifier event barge into an active
/// spoken reply before the accompanying editing key arrives.
///
/// The gate deliberately has no timing policy. `PushToTalkManager` supplies the
/// short hold delay, while this model makes the admission/cancellation contract
/// deterministic and independently testable.
struct ModifierOnlyPTTActivationGate {
  enum Action: Equatable {
    case scheduleStart
    case cancelPendingStart
    case releaseStartedTurn
    case none
  }

  private(set) var hasPendingStart = false
  private(set) var hasStartedTurn = false

  mutating func modifierStateChanged(isShortcutActive: Bool) -> Action {
    if isShortcutActive {
      guard !hasPendingStart, !hasStartedTurn else { return .none }
      hasPendingStart = true
      return .scheduleStart
    }

    if hasPendingStart {
      hasPendingStart = false
      return .cancelPendingStart
    }
    guard hasStartedTurn else { return .none }
    hasStartedTurn = false
    return .releaseStartedTurn
  }

  mutating func nonModifierKeyPressed() -> Action {
    guard hasPendingStart else { return .none }
    hasPendingStart = false
    return .cancelPendingStart
  }

  mutating func consumePendingStart() -> Bool {
    guard hasPendingStart else { return false }
    hasPendingStart = false
    hasStartedTurn = true
    return true
  }

  mutating func cancelPendingStart() {
    hasPendingStart = false
  }

  mutating func reset() {
    hasPendingStart = false
    hasStartedTurn = false
  }
}

extension Notification.Name {
  static let coreAudioCaptureRecoveryRequested = Notification.Name("coreAudioCaptureRecoveryRequested")
}

#if DEBUG
  struct PTTOwnerBoundarySnapshot: Equatable {
    let activeTurnID: VoiceTurnID?
    let hasCaptureDriver: Bool
    let captureStartInFlight: Bool
    let hasTranscriptionDriver: Bool
    let bufferedAudioBytes: Int
    let captureGeneration: UInt64
  }
#endif
