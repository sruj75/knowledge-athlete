import XCTest

@testable import Omi_Computer

final class DesktopAutomationNavigationContractTests: XCTestCase {
  func testEverySupportedTargetUsesTheProductionNavigationResolution() throws {
    let targets = [
      "dashboard", "home", "chat", "conversations", "memories", "tasks", "focus", "insight",
      "insights", "rewind", "settings", "permissions",
    ]

    for target in targets {
      let route = try request(target: target).validatedRoute()
      XCTAssertEqual(
        route.resolution,
        DesktopNavigationPolicy.resolveAutomationTarget(target),
        "\(target) must use the production navigation policy"
      )
    }

    let chat = try request(target: "chat").validatedRoute()
    XCTAssertEqual(chat.resolution.destination, .home)
    XCTAssertEqual(chat.resolution.effect, .openHomeChat)
  }

  func testDeletedRawAndUnknownTargetsFailBeforeDispatch() {
    for target in ["2", "6", "8", "apps", "brain-map", "unknown"] {
      XCTAssertThrowsError(try request(target: target).validatedRoute()) { error in
        XCTAssertEqual(error as? DesktopAutomationNavigationError, .unsupportedTarget(target))
      }
    }
  }

  func testSettingsSectionAndDestinationMustResolveToMountedTypedOwners() throws {
    let privacy = try request(
      target: "settings",
      settingsSection: "privacy",
      highlightedSettingId: SettingsDestination.localData.rawValue
    ).validatedRoute()
    XCTAssertEqual(privacy.settingsSection, .privacy)
    XCTAssertEqual(privacy.highlightedSetting, .localData)

    let inferred = try request(
      target: "settings",
      highlightedSettingId: SettingsDestination.askMode.rawValue
    ).validatedRoute()
    XCTAssertEqual(inferred.settingsSection, .advanced)
    XCTAssertEqual(inferred.highlightedSetting, .askMode)

    XCTAssertThrowsError(
      try request(target: "settings", settingsSection: "deleted-section").validatedRoute()
    ) { error in
      XCTAssertEqual(
        error as? DesktopAutomationNavigationError,
        .unsupportedSettingsSection("deleted-section"))
    }
    XCTAssertThrowsError(
      try request(target: "settings", highlightedSettingId: "advanced.deleted").validatedRoute()
    ) { error in
      XCTAssertEqual(
        error as? DesktopAutomationNavigationError,
        .unsupportedSettingsDestination("advanced.deleted"))
    }
    XCTAssertThrowsError(
      try request(
        target: "settings", settingsSection: "General",
        highlightedSettingId: SettingsDestination.askMode.rawValue
      ).validatedRoute()
    )
  }

  func testSettingsArgumentsCannotBeSmuggledOntoAnotherScreen() {
    XCTAssertThrowsError(
      try request(target: "home", settingsSection: "Advanced").validatedRoute()
    )
    XCTAssertThrowsError(
      try request(
        target: "tasks", highlightedSettingId: SettingsDestination.askMode.rawValue
      ).validatedRoute()
    )
  }

  private func request(
    target: String,
    settingsSection: String? = nil,
    highlightedSettingId: String? = nil
  ) -> DesktopAutomationNavigationRequest {
    DesktopAutomationNavigationRequest(
      target: target,
      settingsSection: settingsSection,
      highlightedSettingId: highlightedSettingId,
      activateApp: false,
      settleMs: 0
    )
  }
}
