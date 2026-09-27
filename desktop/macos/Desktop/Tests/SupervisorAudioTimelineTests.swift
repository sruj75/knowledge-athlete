import XCTest

#if !SUPERVISOR_STANDALONE_TEST
  @testable import Omi_Computer
#endif

final class SupervisorAudioTimelineTests: XCTestCase {
  func testDelayedTranscriptMapsToCapturedAudioAcrossAPause() {
    var timeline = SupervisorAudioTimeline()
    timeline.append(byteCount: 32_000, interval: .init(start: 10, end: 11))
    timeline.append(byteCount: 32_000, interval: .init(start: 20, end: 21))
    XCTAssertEqual(timeline.interval(start: 0.5, end: 1.5), .init(start: 10.5, end: 20.5))
    XCTAssertNil(timeline.interval(start: 1, end: 3))
  }
}

extension SupervisorAudioTimelineTests {
  func testUnknownSpanDoesNotRebindLaterKnownAudio() {
    var timeline = SupervisorAudioTimeline()
    timeline.append(byteCount: 32_000, interval: nil)
    timeline.append(byteCount: 32_000, interval: .init(start: 30, end: 31))
    XCTAssertNil(timeline.interval(start: 0.5, end: 1.5))
    XCTAssertEqual(timeline.interval(start: 1, end: 2), .init(start: 30, end: 31))
    XCTAssertNil(timeline.interval(start: .nan, end: 2))
    XCTAssertNil(timeline.interval(start: 2, end: 1))
  }

  func testRetiredAudioFailsClosedWhileRecentClockMappingRemainsExact() {
    var timeline = SupervisorAudioTimeline()
    for index in 0..<4_100 {
      timeline.append(byteCount: 32_000, interval: .init(start: Double(index + 10), end: Double(index + 11)))
    }
    XCTAssertNil(timeline.interval(start: 0, end: 1))
    XCTAssertEqual(timeline.interval(start: 4_099.25, end: 4_099.75), .init(start: 4_109.25, end: 4_109.75))
  }
}
