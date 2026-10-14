import XCTest

@testable import Omi_Computer

final class ConversationLifecycleTests: XCTestCase {
  func testOnlyAvailableListeningTimeCountsTowardSilence() {
    var conversation = ConversationLifecycle()
    conversation.open(id: "one", now: 0)
    conversation.connected(now: 10)
    XCTAssertFalse(conversation.silenceExpired(now: 69))
    conversation.setBusy(true, now: 40)
    XCTAssertFalse(conversation.silenceExpired(now: 1000))
    conversation.setBusy(false, now: 1000)
    XCTAssertFalse(conversation.silenceExpired(now: 1029))
    XCTAssertTrue(conversation.silenceExpired(now: 1030))
  }

  func testNewUserSpeechSupersedesOlderEndSignal() {
    var conversation = ConversationLifecycle()
    conversation.open(id: "one", now: 0)
    conversation.connected(now: 0)
    let first = conversation.userBeganSpeaking(now: 1)
    conversation.requestEnd(afterActivity: first)
    XCTAssertTrue(conversation.shouldEndAfterPlayback)
    _ = conversation.userBeganSpeaking(now: 2)
    XCTAssertFalse(conversation.shouldEndAfterPlayback)
  }

  func testFallbackPersistsUntilLogicalConversationCloses() {
    var conversation = ConversationLifecycle()
    conversation.open(id: "one", now: 0)
    conversation.useFallback(now: 2)
    conversation.connected(now: 3)
    XCTAssertEqual(conversation.route, .batch)
    let oldGeneration = conversation.generation
    conversation.close()
    conversation.open(id: "two", now: 4)
    XCTAssertEqual(conversation.route, .live)
    XCTAssertNotEqual(conversation.generation, oldGeneration)
    XCTAssertEqual(conversation.id, "two")
  }
}
