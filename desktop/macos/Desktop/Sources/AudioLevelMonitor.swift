import Combine
import Foundation
import QuartzCore

/// Dedicated monitor for audio levels that doesn't trigger global AppState re-renders.
/// Only views that explicitly observe this class will update when audio levels change.
/// Updates are throttled to ~5 Hz to avoid flooding SwiftUI with layout invalidations.
@MainActor
class AudioLevelMonitor: ObservableObject {
  static let shared = AudioLevelMonitor()

  /// Microphone audio level (0.0 - 1.0)
  @Published private(set) var microphoneLevel: Float = 0.0

  /// System audio level (0.0 - 1.0)
  @Published private(set) var systemLevel: Float = 0.0

  /// Latest un-throttled mic level for frame-rate visualizations (notch
  /// waveform). Deliberately not @Published: TimelineView-driven canvases poll
  /// it every animation frame, so publishing at capture rate would only flood
  /// SwiftUI with invalidations the canvas doesn't need.
  private(set) var liveMicrophoneLevel: Float = 0.0

  /// Latest assistant voice playback output level (0.0 - 1.0), fed by the
  /// realtime PCM player's output tap. Same poll-per-frame contract as
  /// `liveMicrophoneLevel`.
  private(set) var liveVoicePlaybackLevel: Float = 0.0

  // Throttle: only publish at ~5 Hz (every ~200ms)
  private let updateInterval: Double = 1.0 / 5.0
  private var lastMicUpdate: Double = 0.0
  private var lastSysUpdate: Double = 0.0
  private var pendingMicLevel: Float = 0.0
  private var pendingSysLevel: Float = 0.0

  struct ConversationReceipt: Equatable, Sendable {
    fileprivate let id: UUID
  }
  private var conversationReceipt: ConversationReceipt?

  init() {}

  func beginConversationMeter() -> ConversationReceipt {
    let receipt = ConversationReceipt(id: UUID())
    conversationReceipt = receipt
    clearVoiceLevels()
    return receipt
  }

  func updateConversationMicrophoneLevel(_ level: Float, receipt: ConversationReceipt) {
    guard conversationReceipt == receipt else { return }
    publishMicrophoneLevel(level)
  }

  func updateConversationPlaybackLevel(_ level: Float, receipt: ConversationReceipt) {
    guard conversationReceipt == receipt else { return }
    liveVoicePlaybackLevel = Self.bounded(level)
  }

  func endConversationMeter(receipt: ConversationReceipt) {
    guard conversationReceipt == receipt else { return }
    conversationReceipt = nil
    clearVoiceLevels()
  }

  private func clearVoiceLevels() {
    microphoneLevel = 0
    liveMicrophoneLevel = 0
    liveVoicePlaybackLevel = 0
    lastMicUpdate = 0
  }

  private static func bounded(_ level: Float) -> Float {
    level.isFinite ? min(1, max(0, level)) : 0
  }

  /// Update microphone level - called from audio capture callback.
  /// Throttled to ~5 Hz to prevent excessive SwiftUI re-renders.
  func updateMicrophoneLevel(_ level: Float) {
    pendingMicLevel = Self.bounded(level)
    guard conversationReceipt == nil else { return }
    publishMicrophoneLevel(pendingMicLevel)
  }

  private func publishMicrophoneLevel(_ sample: Float) {
    let level = Self.bounded(sample)
    liveMicrophoneLevel = level
    let now = CACurrentMediaTime()
    if now - lastMicUpdate >= updateInterval {
      lastMicUpdate = now
      microphoneLevel = level
    }
  }

  /// Update assistant voice playback level - called (on the main queue) from
  /// the realtime PCM player's output tap. Un-throttled; see
  /// `liveVoicePlaybackLevel`.
  func updateVoicePlaybackLevel(_ level: Float) {
    guard conversationReceipt == nil else { return }
    liveVoicePlaybackLevel = Self.bounded(level)
  }

  /// Update system audio level - called from audio capture callback.
  /// Throttled to ~5 Hz to prevent excessive SwiftUI re-renders.
  func updateSystemLevel(_ level: Float) {
    pendingSysLevel = level
    let now = CACurrentMediaTime()
    if now - lastSysUpdate >= updateInterval {
      lastSysUpdate = now
      systemLevel = level
    }
  }

  /// Reset ambient levels without revoking an active conversation meter.
  func reset() {
    if conversationReceipt == nil { clearVoiceLevels() }
    systemLevel = 0.0
    pendingMicLevel = 0.0
    pendingSysLevel = 0.0
  }
}
