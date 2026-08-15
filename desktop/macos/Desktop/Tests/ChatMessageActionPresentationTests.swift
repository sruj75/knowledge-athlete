import XCTest

@testable import Omi_Computer

final class ChatMessageActionPresentationTests: XCTestCase {
  func testNormalAndFloatingAssistantActionsKeepCopyInfoAndTimestamp() {
    for surface in [AssistantMessageSurface.normalChat, .floatingChat] {
      XCTAssertEqual(
        ChatMessageActionPresentation.actions(
          for: surface,
          isStreaming: false,
          copyableText: "answer",
          hasMetadata: true
        ),
        [.copy, .info, .timestamp]
      )
    }
  }

  func testStreamingAssistantHasNoActionsUntilCopyableResponseCompletes() {
    XCTAssertEqual(
      ChatMessageActionPresentation.actions(
        for: .normalChat,
        isStreaming: true,
        copyableText: "partial",
        hasMetadata: true
      ),
      []
    )
  }
}
