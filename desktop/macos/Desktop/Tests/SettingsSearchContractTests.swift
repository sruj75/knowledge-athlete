import XCTest

@testable import Omi_Computer

final class SettingsSearchContractTests: XCTestCase {
  func testSearchCatalogContainsNoRetiredExternalSurfaceEntries() {
    let settingIDs = Set(SettingsSearchItem.allSearchableItems.map(\.settingId))

    XCTAssertFalse(settingIDs.contains("aichat.browserextension"))
    XCTAssertFalse(settingIDs.contains("advanced.troubleshooting.rescanfiles"))
  }
}
