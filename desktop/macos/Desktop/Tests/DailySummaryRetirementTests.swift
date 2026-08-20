import XCTest

@testable import Omi_Computer

final class DailySummaryRetirementTests: XCTestCase {
  func testSettingsSearchRetainsNotificationControlsWithoutDailySummaryProduct() {
    let items = SettingsSearchItem.allSearchableItems
    let notificationIDs = Set(
      items.filter { $0.section == .notifications }.map(\.settingId))

    XCTAssertTrue(notificationIDs.contains("notifications.settings"))
    XCTAssertTrue(notificationIDs.contains("notifications.frequency"))
    XCTAssertTrue(notificationIDs.contains("notifications.focus"))
    XCTAssertTrue(notificationIDs.contains("notifications.task"))
    XCTAssertTrue(notificationIDs.contains("notifications.insight"))
    XCTAssertTrue(notificationIDs.contains("notifications.memory"))

    XCTAssertFalse(items.contains { $0.name == "Daily Summary" })
    XCTAssertFalse(items.contains { $0.name == "Summary Time" })
    XCTAssertFalse(items.contains { $0.settingId.contains("daily") })
  }
}
