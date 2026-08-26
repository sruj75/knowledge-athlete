import Foundation

struct StartupSystemMaintenanceCommand: Equatable, Sendable {
  let label: String
  let executable: String
  let arguments: [String]
}

struct StartupSystemMaintenanceSink: Sendable {
  private let submitCommand: @Sendable (StartupSystemMaintenanceCommand) -> Void

  init(submitCommand: @escaping @Sendable (StartupSystemMaintenanceCommand) -> Void) {
    self.submitCommand = submitCommand
  }

  func submit(_ command: StartupSystemMaintenanceCommand) {
    submitCommand(command)
  }

  static let live = StartupSystemMaintenanceSink { command in
    SystemCommand.runLogging(
      command.label,
      executable: command.executable,
      arguments: command.arguments)
  }
}

/// System commands allowed during normal app startup.
///
/// Keep this list bundle-local. Launching Omi must not mutate shared macOS
/// services such as the Dock or icon cache agents.
enum StartupSystemMaintenancePolicy {
  static func run(
    bundlePath: String,
    sink: StartupSystemMaintenanceSink
  ) {
    for command in commands(bundlePath: bundlePath) {
      sink.submit(command)
    }
  }

  static func commands(bundlePath: String) -> [StartupSystemMaintenanceCommand] {
    [
      StartupSystemMaintenanceCommand(
        label: "AppDelegate: strip provenance xattrs",
        executable: "/usr/bin/xattr",
        arguments: ["-cr", bundlePath]
      )
    ]
  }
}
