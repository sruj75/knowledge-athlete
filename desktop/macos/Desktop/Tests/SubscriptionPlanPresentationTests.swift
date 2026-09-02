import XCTest

@testable import Omi_Computer

final class SubscriptionPlanPresentationTests: XCTestCase {
  func testLoadingDetailDoesNotClaimARetiredBillingIdentity() {
    XCTAssertEqual(SubscriptionPlanPresentation.loadingDetail, "Fetching subscription details...")
  }

  func testSelectionLabelIncludesTheStartingPrice() {
    XCTAssertEqual(
      SubscriptionPlanPresentation.selectionLabel(
        planTitle: "Focused", startingPrice: "$49.00/month"),
      "Select Focused · $49.00/month"
    )
  }

  func testSelectionLabelOmitsTheSeparatorWhenNoPriceIsAvailable() {
    XCTAssertEqual(
      SubscriptionPlanPresentation.selectionLabel(planTitle: "Focused", startingPrice: nil),
      "Select Focused"
    )
  }
}
