import XCTest

@testable import Omi_Computer

@MainActor
final class AssistantSettingsLocalAuthorityTests: XCTestCase {
  func testNotificationMasterAndEveryFrequencyLevelSurviveReconstruction() throws {
    let suite = "AssistantSettingsLocalAuthorityTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertEqual(
      LocalNotificationSettings(defaults: defaults).snapshot(),
      LocalNotificationSettingsSnapshot(enabled: true, frequency: 0)
    )

    for frequency in 0...5 {
      let written = LocalNotificationSettings(defaults: defaults).update(
        enabled: frequency.isMultiple(of: 2),
        frequency: frequency
      )
      let reconstructed = LocalNotificationSettings(defaults: defaults).snapshot()
      XCTAssertEqual(reconstructed, written)
      XCTAssertEqual(reconstructed.frequency, frequency)
      XCTAssertNotEqual(reconstructed.frequencyDescription, "Unknown")
    }

    XCTAssertEqual(LocalNotificationSettings(defaults: defaults).update(frequency: -4).frequency, 0)
    XCTAssertEqual(LocalNotificationSettings(defaults: defaults).update(frequency: 99).frequency, 5)
  }

}
