import Foundation

/// The operating-system window boundary of a synthetic visual preview. This
/// interface deliberately has no conversation, capture, or provider operations.
@MainActor
protocol ConversationPresentationPreviewSurface: AnyObject {
  var presentation: ConversationPresentation { get set }
  var conversationIsActive: Bool { get }
  var hasProtectedContent: Bool { get }
  var usesNotchIsland: Bool { get }
  func prepare() -> Bool
  func restore()
}

/// Development-only borrowed presentation. It projects the same logical states
/// as the conversation owner, but never admits a real conversation or voice turn.
@MainActor
final class ConversationPresentationPreview {
  private let surface: any ConversationPresentationPreviewSurface
  private let monitor: AudioLevelMonitor
  private let isNonProduction: () -> Bool
  private var meter: AudioLevelMonitor.ConversationReceipt?
  private var lastPresentation: ConversationPresentation?

  init(
    surface: any ConversationPresentationPreviewSurface,
    monitor: AudioLevelMonitor,
    isNonProduction: @escaping () -> Bool
  ) {
    self.surface = surface
    self.monitor = monitor
    self.isNonProduction = isNonProduction
  }

  func apply(_ parameters: [String: String]) -> [String: String] {
    guard isNonProduction() else {
      return ["error": "debug_bar_state is disabled on production bundles"]
    }
    guard let request = Request(parameters) else {
      return [
        "error":
          "state must be idle, opening, listening, thinking, answering, speaking, or reconnecting; levels must be finite values from 0 to 1"
      ]
    }
    guard !surface.conversationIsActive else {
      relinquish(.preserve)
      return ["error": "a conversation or user content is active"]
    }
    guard !surface.hasProtectedContent else {
      relinquish(.clearOwned)
      return ["error": "a conversation or user content is active"]
    }
    if let lastPresentation, surface.presentation != lastPresentation {
      relinquish(.preserve)
      return ["error": "the preview no longer owns the presentation"]
    }
    if request.state == "idle" {
      relinquish(.restore)
    } else {
      if meter == nil {
        guard surface.prepare() else {
          return ["error": "an empty floating presentation is unavailable"]
        }
        meter = monitor.beginConversationMeter()
      }
      guard let meter else { return ["error": "preview meter unavailable"] }
      surface.presentation = request.presentation
      lastPresentation = request.presentation
      monitor.updateConversationMicrophoneLevel(request.microphoneLevel, receipt: meter)
      monitor.updateConversationPlaybackLevel(request.playbackLevel, receipt: meter)
    }
    return [
      "state": request.state,
      "phase": request.presentation.phase.rawValue,
      "usesNotchIsland": surface.usesNotchIsland ? "true" : "false",
      "synthetic_levels": "true",
    ]
  }

  private enum SurfaceRelease { case restore, clearOwned, preserve }

  private func relinquish(_ release: SurfaceRelease) {
    guard let meter else { return }
    // A real conversation can replace this receipt between preview actions.
    // Releasing the old receipt cannot clear that conversation's live levels.
    monitor.endConversationMeter(receipt: meter)
    let ownsPresentation = surface.presentation == lastPresentation
    self.meter = nil
    lastPresentation = nil
    if release != .preserve, ownsPresentation {
      surface.presentation = .closed
      if release == .restore { surface.restore() }
    }
  }

  private struct Request {
    let state: String
    let presentation: ConversationPresentation
    let microphoneLevel: Float
    let playbackLevel: Float

    init?(_ parameters: [String: String]) {
      state = (parameters["state"] ?? "thinking").lowercased()
      let lifecycle: ConversationLifecycle.State
      let microphoneOpen: Bool
      switch state {
      case "idle":
        lifecycle = .closed
        microphoneOpen = false
      case "opening":
        lifecycle = .connecting
        microphoneOpen = false
      case "reconnecting":
        lifecycle = .reconnecting
        microphoneOpen = false
      case "listening", "thinking", "answering", "speaking":
        lifecycle = .open
        microphoneOpen = true
      default: return nil
      }
      presentation = ConversationPresentation.resolve(
        state: lifecycle, microphoneOpen: microphoneOpen, userSpeaking: false,
        replyPending: state == "thinking", playbackActive: state == "answering" || state == "speaking")
      guard
        let microphone = Self.level(parameters["microphone_level"], fallback: state == "listening" ? 0.06 : 0),
        let playback = Self.level(
          parameters["playback_level"], fallback: presentation.phase == .speaking ? 0.18 : 0)
      else { return nil }
      microphoneLevel = microphone
      playbackLevel = playback
    }

    private static func level(_ value: String?, fallback: Float) -> Float? {
      guard let value else { return fallback }
      guard let parsed = Float(value), parsed.isFinite, (0...1).contains(parsed) else { return nil }
      return parsed
    }
  }
}
