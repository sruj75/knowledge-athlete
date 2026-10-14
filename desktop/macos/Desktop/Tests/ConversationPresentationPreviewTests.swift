import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationPresentationPreviewTests: XCTestCase {
  func testProductionCannotBorrowTheWindowOrAudioMeter() {
    let surface = PreviewWindow()
    let monitor = AudioLevelMonitor()
    monitor.updateMicrophoneLevel(0.4)
    let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { false })

    XCTAssertNotNil(preview.apply(["state": "listening"])["error"])
    XCTAssertFalse(surface.isVisible)
    XCTAssertEqual(surface.preparations, 0)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0.4)
  }

  func testLegacyAndConversationPhasesUseOneSyntheticPreviewUntilIdle() {
    let surface = PreviewWindow()
    let monitor = AudioLevelMonitor()
    let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { true })

    for (state, phase) in [
      ("opening", "opening"), ("listening", "listening"), ("thinking", "thinking"),
      ("answering", "speaking"), ("speaking", "speaking"), ("reconnecting", "opening"),
    ] {
      let result = preview.apply(["state": state, "microphone_level": "0.12", "playback_level": "0.24"])
      XCTAssertNil(result["error"])
      XCTAssertEqual(result["state"], state)
      XCTAssertEqual(result["phase"], phase)
      XCTAssertEqual(result["synthetic_levels"], "true")
      XCTAssertEqual(surface.presentation.phase.rawValue, phase)
      XCTAssertTrue(surface.isVisible)
      XCTAssertEqual(monitor.liveMicrophoneLevel, 0.12)
      XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0.24)
    }
    XCTAssertEqual(surface.preparations, 1)
    XCTAssertEqual(preview.apply(["state": "idle"])["phase"], "closed")
    XCTAssertEqual(surface.presentation, .closed)
    XCTAssertFalse(surface.isVisible)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0)
    XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0)
    _ = preview.apply(["state": "idle"])
    XCTAssertEqual(surface.restorations, 1)
  }

  func testInvalidInputCannotChangeAnExistingMeterOrWindow() {
    for parameters in [
      ["state": "unknown"], ["state": "listening", "microphone_level": "nan"],
      ["state": "speaking", "playback_level": "1.1"], ["state": "opening", "playback_level": "-0.1"],
    ] {
      let surface = PreviewWindow()
      let monitor = AudioLevelMonitor()
      monitor.updateVoicePlaybackLevel(0.4)
      let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { true })
      XCTAssertNotNil(preview.apply(parameters)["error"])
      XCTAssertEqual(surface.preparations, 0)
      XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0.4)
    }
  }

  func testConversationAndUserContentBlockPreview() {
    for hasConversation in [false, true] {
      let surface = PreviewWindow()
      surface.conversationIsActive = hasConversation
      surface.hasProtectedContent = !hasConversation
      let preview = ConversationPresentationPreview(
        surface: surface, monitor: AudioLevelMonitor(), isNonProduction: { true })
      XCTAssertNotNil(preview.apply(["state": "listening"])["error"])
      XCTAssertEqual(surface.preparations, 0)
    }
  }

  func testRealConversationPreemptsPreviewWithoutLosingItsPresentationOrMeter() {
    let surface = PreviewWindow()
    let monitor = AudioLevelMonitor()
    let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { true })
    _ = preview.apply(["state": "listening"])
    surface.conversationIsActive = true
    surface.presentation = ConversationPresentation(phase: .speaking, microphoneOpen: true)
    let realMeter = monitor.beginConversationMeter()
    monitor.updateConversationPlaybackLevel(0.7, receipt: realMeter)

    XCTAssertNotNil(preview.apply(["state": "idle"])["error"])
    XCTAssertEqual(surface.presentation.phase, .speaking)
    XCTAssertTrue(surface.isVisible)
    XCTAssertEqual(surface.restorations, 0)
    XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0.7)
  }

  func testUserContentTakeoverClosesOnlyTheOwnedSyntheticProjection() {
    let surface = PreviewWindow()
    let monitor = AudioLevelMonitor()
    let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { true })
    _ = preview.apply(["state": "listening"])
    surface.hasProtectedContent = true

    XCTAssertNotNil(preview.apply(["state": "idle"])["error"])
    XCTAssertEqual(surface.presentation, .closed)
    XCTAssertTrue(surface.hasProtectedContent)
    XCTAssertTrue(surface.isVisible)
    XCTAssertEqual(surface.restorations, 0)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0)
    surface.hasProtectedContent = false
    _ = preview.apply(["state": "idle"])
    XCTAssertTrue(surface.isVisible)
    XCTAssertEqual(surface.restorations, 0)
  }

  func testProtectedContentCannotClearAChangedPresentation() {
    let surface = PreviewWindow()
    let monitor = AudioLevelMonitor()
    let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { true })
    _ = preview.apply(["state": "listening"])
    surface.presentation = ConversationPresentation(phase: .thinking, microphoneOpen: true)
    surface.hasProtectedContent = true

    XCTAssertNotNil(preview.apply(["state": "idle"])["error"])
    XCTAssertEqual(surface.presentation.phase, .thinking)
    XCTAssertTrue(surface.isVisible)
    XCTAssertEqual(surface.restorations, 0)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0)
  }

  func testUnavailableWindowDoesNotAcquireAMeter() {
    let surface = PreviewWindow()
    surface.canPrepare = false
    let monitor = AudioLevelMonitor()
    monitor.updateMicrophoneLevel(0.3)
    let preview = ConversationPresentationPreview(surface: surface, monitor: monitor, isNonProduction: { true })
    XCTAssertNotNil(preview.apply(["state": "opening"])["error"])
    XCTAssertEqual(surface.presentation, .closed)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0.3)
  }
}

/// The test substitutes the operating-system window only; the presentation
/// mapper and scoped audio meter are the production implementations.
@MainActor
private final class PreviewWindow: ConversationPresentationPreviewSurface {
  var presentation = ConversationPresentation.closed
  var conversationIsActive = false
  var hasProtectedContent = false
  var usesNotchIsland = true
  var canPrepare = true
  var isVisible = false
  var preparations = 0
  var restorations = 0

  func prepare() -> Bool {
    preparations += 1
    guard canPrepare else { return false }
    isVisible = true
    return true
  }

  func restore() {
    restorations += 1
    isVisible = false
  }
}
