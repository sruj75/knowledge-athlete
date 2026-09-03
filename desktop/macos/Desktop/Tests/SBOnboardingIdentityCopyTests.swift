import XCTest

@testable import Omi_Computer

final class SBOnboardingIdentityCopyTests: XCTestCase {
  func testIdentityCopyNamesIntentiveWithoutAbsolutePrivacyPromises() {
    XCTAssertEqual(
      SBOnboardingIdentityCopy.promise,
      "Hey, I'm Intentive, your second brain. I help with conversations and activity you choose to capture. Three quick things:"
    )
    XCTAssertEqual(SBOnboardingIdentityCopy.howHeardQuestion, "Quick one. How did you hear about Intentive?")
    XCTAssertEqual(SBOnboardingIdentityCopy.typingStatus, "Intentive is typing…")
    XCTAssertEqual(SBOnboardingIdentityCopy.setupAction, "Set up Intentive →")
    XCTAssertEqual(SBOnboardingIdentityCopy.openSourceDetail, "View the project repository on GitHub.")
    XCTAssertEqual(
      SBOnboardingIdentityCopy.privateDataDetail,
      "Conversations and memories you keep are saved on this Mac.")
    XCTAssertEqual(SBOnboardingIdentityCopy.userControlDetail, "Choose when Intentive listens and what you keep.")

    let renderedCopy = SBOnboardingIdentityCopy.allText.joined(separator: " ")
    XCTAssertFalse(renderedCopy.contains("Omi"))
    XCTAssertFalse(renderedCopy.contains("remember everything"))
    XCTAssertFalse(renderedCopy.contains("only yours"))
    XCTAssertFalse(renderedCopy.contains("Delete anything, forever"))
  }

  func testRepositoryDestinationUsesTheApprovedOwner() {
    XCTAssertEqual(SBOnboardingRepository.url.absoluteString, "https://github.com/sruj75/knowledge-athlete")
  }
}
