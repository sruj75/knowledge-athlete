import XCTest

@testable import Omi_Computer

final class ConversationPendingAudioTests: XCTestCase {
  func testOverflowRejectsTheWholeLivePrefixSoFallbackCanUseCompleteUtterance() {
    var audio = ConversationPendingAudio(maximumBytes: 6)
    XCTAssertTrue(audio.append(Data([1, 2, 3, 4])))
    XCTAssertFalse(audio.append(Data([5, 6, 7])))
    XCTAssertNil(audio.take(), "Never send a silently truncated Live utterance")
    XCTAssertFalse(audio.append(Data([8])), "Overflow stays terminal until the next connection")
    audio.reset()
    XCTAssertTrue(audio.append(Data([9, 10])))
    XCTAssertEqual(audio.take(), Data([9, 10]))
  }
}
