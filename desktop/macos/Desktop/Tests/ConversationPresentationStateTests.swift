import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationPresentationStateTests: XCTestCase {
  func testOpeningDrivesOriginalGlowAndThinkingWithoutTurnCaptureOwnership() {
    let state = FloatingControlBarState()
    state.showingAIConversation = true
    state.setConversationPresentation(
      .resolve(
        state: .connecting, microphoneOpen: false, userSpeaking: false,
        replyPending: false, playbackActive: false))

    XCTAssertTrue(state.isThinking)
    XCTAssertTrue(state.isVoiceResponseGlowActive)
    XCTAssertTrue(state.isVoicePresentationActive)
    XCTAssertFalse(state.isVoiceListening)
    XCTAssertFalse(state.conversationMicrophoneOpen)
  }

  func testIdleTurnProjectionCannotCollapseAnOpenListeningConversation() {
    let state = FloatingControlBarState()
    let coordinator = VoiceTurnCoordinator()
    coordinator.configure(barState: state)
    state.showingAIConversation = true
    state.setConversationPresentation(
      .resolve(
        state: .open, microphoneOpen: true, userSpeaking: false,
        replyPending: false, playbackActive: false))

    coordinator.reset()

    XCTAssertTrue(state.showingAIConversation)
    XCTAssertTrue(state.isVoiceListening)
    XCTAssertTrue(state.conversationMicrophoneOpen)
    XCTAssertTrue(state.isVoicePresentationActive)
    XCTAssertFalse(state.isVoiceResponseActive)
    XCTAssertFalse(state.isThinking)
  }

  func testActualPlaybackAndInterruptionSelectDifferentFeedbackWhileInputStaysOpen() {
    let state = FloatingControlBarState()
    state.setConversationPresentation(
      .resolve(
        state: .open, microphoneOpen: true, userSpeaking: false,
        replyPending: true, playbackActive: true))
    XCTAssertTrue(state.isVoiceResponseActive)
    XCTAssertTrue(state.isVoiceResponseGlowActive)
    XCTAssertFalse(state.isVoiceListening)
    XCTAssertFalse(state.isThinking)

    state.setConversationPresentation(
      .resolve(
        state: .open, microphoneOpen: true, userSpeaking: true,
        replyPending: true, playbackActive: true))
    XCTAssertTrue(state.isVoiceListening)
    XCTAssertTrue(state.conversationMicrophoneOpen)
    XCTAssertFalse(state.isVoiceResponseActive)
    XCTAssertFalse(state.isVoiceResponseGlowActive)
  }

  func testLogicalCloseReleasesPresentationAndMicrophoneIndicatorTogether() {
    let state = FloatingControlBarState()
    state.setConversationPresentation(
      .resolve(
        state: .open, microphoneOpen: true, userSpeaking: false,
        replyPending: false, playbackActive: false))

    state.setConversationPresentation(.closed)

    XCTAssertFalse(state.conversationMicrophoneOpen)
    XCTAssertFalse(state.isVoiceListening)
    XCTAssertFalse(state.isVoicePresentationActive)
    XCTAssertFalse(state.isVoiceResponseGlowActive)
  }
}
