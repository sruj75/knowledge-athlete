import XCTest

@testable import Omi_Computer

final class SBOnboardingRepositoryTests: XCTestCase {
  func testGitHubLinkUsesApprovedIntentiveRepository() {
    XCTAssertEqual(SBOnboardingRepository.url.absoluteString, "https://github.com/sruj75/knowledge-athlete")
  }
}
