import XCTest

@testable import Omi_Computer

final class LocalTranscriptFormatterTests: XCTestCase {
  func testNormalizerJoinsSameSpeakerRepairsBoundaryAndCleansPunctuation() {
    let existing = [
      LocalTranscriptSegment(
        segmentId: "40000000-0000-4000-8000-000000000001", speakerId: 0,
        text: "I think we should probably", startTime: 0, endTime: 2, segmentOrder: 0, isUser: true,
        translations: [])
    ]
    let incoming = [
      LocalTranscriptSegment(
        segmentId: "40000000-0000-4000-8000-000000000002", speakerId: 1,
        text: "do that.  Next point .", startTime: 2, endTime: 4, segmentOrder: 1, isUser: false,
        translations: []),
      LocalTranscriptSegment(
        segmentId: "40000000-0000-4000-8000-000000000003", speakerId: 1,
        text: "and continue?", startTime: 4.5, endTime: 5, segmentOrder: 2, isUser: false,
        translations: []),
    ]

    let normalized = LocalTranscriptFormatter.normalize(existing: existing, incoming: incoming)

    XCTAssertEqual(
      normalized.segments.map(\.text), ["I think we should probably do that.", "Next point. and continue?"])
    XCTAssertEqual(normalized.removedSegmentIds, ["40000000-0000-4000-8000-000000000003"])
  }

  func testFormatterUsesConversationLabelsUserFallbackAndOverlapTimestampGuard() {
    let segments = [
      LocalTranscriptSegment(
        segmentId: "50000000-0000-4000-8000-000000000001", speakerId: 0, text: "hello", startTime: 0,
        endTime: 1, segmentOrder: 0, isUser: true, translations: []),
      LocalTranscriptSegment(
        segmentId: "50000000-0000-4000-8000-000000000002", speakerId: 1, text: "hi", startTime: 2,
        endTime: 3, segmentOrder: 1, isUser: false, translations: []),
    ]

    XCTAssertEqual(
      LocalTranscriptFormatter.format(
        segments: segments, speakerLabels: [1: "Alice"], userName: "", includeTimestamps: true),
      "[0:00:00 - 0:00:01] User: hello\n\n[0:00:02 - 0:00:03] Alice: hi")

    var overlapping = segments
    overlapping[1].startTime = 0.5
    XCTAssertEqual(
      LocalTranscriptFormatter.format(
        segments: overlapping, speakerLabels: [:], userName: "Sam", includeTimestamps: true),
      "Sam: hello\n\nSpeaker 1: hi")
  }
}
