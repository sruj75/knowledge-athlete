import XCTest

@testable import Omi_Computer

final class ConversationListPresentationTests: XCTestCase {
  func testTrueEmptyAndFilteredEmptyUseDifferentProductCopy() {
    XCTAssertEqual(
      ConversationListEmptyPresentation.resolve(hasActiveFilters: false),
      ConversationListEmptyPresentation(
        title: "No Conversations",
        message: "Start recording to capture your first conversation"))
    XCTAssertEqual(
      ConversationListEmptyPresentation.resolve(hasActiveFilters: true),
      ConversationListEmptyPresentation(
        title: "No conversations found",
        message: "Try a different search term"))
  }

  func testSearchFailureCopyIsConnectionNeutral() {
    XCTAssertEqual(
      ConversationSearchPresentation.failureMessage,
      "Couldn't search conversations. Try again.")
  }

  func testLoadFailureCopyMatchesProductContract() {
    XCTAssertEqual(
      ConversationLoadPresentation.failureMessage,
      "Unable to load conversations. Try again.")
  }
}
