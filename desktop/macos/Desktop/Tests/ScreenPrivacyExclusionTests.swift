import XCTest

@testable import Omi_Computer

/// Verifies that Rewind privacy exclusions (password managers, keychains) are respected
/// by all proactive assistants — not just the Rewind indexer.
/// See: https://github.com/BasedHardware/omi/issues/7098
final class ScreenPrivacyExclusionTests: XCTestCase {

  // MARK: - Rewind default excluded apps include privacy-sensitive apps

  func testRewindDefaultsIncludePasswordManagers() {
    let defaults = RewindSettings.defaultExcludedApps
    let privacyApps = [
      "Passwords", "1Password", "1Password 7", "Bitwarden",
      "LastPass", "Dashlane", "Keeper", "Enpass",
      "KeePassXC", "Keychain Access",
    ]
    for app in privacyApps {
      XCTAssertTrue(defaults.contains(app), "RewindSettings.defaultExcludedApps must include '\(app)'")
    }
  }

  func testVisibleDefaultExclusionsUseIntentiveIdentityOnly() {
    let retiredProductNames = ["Omi", "Omi Beta", "omi", "Omi Dev", "Omi Computer"]

    for app in retiredProductNames {
      XCTAssertFalse(
        RewindSettings.defaultExcludedApps.contains(app),
        "Rewind defaults must not render the retired product name '\(app)'")
      XCTAssertFalse(
        SupervisorScreenPolicy.excludedUtilityApps.contains(app),
        "Assistant defaults must not render the retired product name '\(app)'")
    }

    for app in ["Intentive", "Intentive Beta", "Intentive Dev"] {
      XCTAssertTrue(RewindSettings.defaultExcludedApps.contains(app))
      XCTAssertTrue(SupervisorScreenPolicy.excludedUtilityApps.contains(app))
    }
  }

  func testSupervisorRespectsPrivacyAndUtilityExclusions() {
    for app in ["Passwords", "1Password", "Keychain Access", "Finder", "Calculator"] {
      XCTAssertTrue(SupervisorScreenPolicy.isAppExcluded(app))
    }
    XCTAssertFalse(SupervisorScreenPolicy.isAppExcluded("Safari"))
  }

  func testCustomRewindExclusionBlocksSupervisor() {
    let app = "PrivateApp-\(UUID().uuidString)"
    RewindSettings.shared.excludeApp(app)
    defer { RewindSettings.shared.includeApp(app) }
    XCTAssertTrue(SupervisorScreenPolicy.isAppExcluded(app))
  }

  // MARK: - RewindSettings.isAppExcluded covers all default privacy apps

  func testRewindSettingsExcludesAllDefaultPrivacyApps() {
    let privacyApps = [
      "Passwords", "1Password", "1Password 7", "Bitwarden",
      "LastPass", "Dashlane", "Keeper", "Enpass",
      "KeePassXC", "Keychain Access",
    ]
    for app in privacyApps {
      XCTAssertTrue(
        RewindSettings.shared.isAppExcluded(app),
        "RewindSettings.shared.isAppExcluded must return true for '\(app)'")
    }
  }
}
