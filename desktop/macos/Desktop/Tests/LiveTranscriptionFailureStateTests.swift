import XCTest

@testable import Omi_Computer

@MainActor
final class LiveTranscriptionFailureStateTests: XCTestCase {
  func testTerminalFailureRemainsVisibleUntilTheBackendReportsReady() async {
    let state = AppState()

    await state.handleListenEvent(
      .serviceStatus(.sttFailed)
    )

    XCTAssertEqual(state.transcriptionServiceError, "Transcription unavailable")

    await state.handleListenEvent(
      .serviceStatus(.ready)
    )

    XCTAssertNil(state.transcriptionServiceError)
  }

  func testStoppingAfterTerminalFailureClearsTheEndedSessionError() async {
    let state = AppState()
    await state.handleListenEvent(
      .serviceStatus(.sttFailed)
    )

    state.stopTranscription()

    XCTAssertNil(state.transcriptionServiceError)
  }

  func testLateCloudCallbacksCannotMutateANewerLocalSession() async {
    let state = AppState()
    state.currentSessionId = 22

    await state.handleListenEvent(.serviceStatus(.sttFailed), expectedSessionId: 11)
    await state.handleBackendSegments(
      [
        TranscriptionService.BackendSegment(
          segmentId: "a1b2c3d4-e5f6-4890-abcd-ef1234567890",
          speakerId: 0,
          text: "stale",
          isUser: false,
          start: 0,
          end: 1)
      ],
      expectedSessionId: 11)

    XCTAssertNil(state.transcriptionServiceError)
    XCTAssertTrue(state.speakerSegments.isEmpty)
  }
}
