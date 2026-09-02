import XCTest

@testable import Omi_Computer

final class TelemetryIdentityContractTests: XCTestCase {
  func testExternallyMeaningfulTelemetryUsesIntentiveIdentity() {
    XCTAssertEqual(ProductTelemetryIdentity.floatingBarOpenedEvent, "floating_bar_ask_intentive_opened")
    XCTAssertEqual(ProductTelemetryIdentity.floatingBarClosedEvent, "floating_bar_ask_intentive_closed")
    XCTAssertEqual(ProductTelemetryIdentity.openProductAction, "open_intentive")
  }
}
