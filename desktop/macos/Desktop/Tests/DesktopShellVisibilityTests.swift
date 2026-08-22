import XCTest

@testable import Omi_Computer

final class DesktopShellVisibilityTests: XCTestCase {
  func testPrimaryShellAlwaysExposesTheFourRetainedDestinations() {
    XCTAssertEqual(
      DesktopNavigationPolicy.primaryDestinations,
      [.home, .memory, .tasks, .insights]
    )
  }

  func testDeletedRawDestinationsCannotBecomeVisible() {
    let retained = Set(DesktopNavigationPolicy.primaryDestinations.map(\.rawValue))
    XCTAssertTrue(retained.isDisjoint(with: [2, 6, 8]))
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 2))
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 6))
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 8))
  }
}
