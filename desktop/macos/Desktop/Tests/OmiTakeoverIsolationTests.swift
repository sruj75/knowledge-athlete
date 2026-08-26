import Foundation
@preconcurrency import GRDB
import XCTest

@testable import Omi_Computer

private final class RewindFileAccessRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedAccesses: [(RewindDatabaseFileSystem.Operation, String)] = []

  func record(operation: RewindDatabaseFileSystem.Operation, path: String) {
    lock.lock()
    recordedAccesses.append((operation, path))
    lock.unlock()
  }

  func snapshot() -> [(RewindDatabaseFileSystem.Operation, String)] {
    lock.lock()
    defer { lock.unlock() }
    return recordedAccesses
  }
}

final class OmiTakeoverIsolationTests: XCTestCase {
  func testInitializationNeverAccessesSyntheticForeignOmiStorage() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("foreign-storage-isolation-\(UUID().uuidString)", isDirectory: true)
    let productRoot = temporaryRoot.appendingPathComponent("Target Product", isDirectory: true)
    let foreignRoot = temporaryRoot.appendingPathComponent("Omi", isDirectory: true)
    let foreignDatabase = foreignRoot.appendingPathComponent("omi.db")
    let foreignWAL = foreignRoot.appendingPathComponent("omi.db-wal")
    let foreignScreenshot = foreignRoot.appendingPathComponent("Screenshots/sentinel.txt")
    let foreignVideo = foreignRoot.appendingPathComponent("Videos/sentinel.txt")
    let foreignBackup = foreignRoot.appendingPathComponent("backups/sentinel.txt")
    let anonymousDatabase = foreignRoot.appendingPathComponent("users/anonymous/omi.db")
    let foreignSentinel = Data("foreign-omi-sentinel".utf8)

    defer {
      RewindDatabase.currentUserId = nil
      try? FileManager.default.removeItem(at: temporaryRoot)
    }

    let foreignFiles = [
      foreignDatabase,
      foreignWAL,
      foreignScreenshot,
      foreignVideo,
      foreignBackup,
      anonymousDatabase,
    ]
    for file in foreignFiles {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    try await createForeignDatabase(at: foreignDatabase)
    try await createForeignDatabase(at: anonymousDatabase)
    for file in [foreignWAL, foreignScreenshot, foreignVideo, foreignBackup] {
      try foreignSentinel.write(to: file)
    }
    let originalFiles = try foreignFiles.map { file in
      (url: file, bytes: try Data(contentsOf: file))
    }

    let recorder = RewindFileAccessRecorder()
    let fileSystem = RewindDatabaseFileSystem { operation, path in
      recorder.record(operation: operation, path: path)
    }
    let database = RewindDatabase(
      storageLocation: RewindDatabaseStorageLocation(
        applicationSupportDirectoryURL: temporaryRoot,
        productPathComponents: [productRoot.lastPathComponent]),
      fileSystem: fileSystem)
    await database.configure(userId: "target-owner")
    try await database.initialize()
    await database.close()

    for originalFile in originalFiles {
      XCTAssertEqual(
        try Data(contentsOf: originalFile.url),
        originalFile.bytes,
        "Changed foreign file: \(originalFile.url.path)")
    }

    let foreignPath = foreignRoot.standardizedFileURL.path
    let foreignPrefix = foreignPath + "/"
    let foreignAccesses = recorder.snapshot().filter { _, path in
      let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
      return standardizedPath == foreignPath || standardizedPath.hasPrefix(foreignPrefix)
    }
    XCTAssertTrue(
      foreignAccesses.isEmpty,
      "Initialization accessed synthetic foreign storage: \(foreignAccesses)")

    let targetOwnerRoot = productRoot.appendingPathComponent("users/target-owner", isDirectory: true)
    let targetDatabase = targetOwnerRoot.appendingPathComponent("omi.db")
    XCTAssertTrue(FileManager.default.fileExists(atPath: targetDatabase.path))
    let targetQueue = try DatabaseQueue(path: targetDatabase.path)
    let importedForeignTable = try await targetQueue.read { database in
      try database.tableExists("foreign_sentinel")
    }
    try targetQueue.close()
    XCTAssertFalse(importedForeignTable)
    XCTAssertFalse(FileManager.default.fileExists(atPath: targetOwnerRoot.appendingPathComponent("Screenshots").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: targetOwnerRoot.appendingPathComponent("Videos").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: targetOwnerRoot.appendingPathComponent("backups").path))
  }

  private func createForeignDatabase(at url: URL) async throws {
    let queue = try DatabaseQueue(path: url.path)
    try await queue.write { database in
      try database.execute(sql: "CREATE TABLE foreign_sentinel (value TEXT NOT NULL)")
      try database.execute(
        sql: "INSERT INTO foreign_sentinel (value) VALUES (?)",
        arguments: ["foreign-omi-sentinel"])
    }
    try queue.close()
  }
}
