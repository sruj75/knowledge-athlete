import XCTest

@testable import Omi_Computer

final class SubscriptionInfoDecoderTests: XCTestCase {
  func testDecodesNormalizedBoundedSubscription() throws {
    let json = """
      {
        "plan": "bounded",
        "plan_name": "Synthetic plan",
        "offer_id": "synthetic-monthly",
        "billing_customer_id": "customer-synthetic",
        "billing_subscription_id": "subscription-synthetic",
        "billing_product_id": "product-synthetic",
        "entitlement_policy": "bounded",
        "status": "active",
        "current_period_start": 1700000000,
        "current_period_end": 1702592000,
        "cancel_at_next_billing_date": true,
        "billing_interval": "month",
        "price_string": "$8/month",
        "provider_updated_at": 1699999999,
        "features": ["managed_chat"],
        "limits": {
          "transcription_seconds": null,
          "words_transcribed": null,
          "insights_gained": null,
          "chat_questions_per_month": 8,
          "chat_cost_usd_per_month": null
        }
      }
      """

    let info = try JSONDecoder().decode(UserSubscriptionInfo.self, from: Data(json.utf8))

    XCTAssertEqual(info.plan, .bounded)
    XCTAssertEqual(info.planName, "Synthetic plan")
    XCTAssertEqual(info.offerId, "synthetic-monthly")
    XCTAssertEqual(info.billingSubscriptionId, "subscription-synthetic")
    XCTAssertEqual(info.entitlementPolicy, .bounded)
    XCTAssertEqual(info.status, .active)
    XCTAssertTrue(info.cancelAtNextBillingDate)
    XCTAssertEqual(info.billingInterval, "month")
  }

  func testDecodesTerminalProviderStatusesWithoutLegacyFallback() throws {
    for status in ["on_hold", "cancelled", "failed", "expired", "inactive"] {
      let json = """
        {
          "plan": "free",
          "plan_name": "Free",
          "entitlement_policy": "bounded",
          "status": "\(status)",
          "features": [],
          "cancel_at_next_billing_date": false,
          "limits": {}
        }
        """
      XCTAssertNoThrow(try JSONDecoder().decode(UserSubscriptionInfo.self, from: Data(json.utf8)))
    }
  }
}
