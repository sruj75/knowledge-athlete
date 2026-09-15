import XCTest

@testable import Omi_Computer

@MainActor
final class LiveTranscriptionFailureStateTests: XCTestCase {
  func testBackendSegmentsStayChronologicalAcrossArrivalBatchesAndUpdates() async {
    let monitor = LiveTranscriptMonitor.shared
    monitor.clear()
    monitor.clearSaved()
    defer {
      monitor.clear()
      monitor.clearSaved()
    }

    let state = AppState()
    let earlyId = "80000000-0000-4000-8000-000000000001"
    let continuationId = "80000000-0000-4000-8000-000000000002"
    let lateId = "80000000-0000-4000-8000-000000000003"
    let equalLateId = "80000000-0000-4000-8000-000000000004"

    await state.handleBackendSegments([
      TranscriptionService.BackendSegment(
        segmentId: lateId,
        speakerId: 1,
        text: "Later.",
        isUser: false,
        start: 15,
        end: 16)
    ])
    await state.handleBackendSegments([
      TranscriptionService.BackendSegment(
        segmentId: continuationId,
        speakerId: 0,
        text: "world.",
        isUser: true,
        start: 3,
        end: 4),
      TranscriptionService.BackendSegment(
        segmentId: earlyId,
        speakerId: 0,
        text: "Hello",
        isUser: true,
        start: 2,
        end: 3,
        translations: [.init(lang: "es", text: "Hola mundo.")]),
      TranscriptionService.BackendSegment(
        segmentId: equalLateId,
        speakerId: 2,
        text: "Also later.",
        isUser: false,
        start: 15,
        end: 17),
    ])
    await state.handleBackendSegments([
      TranscriptionService.BackendSegment(
        segmentId: earlyId,
        speakerId: 0,
        text: "Hello corrected",
        isUser: true,
        start: 2,
        end: 3)
    ])

    XCTAssertEqual(state.speakerSegments.map(\.segmentId), [earlyId, continuationId, lateId, equalLateId])
    XCTAssertEqual(state.speakerSegments.map(\.start), [2, 3, 15, 15])
    let correctedEarly = state.speakerSegments.first { $0.segmentId == earlyId }
    XCTAssertEqual(correctedEarly?.text, "Hello corrected")
    XCTAssertEqual(correctedEarly?.translations.map(\.lang), ["es"])
    XCTAssertEqual(correctedEarly?.translations.map(\.text), ["Hola mundo."])
    XCTAssertEqual(monitor.segments.map(\.segmentId), state.speakerSegments.map(\.segmentId))
  }

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
