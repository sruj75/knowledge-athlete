import Foundation

struct DesktopAutomationNavigationRequest: Codable {
  let target: String
  let settingsSection: String?
  let highlightedSettingId: String?
  let activateApp: Bool?
  let settleMs: Int?

  func validatedRoute() throws -> DesktopAutomationNavigationRoute {
    guard let resolution = DesktopNavigationPolicy.resolveAutomationTarget(target) else {
      throw DesktopAutomationNavigationError.unsupportedTarget(target)
    }

    var resolvedSection: SettingsContentView.SettingsSection?
    if let settingsSection {
      guard resolution.destination == .settings,
        let section = SettingsContentView.SettingsSection.automationMatch(settingsSection)
      else {
        throw DesktopAutomationNavigationError.unsupportedSettingsSection(settingsSection)
      }
      resolvedSection = section
    }

    var resolvedSetting: SettingsDestination?
    if let highlightedSettingId {
      guard resolution.destination == .settings,
        let destination = SettingsDestination(rawValue: highlightedSettingId)
      else {
        throw DesktopAutomationNavigationError.unsupportedSettingsDestination(
          highlightedSettingId)
      }
      if let resolvedSection, resolvedSection.sidebarItem != destination.section.sidebarItem {
        throw DesktopAutomationNavigationError.settingsDestinationSectionMismatch(
          destination: highlightedSettingId,
          section: resolvedSection.rawValue)
      }
      resolvedSetting = destination
      resolvedSection = resolvedSection ?? destination.section
    }

    return DesktopAutomationNavigationRoute(
      resolution: resolution,
      settingsSection: resolvedSection,
      highlightedSetting: resolvedSetting)
  }
}

struct DesktopAutomationNavigationRoute: Equatable {
  let resolution: DesktopNavigationResolution
  let settingsSection: SettingsContentView.SettingsSection?
  let highlightedSetting: SettingsDestination?
}

enum DesktopAutomationNavigationError: LocalizedError, Equatable {
  case unsupportedTarget(String)
  case unsupportedSettingsSection(String)
  case unsupportedSettingsDestination(String)
  case settingsDestinationSectionMismatch(destination: String, section: String)

  var errorDescription: String? {
    switch self {
    case .unsupportedTarget(let target):
      return "unsupported navigation target '\(target)'"
    case .unsupportedSettingsSection(let section):
      return "unsupported settings section '\(section)'"
    case .unsupportedSettingsDestination(let destination):
      return "unsupported settings destination '\(destination)'"
    case .settingsDestinationSectionMismatch(let destination, let section):
      return "settings destination '\(destination)' is not in section '\(section)'"
    }
  }
}
