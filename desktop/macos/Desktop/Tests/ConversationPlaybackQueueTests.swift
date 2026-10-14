import XCTest

@testable import Omi_Computer

final class ConversationPlaybackQueueTests: XCTestCase {
  func testLateInterruptedPlaybackCannotDrainNewAnswer() {
    var queue = ConversationPlaybackQueue()
    let old = queue.enqueue()
    queue.reset()
    let current = queue.enqueue()
    XCTAssertFalse(queue.seal())
    XCTAssertFalse(queue.played(old))
    XCTAssertTrue(queue.played(current))
    XCTAssertFalse(queue.played(current))
  }

  func testTemporaryGapInStreamingAudioDoesNotFinishAnswer() {
    var queue = ConversationPlaybackQueue()
    let first = queue.enqueue()
    XCTAssertFalse(queue.played(first))
    let second = queue.enqueue()
    XCTAssertFalse(queue.seal())
    XCTAssertTrue(queue.played(second))
  }
}
