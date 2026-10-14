import XCTest

@testable import Omi_Computer

final class ConversationPresentationTests: XCTestCase {
  func testOpeningReservesTheOriginalVoicePresentationBeforeMicrophoneReadiness() {
    let presentation = ConversationPresentation.resolve(
      state: .connecting, microphoneOpen: false, userSpeaking: false,
      replyPending: false, playbackActive: false)

    XCTAssertEqual(presentation.phase, .opening)
    XCTAssertTrue(presentation.isOpen)
    XCTAssertFalse(presentation.microphoneOpen)
  }

  func testQuietConversationKeepsListeningPresentationBetweenReplies() {
    let presentation = ConversationPresentation.resolve(
      state: .open, microphoneOpen: true, userSpeaking: false,
      replyPending: false, playbackActive: false)

    XCTAssertEqual(presentation.phase, .listening)
    XCTAssertTrue(presentation.isOpen)
    XCTAssertTrue(presentation.microphoneOpen)
  }

  func testWaitingForAnAnswerShowsThinkingWhileMicrophoneRemainsAvailable() {
    let presentation = ConversationPresentation.resolve(
      state: .open, microphoneOpen: true, userSpeaking: false,
      replyPending: true, playbackActive: false)

    XCTAssertEqual(presentation.phase, .thinking)
    XCTAssertTrue(presentation.microphoneOpen)
  }

  func testRenderedPlaybackUsesSpeakingFeedbackUntilDrain() {
    let playing = ConversationPresentation.resolve(
      state: .open, microphoneOpen: true, userSpeaking: false,
      replyPending: true, playbackActive: true)
    let drained = ConversationPresentation.resolve(
      state: .open, microphoneOpen: true, userSpeaking: false,
      replyPending: false, playbackActive: false)

    XCTAssertEqual(playing.phase, .speaking)
    XCTAssertEqual(drained.phase, .listening)
    XCTAssertTrue(drained.isOpen)
  }

  func testUserSpeechImmediatelyReclaimsWaveformDuringInterruption() {
    let interrupted = ConversationPresentation.resolve(
      state: .open, microphoneOpen: true, userSpeaking: true,
      replyPending: true, playbackActive: true)

    XCTAssertEqual(interrupted.phase, .listening)
    XCTAssertTrue(interrupted.microphoneOpen)
  }

  func testReconnectKeepsOpeningFeedbackWithoutBlockingActualUserSpeech() {
    let reconnecting = ConversationPresentation.resolve(
      state: .reconnecting, microphoneOpen: true, userSpeaking: false,
      replyPending: true, playbackActive: false)
    let replying = ConversationPresentation.resolve(
      state: .reconnecting, microphoneOpen: true, userSpeaking: true,
      replyPending: true, playbackActive: false)

    XCTAssertEqual(reconnecting.phase, .opening)
    XCTAssertTrue(reconnecting.isOpen)
    XCTAssertEqual(replying.phase, .listening)
  }

  func testClosedConversationCannotBeReanimatedByOldAudioFlags() {
    let closed = ConversationPresentation.resolve(
      state: .closed, microphoneOpen: true, userSpeaking: true,
      replyPending: true, playbackActive: true)

    XCTAssertEqual(closed, .closed)
  }

  func testFallbackUsesTheSameVisibleListeningAndReplyStates() {
    var lifecycle = ConversationLifecycle()
    lifecycle.open(id: "conversation", now: 0)
    lifecycle.useFallback(now: 1)
    let listening = ConversationPresentation.resolve(
      state: lifecycle.state, microphoneOpen: true, userSpeaking: false,
      replyPending: false, playbackActive: false)
    let replying = ConversationPresentation.resolve(
      state: lifecycle.state, microphoneOpen: true, userSpeaking: false,
      replyPending: true, playbackActive: false)

    XCTAssertEqual(listening.phase, .listening)
    XCTAssertEqual(replying.phase, .thinking)
    XCTAssertTrue(replying.isOpen)
  }
}
