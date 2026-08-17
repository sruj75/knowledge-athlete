import XCTest

@testable import Omi_Computer

@MainActor
final class BillingWebFlowTests: XCTestCase {
  func testCompletionMatchingAcceptsOnlyExactConfiguredURL() {
    let success = URL(string: "https://billing.invalid/v1/payments/success")!

    XCTAssertTrue(BillingWebView.Coordinator.urlsMatchCompletion(success, completionURL: success))
    XCTAssertFalse(
      BillingWebView.Coordinator.urlsMatchCompletion(
        URL(string: "https://billing.invalid/v1/payments/success/extra")!,
        completionURL: success))
    XCTAssertFalse(
      BillingWebView.Coordinator.urlsMatchCompletion(
        URL(string: "https://billing.invalid/v1/payments/success?forged=1")!,
        completionURL: success))
    XCTAssertFalse(
      BillingWebView.Coordinator.urlsMatchCompletion(
        URL(string: "https://attacker.invalid/v1/payments/success")!,
        completionURL: success))
  }
}
