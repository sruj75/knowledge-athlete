import XCTest

@testable import Omi_Computer

final class SettingsSearchContractTests: XCTestCase {
  func testSearchCatalogContainsNoRetiredExternalSurfaceEntries() {
    let settingIDs = Set(SettingsSearchItem.allSearchableItems.map(\.settingId))

    XCTAssertFalse(settingIDs.contains("aichat.browserextension"))
    XCTAssertFalse(settingIDs.contains("advanced.troubleshooting.rescanfiles"))
  }

  func testSearchCatalogRemovesRetiredEntriesAndPreservesAvailableDestinations() {
    let settingIDs = Set(SettingsSearchItem.allSearchableItems.map(\.settingId))

    let retiredSettingIDs: Set<String> = [
      "general.rewind",
      "general.askomi",
      "general.resetwindow",
      "rewind.rewind",
      "rewind.screencapture",
      "rewind.audiorecording",
      "transcription.settings",
    ]
    XCTAssertTrue(retiredSettingIDs.isDisjoint(with: settingIDs))

    let availableSettingIDs: Set<String> = [
      "general.systemaudio",
      "general.notifications",
      "general.fontsize",
      "rewind.storage",
      "rewind.excludedapps",
      "rewind.battery",
      "rewind.retention",
      "transcription.languagemode",
      "transcription.voicelanguages",
      "transcription.vocabulary",
      "transcription.vadgate",
      "floatingbar.show",
      "privacy.storerecordings",
      "privacy.cloudsync",
    ]
    XCTAssertTrue(availableSettingIDs.isSubset(of: settingIDs))
  }
}
