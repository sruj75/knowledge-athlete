import XCTest

@testable import Omi_Computer

@MainActor
final class AssistantSettingsLocalAuthorityTests: XCTestCase {
  func testAssistantTogglesPersistLocallyAndReconcileImmediately() {
    let shared = AssistantSettings.shared
    let focus = FocusAssistantSettings.shared
    let task = TaskAssistantSettings.shared
    let insight = InsightAssistantSettings.shared
    let memory = MemoryAssistantSettings.shared
    let suggestions = SuggestionAssistantSettings.shared

    let previous = (
      shared.screenAnalysisEnabled,
      focus.isEnabled,
      focus.notificationsEnabled,
      task.isEnabled,
      task.notificationsEnabled,
      insight.isEnabled,
      insight.notificationsEnabled,
      memory.isEnabled,
      memory.notificationsEnabled,
      suggestions.isEnabled
    )
    defer {
      shared.screenAnalysisEnabled = previous.0
      focus.isEnabled = previous.1
      focus.notificationsEnabled = previous.2
      task.isEnabled = previous.3
      task.notificationsEnabled = previous.4
      insight.isEnabled = previous.5
      insight.notificationsEnabled = previous.6
      memory.isEnabled = previous.7
      memory.notificationsEnabled = previous.8
      suggestions.isEnabled = previous.9
    }

    let changed = expectation(description: "local settings reconciliation")
    changed.expectedFulfillmentCount = 10
    let observer = NotificationCenter.default.addObserver(
      forName: .assistantSettingsDidChange, object: nil, queue: nil
    ) { _ in changed.fulfill() }
    defer { NotificationCenter.default.removeObserver(observer) }

    shared.screenAnalysisEnabled = false
    focus.isEnabled = false
    focus.notificationsEnabled = false
    task.isEnabled = false
    task.notificationsEnabled = false
    insight.isEnabled = false
    insight.notificationsEnabled = false
    memory.isEnabled = false
    memory.notificationsEnabled = false
    suggestions.isEnabled = false

    XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 0), .completed)
    XCTAssertFalse(AssistantSettings.shared.screenAnalysisEnabled)
    XCTAssertFalse(FocusAssistantSettings.shared.isEnabled)
    XCTAssertFalse(FocusAssistantSettings.shared.notificationsEnabled)
    XCTAssertFalse(TaskAssistantSettings.shared.isEnabled)
    XCTAssertFalse(TaskAssistantSettings.shared.notificationsEnabled)
    XCTAssertFalse(InsightAssistantSettings.shared.isEnabled)
    XCTAssertFalse(InsightAssistantSettings.shared.notificationsEnabled)
    XCTAssertFalse(MemoryAssistantSettings.shared.isEnabled)
    XCTAssertFalse(MemoryAssistantSettings.shared.notificationsEnabled)
    XCTAssertFalse(SuggestionAssistantSettings.shared.isEnabled)
  }

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

  func testLocalNotificationTogglesPreserveExistingDiscoverySemantics() {
    XCTAssertTrue(TaskAssistant.discoveryEnabled(settingsEnabled: true, notificationsEnabled: false))
    XCTAssertFalse(TaskAssistant.discoveryEnabled(settingsEnabled: false, notificationsEnabled: true))
    XCTAssertTrue(MemoryAssistant.discoveryEnabled(settingsEnabled: true, notificationsEnabled: true))
    XCTAssertFalse(MemoryAssistant.discoveryEnabled(settingsEnabled: true, notificationsEnabled: false))
  }
}
