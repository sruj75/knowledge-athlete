import XCTest

@testable import Omi_Computer

final class DailySummaryRetirementTests: XCTestCase {
  func testSettingsSearchRetainsNotificationControlsWithoutDailySummaryProduct() {
    let items = SettingsSearchItem.allSearchableItems
    let notificationIDs = Set(
      items.filter { $0.section == .notifications }.map(\.settingId))

    XCTAssertTrue(notificationIDs.contains("notifications.settings"))
    XCTAssertTrue(notificationIDs.contains("notifications.frequency"))
    XCTAssertTrue(notificationIDs.contains("notifications.supervisor"))
    for retired in ["notifications.focus", "notifications.task", "notifications.insight", "notifications.memory"] {
      XCTAssertFalse(notificationIDs.contains(retired))
    }

    XCTAssertFalse(items.contains { $0.name == "Daily Summary" })
    XCTAssertFalse(items.contains { $0.name == "Summary Time" })
    XCTAssertFalse(items.contains { $0.settingId.contains("daily") })
  }
}
