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

  func testRetainedTopBarExposesPermissionRecoveryOnlyWhenItIsNeededOrActive() {
    XCTAssertTrue(
      DesktopNavigationPolicy.showsTopBar(
        forRawValue: DesktopDestination.permissions.rawValue),
      "permission recovery must retain the production top-bar exit")
    XCTAssertEqual(
      DesktopUtilityNavigation.permissionRecoveryDestination(
        hasMissingPermissions: true,
        selectedIndex: DesktopDestination.home.rawValue),
      .permissions)
    XCTAssertNil(
      DesktopUtilityNavigation.permissionRecoveryDestination(
        hasMissingPermissions: false,
        selectedIndex: DesktopDestination.home.rawValue))
    XCTAssertEqual(
      DesktopUtilityNavigation.permissionRecoveryDestination(
        hasMissingPermissions: false,
        selectedIndex: DesktopDestination.permissions.rawValue),
      .permissions,
      "the recovery page must retain a top-bar exit after permissions become healthy")
  }
}
