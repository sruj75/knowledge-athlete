import XCTest

@testable import Omi_Computer

final class ConversationSpeechSegmentationTests: XCTestCase {
  func testPrerollAndEightHundredMillisecondsOfSilenceProduceOneUtterance() {
    var segmenter = ConversationSpeechSegmentation()
    let frame = Data(repeating: 1, count: 1024)
    for _ in 0..<30 { XCTAssertTrue(segmenter.consume(frame, probability: 0).isEmpty) }
    XCTAssertTrue(segmenter.consume(frame, probability: 0.9).isEmpty)
    XCTAssertTrue(segmenter.consume(frame, probability: 0.9).isEmpty)
    guard case .began? = segmenter.consume(frame, probability: 0.9).first else {
      return XCTFail("Reliable speech onset must interrupt playback")
    }
    for _ in 0..<24 { XCTAssertTrue(segmenter.consume(frame, probability: 0).isEmpty) }
    guard case .ended(let pcm)? = segmenter.consume(frame, probability: 0).first else {
      return XCTFail("800 ms of trailing silence must finish the utterance")
    }
    XCTAssertEqual(pcm.count, 16_000 + 25 * 1024)
    XCTAssertFalse(segmenter.speaking)
    XCTAssertTrue(segmenter.consume(frame, probability: 0).isEmpty)
  }
}
