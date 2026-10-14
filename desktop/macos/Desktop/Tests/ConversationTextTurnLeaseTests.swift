import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationTextTurnLeaseTests: XCTestCase {
  func testTypedOwnerBlocksCompetingAdmissionUntilItsOwnFinalizer() async {
    let lease = ConversationTextTurnLease()
    XCTAssertTrue(lease.begin(turnID: "first", conversationID: nil))
    XCTAssertFalse(lease.begin(turnID: "competing", conversationID: "other"))
    XCTAssertTrue(lease.isActive, "Proactive voice must defer while typed generation owns the conversation")
    XCTAssertFalse(lease.finish(turnID: "stale"))
    let released = expectation(description: "Released")
    let waiter = Task {
      await lease.waitUntilReleased()
      released.fulfill()
    }
    await Task.yield()
    XCTAssertTrue(lease.finish(turnID: "first"))
    await fulfillment(of: [released], timeout: 1)
    await waiter.value
    XCTAssertTrue(lease.begin(turnID: "next", conversationID: "shared"))
  }

  func testOnlyCurrentTypedTurnAdvancesSupervisorRevisions() {
    let lease = ConversationTextTurnLease()
    XCTAssertTrue(lease.begin(turnID: "first", conversationID: nil))
    XCTAssertTrue(lease.bind(turnID: "first", conversationID: "pinned"))
    XCTAssertEqual(lease.conversationID, "pinned")
    XCTAssertEqual(lease.nextRevision(turnID: "first"), 1)
    XCTAssertEqual(lease.nextRevision(turnID: "first"), 2)
    XCTAssertNil(lease.nextRevision(turnID: "stale"))
    lease.finish(turnID: "first")
    XCTAssertTrue(lease.begin(turnID: "second", conversationID: "pinned"))
    XCTAssertNil(lease.nextRevision(turnID: "first"))
    XCTAssertEqual(lease.nextRevision(turnID: "second"), 1)
  }
  func testIdleConversationStillDefersProactiveVoiceUntilExplicitClosure() {
    let lease = ConversationTextTurnLease()
    XCTAssertTrue(lease.begin(turnID: "first", conversationID: "pinned"))
    XCTAssertTrue(lease.finish(turnID: "first"))
    XCTAssertFalse(lease.isActive)
    XCTAssertTrue(lease.hasConversation, "An answer ending does not end the conversation or permit competing voice")
    XCTAssertEqual(lease.conversationID, "pinned")
    XCTAssertTrue(lease.begin(turnID: "reply", conversationID: nil))
    XCTAssertEqual(lease.conversationID, "pinned", "The next safe request consumes queued private guidance")
    XCTAssertTrue(lease.finish(turnID: "reply"))
    lease.endConversation()
    XCTAssertFalse(lease.hasConversation)
  }

}
