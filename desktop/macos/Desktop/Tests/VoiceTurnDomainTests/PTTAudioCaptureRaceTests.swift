import XCTest

@testable import Omi_Computer
@testable import VoiceTurnDomain

/// Retained CoreAudio teardown safety and legacy journal/UI projection coverage.
/// Conversation tap behavior is covered by ConversationLifecycleTests.
final class PTTAudioCaptureRaceTests: XCTestCase {
  func testDeferredCoreAudioReconfigurationCannotRestartAfterOwnerTeardown() {
    XCTAssertTrue(
      AudioCaptureService.shouldRunDeferredReconfiguration(
        isCapturing: true,
        isReconfiguring: true))
    XCTAssertFalse(
      AudioCaptureService.shouldRunDeferredReconfiguration(
        isCapturing: false,
        isReconfiguring: true))
    XCTAssertFalse(
      AudioCaptureService.shouldRunDeferredReconfiguration(
        isCapturing: true,
        isReconfiguring: false))
  }

  func testHintUsesPTTHintTextAndKeepsBarVoiceSized() throws {
    let reducer = VoiceTurnReducer()
    let turnID = VoiceTurnID()
    let started = reducer.reduce(.idle, .start(turnID: turnID, ownerID: nil, intent: .hold)).model

    let finished = reducer.reduce(started, .finish(turnID: turnID, reason: .tooShort))

    XCTAssertEqual(finished.model.turn?.phase, .terminal(.tooShort))
    XCTAssertEqual(finished.model.turn?.projection.hint, "Hold longer to record")
    XCTAssertTrue(finished.model.turn?.deadlines.contains(.hintVisibility) == true)
  }

  /// A terminal projection must clear its own hint without reopening the turn.
  func testHintPathResetsStateAndTagsHint() throws {
    let reducer = VoiceTurnReducer()
    let turnID = VoiceTurnID()
    var model = reducer.reduce(.idle, .start(turnID: turnID, ownerID: nil, intent: .hold)).model
    model = reducer.reduce(model, .finish(turnID: turnID, reason: .tooShort)).model

    XCTAssertTrue(model.turn?.phase.isTerminal == true)

    let cleared = reducer.reduce(
      model,
      .deadlineFired(turnID: turnID, deadline: .hintVisibility))
    XCTAssertEqual(cleared.model.turn?.projection.hint, "")
    XCTAssertEqual(cleared.model.turn?.phase, .terminal(.tooShort))
  }

  func testFloatingBarRendersPTTHintText() throws {
    let view = try source(relativePath: "Sources/FloatingControlBar/FloatingControlBarView.swift")
    XCTAssertTrue(view.contains("state.pttHintText"))
    XCTAssertTrue(view.contains("Text(state.pttHintText)"))
    let state = try source(relativePath: "Sources/FloatingControlBar/FloatingControlBarState.swift")
    XCTAssertTrue(state.contains("var pttHintText: String"))
  }

  /// MIC-02b: too-short PTT / mic-error copy renders in a full-width status
  /// banner under chrome (notch + non-notch), not cramped into the logo lobe.
  func testNotchIslandRendersAndSizesPTTHint() throws {
    let view = try source(relativePath: "Sources/FloatingControlBar/FloatingControlBarView.swift")
    XCTAssertTrue(view.contains("pttStatusBanner"))
    XCTAssertTrue(view.contains("showingPTTStatusBanner"))
    XCTAssertTrue(view.contains("state.isVoiceListening && state.pttHintText.isEmpty"))
    XCTAssertFalse(view.contains("showingNotchPttHint"))
    XCTAssertFalse(view.contains("notchPttHintRow"))
    // Waveform remains available in open chat. Continuous-conversation thinking
    // is separately exercised by ConversationNotchPresentationTests.
    XCTAssertFalse(view.contains("!state.isVoiceFollowUp && !state.showingAIConversation"))

    let window = try source(relativePath: "Sources/FloatingControlBar/FloatingControlBarWindow.swift")
    XCTAssertTrue(window.contains("pttHintRowHeight"))
    XCTAssertTrue(window.contains("observePttHint"))
    XCTAssertTrue(window.contains("pttHintSurfaceSize"))
    XCTAssertTrue(window.contains("pttStatusBannerBudget"))
    // Chat-open hints must grow the panel (do not bail out of observePttHint).
    XCTAssertFalse(
      window.contains(
        "guard !self.state.showingAIConversation else { return }\n                self.resizeAnchored(\n                    to: self.currentSurfaceSizeForCurrentScreen()"
      ))
  }

  private func source(relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }
}
