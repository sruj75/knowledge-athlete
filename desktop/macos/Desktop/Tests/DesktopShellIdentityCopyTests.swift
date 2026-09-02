import XCTest

@testable import Omi_Computer

final class DesktopShellIdentityCopyTests: XCTestCase {
  func testShellCopyUsesIntentiveAndOnlyClaimsAvailableLocalContext() {
    XCTAssertEqual(DesktopShellIdentityCopy.productName, "Intentive")
    XCTAssertEqual(DesktopShellIdentityCopy.chatWelcomeTitle, "Intentive")
    XCTAssertEqual(
      DesktopShellIdentityCopy.chatWelcomeDetail,
      "Can use your local memories and conversations when available.")
    XCTAssertEqual(DesktopShellIdentityCopy.askAnything, "Ask Intentive anything")
    XCTAssertEqual(DesktopShellIdentityCopy.openChat, "Open Intentive chat")
    XCTAssertEqual(DesktopShellIdentityCopy.openApp, "Open Intentive")
    XCTAssertEqual(DesktopShellIdentityCopy.continueInApp, "Continue in Intentive")
    XCTAssertEqual(DesktopShellIdentityCopy.rewindMenuAccessibility, "Intentive Rewind")

    XCTAssertFalse(DesktopShellIdentityCopy.allText.joined(separator: " ").contains("Omi"))
  }

  func testExactMemoryCopyRemainsUnchanged() {
    XCTAssertEqual(MemoryPageCopy.subtitle, "Memories and insights saved on this Mac.")
    XCTAssertEqual(
      MemoryPageCopy.emptyStateDetail,
      "Memories you add and insights learned from your conversations and activity will appear here.")
  }

  func testWindowOwnershipRecognizesFinalIdentityAndTheNamedTestBundleConvention() {
    XCTAssertTrue(DesktopShellIdentityCopy.isProductWindowTitle("Intentive"))
    XCTAssertTrue(DesktopShellIdentityCopy.isProductWindowTitle("Intentive Beta"))
    XCTAssertTrue(DesktopShellIdentityCopy.isProductWindowTitle("omi-wave6-s30 v1.0"))
    XCTAssertFalse(DesktopShellIdentityCopy.isProductWindowTitle("Omi"))
    XCTAssertFalse(DesktopShellIdentityCopy.isProductWindowTitle("Another app"))
  }
}
