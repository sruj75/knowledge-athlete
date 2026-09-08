import Darwin
import Foundation
import OmiSupport

enum DesktopAutomationLaunchOptions {
  static let enableFlag = "--automation-bridge"
  static let portPrefix = "--automation-port="
  static let ownershipTokenPrefix = "--omi-launch-token="
  static let captureRootPrefix = "--automation-capture-root="
  static let defaultPort: UInt16 = 47777
  static let tokenEnvironmentKey = "OMI_AUTOMATION_TOKEN"
  static let tokenFileEnvironmentKey = "OMI_AUTOMATION_TOKEN_FILE"

  private static let generatedToken =
    "heyintentive_auto_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"

  static var isEnabled: Bool {
    isEnabled(
      allowsLocalAutomation: AppBuild.allowsLocalAutomation,
      arguments: CommandLine.arguments,
      environment: ProcessInfo.processInfo.environment
    )
  }

  static func isEnabled(
    allowsLocalAutomation: Bool,
    arguments: [String],
    environment: [String: String]
  ) -> Bool {
    guard allowsLocalAutomation else {
      return false
    }
    // Explicit opt-out always wins, so a dev build can be run "clean" if needed.
    if environment["OMI_DISABLE_LOCAL_AUTOMATION"] == "1" {
      return false
    }
    // Auto-enable on local bundles (Intentive Dev + every `omi-*` named test bundle) so agents
    // can drive the app without remembering a launch flag. Published previews are excluded
    // by `allowsLocalAutomation` above even if their process environment is contaminated.
    return arguments.contains(enableFlag)
      || environment["OMI_ENABLE_LOCAL_AUTOMATION"] == "1"
      || allowsLocalAutomation
  }

  static var port: UInt16 {
    for argument in CommandLine.arguments {
      guard argument.hasPrefix(portPrefix) else { continue }
      let rawValue = String(argument.dropFirst(portPrefix.count))
      if let parsed = UInt16(rawValue) {
        return parsed
      }
    }

    if let rawValue = ProcessInfo.processInfo.environment["OMI_AUTOMATION_PORT"],
      let parsed = UInt16(rawValue)
    {
      return parsed
    }

    return defaultPort
  }

  static var ownershipToken: String? {
    ownershipToken(arguments: CommandLine.arguments)
  }

  static func ownershipToken(arguments: [String]) -> String? {
    let candidates = arguments.compactMap { argument -> String? in
      guard argument.hasPrefix(ownershipTokenPrefix) else { return nil }
      return String(argument.dropFirst(ownershipTokenPrefix.count))
    }
    guard candidates.count == 1 else { return nil }
    return validatedOwnershipToken(candidates[0])
  }

  static func validatedOwnershipToken(_ rawValue: String?) -> String? {
    guard let rawValue, (16...128).contains(rawValue.utf8.count) else { return nil }
    guard
      rawValue.utf8.allSatisfy({ byte in
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57)
          || byte == 95 || byte == 45
      })
    else { return nil }
    return rawValue
  }

  static var token: String {
    let env = ProcessInfo.processInfo.environment[tokenEnvironmentKey] ?? ""
    let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? generatedToken : trimmed
  }

  static var tokenFileURL: URL {
    if let rawValue = ProcessInfo.processInfo.environment[tokenFileEnvironmentKey],
      !rawValue.isEmpty
    {
      return URL(fileURLWithPath: rawValue).standardizedFileURL
    }
    return URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("\(DesktopProductIdentity.automationTokenPrefix)-\(port).token")
      .standardizedFileURL
  }

  static func writeTokenFileIfNeeded() {
    guard isEnabled else { return }
    let url = tokenFileURL
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try token.write(to: url, atomically: true, encoding: .utf8)
      chmod(url.path, S_IRUSR | S_IWUSR)
    } catch {
      logError("DesktopAutomationBridge: failed to write automation token file", error: error)
    }
  }

  static var captureRoot: URL {
    for argument in CommandLine.arguments {
      guard argument.hasPrefix(captureRootPrefix) else { continue }
      let rawValue = String(argument.dropFirst(captureRootPrefix.count))
      if !rawValue.isEmpty {
        return URL(fileURLWithPath: rawValue).standardizedFileURL
      }
    }

    if let rawValue = ProcessInfo.processInfo.environment["OMI_AUTOMATION_CAPTURE_ROOT"],
      !rawValue.isEmpty
    {
      return URL(fileURLWithPath: rawValue).standardizedFileURL
    }

    return URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("omi-harness", isDirectory: true)
      .standardizedFileURL
  }
}
