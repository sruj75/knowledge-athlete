import XCTest

@testable import Omi_Computer

final class LegacyAppTakeoverIsolationTests: XCTestCase {
  func testStableStartupRequestsOnlyRetainedBundleLocalMaintenance() {
    let bundlePath = "/Applications/Target Product.app"

    let actions = StartupSystemMaintenancePolicy.actions(bundlePath: bundlePath)

    XCTAssertEqual(
      actions,
      [
        .systemCommand(
          StartupSystemMaintenanceCommand(
            label: "AppDelegate: strip provenance xattrs",
            executable: "/usr/bin/xattr",
            arguments: ["-cr", bundlePath]))
      ])
  }
}
