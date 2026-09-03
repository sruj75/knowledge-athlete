import XCTest

@testable import Omi_Computer

final class ChatPromptsTests: XCTestCase {
  func testExplicitScreenShareRequestUsesCanonicalScreenRecordingPermissionTool() {
    let desktopPrompt = ChatPromptBuilder.buildDesktopChat(userName: "Taylor")

    XCTAssertTrue(
      desktopPrompt.contains("screen share, screen sharing, and screen-share as the screen_recording permission"))
    XCTAssertTrue(desktopPrompt.contains("use request_permission immediately"))
    XCTAssertTrue(DesktopCapabilityRegistry.realtimeSelfModelPrompt.contains("screen share"))
    XCTAssertTrue(DesktopCapabilityRegistry.realtimeSelfModelPrompt.contains("screen_recording"))
    XCTAssertTrue(
      DesktopCapabilityRegistry.realtimeSelfModelPrompt.contains(
        "explicitly say that Intentive needs Screen Recording permission"
      )
    )
    XCTAssertTrue(
      DesktopCapabilityRegistry.realtimeSelfModelPrompt.contains(
        "next-turn request such as \"request it\""
      )
    )
  }

}
