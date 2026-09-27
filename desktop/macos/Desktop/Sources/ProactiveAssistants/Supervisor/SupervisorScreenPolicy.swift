import Foundation

enum SupervisorScreenPolicy {
  static let excludedUtilityApps: Set<String> = [
    "Intentive",
    "Intentive Beta",
    "Intentive Dev",
    "Finder",
    "System Preferences",
    "System Settings",
    "Music",
    "Spotify",
    "Photos",
    "Preview",
    "Calculator",
    "QuickTime Player",
    "Activity Monitor",
    "Disk Utility",
    "Font Book",
    "Archive Utility",
    "Installer",
    "Screenshot",
  ]

  static func isAppExcluded(_ appName: String) -> Bool {
    excludedUtilityApps.contains(appName) || RewindSettings.shared.isAppExcluded(appName)
  }
}
