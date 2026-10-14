import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationOpeningRequestTests: XCTestCase {
  func testCompletedOpeningDoesNotConsumeTheNextCloseToggle() async {
    let request = ConversationOpeningRequest()
    let lease = ConversationTextTurnLease()
    _ = lease.begin(turnID: "typed", conversationID: "shared")
    let opened = expectation(description: "Opened after typed release")
    request.schedule(
      wait: { await lease.waitUntilReleased() },
      open: {
        XCTAssertFalse(request.isPending)
        opened.fulfill()
      })
    XCTAssertTrue(request.isPending)
    await Task.yield()
    lease.finish(turnID: "typed")
    await fulfillment(of: [opened], timeout: 1)
    XCTAssertFalse(request.cancel(), "Next shortcut must reach the open conversation's close branch")
  }

  func testCancelledOpeningCannotOpenAfterOldTypedTurnReleases() async {
    let request = ConversationOpeningRequest()
    let lease = ConversationTextTurnLease()
    _ = lease.begin(turnID: "typed", conversationID: "shared")
    var openings = 0
    request.schedule(wait: { await lease.waitUntilReleased() }, open: { openings += 1 })
    await Task.yield()
    XCTAssertTrue(request.cancel())
    lease.finish(turnID: "typed")
    await Task.yield()
    XCTAssertEqual(openings, 0)
    XCTAssertFalse(request.isPending)
  }
}
