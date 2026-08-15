import XCTest

@testable import Omi_Computer

@MainActor
final class ManagedAccessDecisionTests: XCTestCase {
  private let paywallKey = "desktop_isPaywalled"
  private let legacyCustomerKeyNames = [
    "dev_openai_api_key",
    "dev_anthropic_api_key",
    "dev_gemini_api_key",
    "dev_deepgram_api_key",
  ]

  override func tearDown() async throws {
    legacyCustomerKeyNames.forEach(UserDefaults.standard.removeObject(forKey:))
    UserDefaults.standard.removeObject(forKey: paywallKey)
  }

  func testLegacyCustomerKeysCannotOverrideManagedPaywallOrQuota() throws {
    for key in legacyCustomerKeyNames {
      UserDefaults.standard.set("legacy-customer-secret", forKey: key)
    }
    UserDefaults.standard.set(true, forKey: paywallKey)

    let limiter = FloatingBarUsageLimiter()
    limiter.applyQuota(try makeQuota(allowed: false))

    XCTAssertTrue(AppState.isPaywalledEffective)
    XCTAssertTrue(limiter.isLimitReached)
  }

  func testManagedEntitlementAllowsAccess() throws {
    UserDefaults.standard.set(false, forKey: paywallKey)

    let limiter = FloatingBarUsageLimiter()
    limiter.applyQuota(try makeQuota(allowed: true))

    XCTAssertFalse(AppState.isPaywalledEffective)
    XCTAssertFalse(limiter.isLimitReached)
  }

  private func makeQuota(allowed: Bool) throws -> APIClient.ChatUsageQuota {
    let data = try JSONSerialization.data(
      withJSONObject: [
        "plan": "Free",
        "plan_type": "basic",
        "unit": "questions",
        "used": allowed ? 0 : 30,
        "limit": 30,
        "percent": allowed ? 0 : 100,
        "allowed": allowed,
      ])
    return try JSONDecoder().decode(APIClient.ChatUsageQuota.self, from: data)
  }
}
