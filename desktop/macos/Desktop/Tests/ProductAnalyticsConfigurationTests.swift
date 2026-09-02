import XCTest

@testable import Omi_Computer

final class ProductAnalyticsConfigurationTests: XCTestCase {
  func testOwnedConfigurationResolvesFromTheExistingRuntimeEnvironment() throws {
    let configuration = try XCTUnwrap(
      ProductAnalyticsConfiguration.resolve(
        infoDictionary: [:],
        environment: [
          "POSTHOG_PROJECT_API_KEY": "owned-project-token",
          "POSTHOG_HOST": "https://us.i.posthog.com",
        ]))

    XCTAssertEqual(configuration.projectToken, "owned-project-token")
    XCTAssertEqual(configuration.host.absoluteString, "https://us.i.posthog.com")
  }

  func testMissingOrMalformedConfigurationFailsClosed() {
    XCTAssertNil(ProductAnalyticsConfiguration.resolve(infoDictionary: [:], environment: [:]))
    XCTAssertNil(
      ProductAnalyticsConfiguration.resolve(
        infoDictionary: [
          "IntentivePostHogProjectToken": "token",
          "IntentivePostHogHost": "http://us.i.posthog.com",
        ],
        environment: [:]))
    XCTAssertNil(
      ProductAnalyticsConfiguration.resolve(
        infoDictionary: [
          "IntentivePostHogProjectToken": "token",
          "IntentivePostHogHost": "https://user:password@us.i.posthog.com",
        ],
        environment: [:]))
  }

  func testPackagedConfigurationUsesIntentiveOwnedPlistKeys() throws {
    let configuration = try XCTUnwrap(
      ProductAnalyticsConfiguration.resolve(
        infoDictionary: [
          "IntentivePostHogProjectToken": "packaged-project-token",
          "IntentivePostHogHost": "https://eu.i.posthog.com",
        ],
        environment: [:]))

    XCTAssertEqual(configuration.projectToken, "packaged-project-token")
    XCTAssertEqual(configuration.host.absoluteString, "https://eu.i.posthog.com")
  }
}
