import XCTest

@testable import Omi_Computer

final class DesktopSentryConfigurationTests: XCTestCase {
  func testRuntimeEventsAndDebugSymbolsUseTheOwnedMacProject() throws {
    XCTAssertEqual(DesktopSentryConfiguration.organizationSlug, "heyintentive")
    XCTAssertEqual(DesktopSentryConfiguration.projectSlug, "desktop-macos")

    let dsn = try XCTUnwrap(URL(string: DesktopSentryConfiguration.dsn))
    XCTAssertEqual(dsn.scheme, "https")
    XCTAssertEqual(dsn.host, "o4511576350326784.ingest.us.sentry.io")
    XCTAssertEqual(dsn.path, "/4511981568458752")
  }
}
