import XCTest

@testable import Omi_Computer

@MainActor
final class BillingReconcilerTests: XCTestCase {
  func testMatchesExpectedOfferAfterBoundedReads() async {
    var reads = 0
    var sleeps = 0

    let outcome = await BillingReconciler.poll(
      read: {
        reads += 1
        return reads == 3 ? "expected-offer" : "other-offer"
      },
      matches: { $0 == "expected-offer" },
      sleep: { sleeps += 1 }
    )

    guard case .matched(let offer) = outcome else {
      return XCTFail("expected a matched offer")
    }
    XCTAssertEqual(offer, "expected-offer")
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(sleeps, 2)
  }

  func testTimesOutAfterExactlyEightReadsAndSevenWaits() async {
    var reads = 0
    var sleeps = 0

    let outcome = await BillingReconciler.poll(
      read: {
        reads += 1
        return "other-offer"
      },
      matches: { $0 == "expected-offer" },
      sleep: { sleeps += 1 }
    )

    guard case .timedOut(let last) = outcome else {
      return XCTFail("expected timeout")
    }
    XCTAssertEqual(last, "other-offer")
    XCTAssertEqual(reads, 8)
    XCTAssertEqual(sleeps, 7)
  }

  func testAllReadFailuresFailWithoutGrantingEntitlement() async {
    struct SyntheticFailure: Error {}
    var reads = 0

    let outcome: BillingReconciliationOutcome<String> = await BillingReconciler.poll(
      read: {
        reads += 1
        throw SyntheticFailure()
      },
      matches: { _ in true },
      sleep: {}
    )

    guard case .failed = outcome else {
      return XCTFail("expected failure")
    }
    XCTAssertEqual(reads, 8)
  }
}
