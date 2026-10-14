import XCTest

@testable import Omi_Computer

final class ConversationNotchPresentationTests: XCTestCase {
  func testOpenConversationKeepsThinkingVisibleInItsNotchHeader() {
    XCTAssertTrue(
      NotchChromeLayout.showsThinking(
        isThinking: true, isResponseWaiting: true, isListening: false,
        showingAIConversation: true, conversationOpen: true))
    XCTAssertFalse(
      NotchChromeLayout.showsThinking(
        isThinking: true, isResponseWaiting: true, isListening: false,
        showingAIConversation: true, conversationOpen: false))
    XCTAssertFalse(
      NotchChromeLayout.showsThinking(
        isThinking: true, isResponseWaiting: true, isListening: true,
        showingAIConversation: true, conversationOpen: true))
  }
}
