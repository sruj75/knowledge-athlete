import Foundation
import XCTest

@testable import Omi_Computer

private final class StartupMaintenanceCommandRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var commands: [StartupSystemMaintenanceCommand] = []

  func record(_ command: StartupSystemMaintenanceCommand) {
    lock.lock()
    commands.append(command)
    lock.unlock()
  }

  func snapshot() -> [StartupSystemMaintenanceCommand] {
    lock.lock()
    defer { lock.unlock() }
    return commands
  }
}

final class LegacyAppTakeoverIsolationTests: XCTestCase {
  func testStartupRequestsOnlyRetainedBundleLocalMaintenance() throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("legacy-app-isolation-\(UUID().uuidString)", isDirectory: true)
    let targetBundle = temporaryRoot.appendingPathComponent("Target Product.app", isDirectory: true)
    let foreignBundle = temporaryRoot.appendingPathComponent("Omi Computer.app", isDirectory: true)
    let foreignSentinel = foreignBundle.appendingPathComponent("sentinel.txt")
    let sentinelBytes = Data("foreign-app-sentinel".utf8)

    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: targetBundle, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: foreignBundle, withIntermediateDirectories: true)
    try sentinelBytes.write(to: foreignSentinel)

    let recorder = StartupMaintenanceCommandRecorder()
    let sink = StartupSystemMaintenanceSink { command in recorder.record(command) }
    let delegate = AppDelegate(startupSystemMaintenanceSink: sink)
    delegate.performStartupSystemMaintenance(bundlePath: targetBundle.path)

    let commands = recorder.snapshot()
    XCTAssertEqual(
      commands,
      [
        StartupSystemMaintenanceCommand(
          label: "AppDelegate: strip provenance xattrs",
          executable: "/usr/bin/xattr",
          arguments: ["-cr", targetBundle.path])
      ])
    XCTAssertEqual(try Data(contentsOf: foreignSentinel), sentinelBytes)
  }
}
