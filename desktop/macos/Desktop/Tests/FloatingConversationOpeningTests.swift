import XCTest

@testable import Omi_Computer

final class FloatingConversationOpeningTests: XCTestCase {
  func testExplicitHideEndsAnOpenConversationBeforeRemovingItsSurface() {
    var events: [String] = []
    FloatingConversationDismissal.perform(
      isConversationOpen: true,
      closeConversation: { events.append("end") }, hideSurface: { events.append("hide") })
    XCTAssertEqual(events, ["end", "hide"])
    events = []
    FloatingConversationDismissal.perform(
      isConversationOpen: false,
      closeConversation: { events.append("end") }, hideSurface: { events.append("hide") })
    XCTAssertEqual(events, ["hide"])
  }

  func testSnoozeBlocksProactiveOpeningButAllowsTheUserToTalk() {
    var events: [String] = []
    XCTAssertFalse(
      FloatingConversationOpening.present(
        request: .background, isSnoozed: true, cancelPendingDismiss: {},
        reveal: { events.append("reveal") },
        openConversation: { events.append("conversation") }))
    XCTAssertEqual(events, [])
    XCTAssertTrue(
      FloatingConversationOpening.present(
        request: .explicitUserAction, isSnoozed: true, cancelPendingDismiss: {},
        reveal: { events.append("reveal") },
        openConversation: { events.append("conversation") }))
    XCTAssertEqual(events, ["reveal", "conversation"])
  }

  func testShortcutAndSupervisorRevealBeforeOpeningTheSameConversationSurface() {
    for request: FloatingBarPresentationRequest in [.explicitUserAction, .background] {
      var events: [String] = []
      let opened = FloatingConversationOpening.present(
        request: request, isSnoozed: false,
        cancelPendingDismiss: { events.append("cancelDismiss") },
        reveal: { events.append("reveal") },
        openConversation: { events.append("conversation") })
      XCTAssertTrue(opened)
      XCTAssertEqual(events, ["cancelDismiss", "reveal", "conversation"])
    }
  }
}
