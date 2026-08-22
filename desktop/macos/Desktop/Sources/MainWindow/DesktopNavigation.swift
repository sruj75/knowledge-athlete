import AppKit

enum DesktopDestination: Int, CaseIterable, Sendable {
  case home = 0
  case memory = 1
  case memories = 3
  case tasks = 4
  case insights = 5
  case rewind = 7
  case settings = 9
  case permissions = 10

  var title: String {
    switch self {
    case .home: return "Home"
    case .memory: return "Memory"
    case .memories: return "Memories"
    case .tasks: return "Tasks"
    case .insights: return "Insights"
    case .rewind: return "Rewind"
    case .settings: return "Settings"
    case .permissions: return "Permissions"
    }
  }

  var icon: String {
    switch self {
    case .home: return "house.fill"
    case .memory: return "brain"
    case .memories: return "brain.head.profile"
    case .tasks: return "checklist"
    case .insights: return "lightbulb.fill"
    case .rewind: return "clock.arrow.circlepath"
    case .settings: return "gearshape.fill"
    case .permissions: return "exclamationmark.triangle.fill"
    }
  }
}

enum DesktopNavigationEffect: Equatable, Sendable {
  case none
  case openHomeChat
  case selectMemory(MemoryHubDestination)
  case selectInsights(InsightsHubSegment)
}

struct DesktopNavigationResolution: Equatable, Sendable {
  let destination: DesktopDestination
  let effect: DesktopNavigationEffect
}

enum DesktopNavigationPolicy {
  static let primaryDestinations: [DesktopDestination] = [.home, .memory, .tasks, .insights]

  static func destination(forRawValue rawValue: Int) -> DesktopDestination? {
    DesktopDestination(rawValue: rawValue)
  }

  static func showsTopBar(forRawValue rawValue: Int) -> Bool {
    destination(forRawValue: rawValue) != nil
  }

  static func destination(forShortcut shortcut: String) -> DesktopDestination? {
    switch normalized(shortcut) {
    case "1", "home", "dashboard": return .home
    case "2", "memory", "memories": return .memories
    case "3", "tasks": return .tasks
    case "4", "insight", "insights": return .insights
    case ",", "comma", "settings": return .settings
    default: return nil
    }
  }

  static func resolveAutomationTarget(_ target: String) -> DesktopNavigationResolution? {
    switch normalized(target).replacingOccurrences(of: "-", with: "_") {
    case "dashboard", "home":
      return DesktopNavigationResolution(destination: .home, effect: .none)
    case "conversations":
      return DesktopNavigationResolution(destination: .memory, effect: .selectMemory(.conversations))
    case "chat":
      return DesktopNavigationResolution(destination: .home, effect: .openHomeChat)
    case "memories":
      return DesktopNavigationResolution(destination: .memory, effect: .selectMemory(.memories))
    case "tasks":
      return DesktopNavigationResolution(destination: .tasks, effect: .none)
    case "focus":
      return DesktopNavigationResolution(destination: .insights, effect: .selectInsights(.focus))
    case "insight", "insights":
      return DesktopNavigationResolution(destination: .insights, effect: .selectInsights(.insights))
    case "rewind":
      return DesktopNavigationResolution(destination: .rewind, effect: .none)
    case "settings":
      return DesktopNavigationResolution(destination: .settings, effect: .none)
    case "permissions":
      return DesktopNavigationResolution(destination: .permissions, effect: .none)
    default:
      return nil
    }
  }

  static func returnsHomeOnUnhandledEscape(from destination: DesktopDestination) -> Bool {
    [.memory, .memories, .tasks, .rewind].contains(destination)
  }

  static func isRewindShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
    keyCode == 15
      && modifiers.intersection(.deviceIndependentFlagsMask) == [.command, .option]
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
