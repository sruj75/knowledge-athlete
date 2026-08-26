import Foundation
@preconcurrency import GRDB
import XCTest

@testable import Omi_Computer

final class OmiTakeoverIsolationTests: XCTestCase {
  func testInitializationLeavesSyntheticForeignOmiStorageUntouched() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("foreign-storage-isolation-\(UUID().uuidString)", isDirectory: true)
    let productRoot = temporaryRoot.appendingPathComponent("Target Product", isDirectory: true)
    let foreignRoot = temporaryRoot.appendingPathComponent("Omi", isDirectory: true)
    let foreignDatabase = foreignRoot.appendingPathComponent("omi.db")
    let foreignWAL = foreignRoot.appendingPathComponent("omi.db-wal")
    let foreignScreenshot = foreignRoot.appendingPathComponent("Screenshots/sentinel.txt")
    let foreignVideo = foreignRoot.appendingPathComponent("Videos/sentinel.txt")
    let foreignBackup = foreignRoot.appendingPathComponent("backups/sentinel.txt")
    let foreignSentinel = Data("foreign-omi-sentinel".utf8)

    defer {
      RewindDatabase.currentUserId = nil
      try? FileManager.default.removeItem(at: temporaryRoot)
    }

    try FileManager.default.createDirectory(
      at: foreignScreenshot.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: foreignVideo.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: foreignBackup.deletingLastPathComponent(), withIntermediateDirectories: true)

    let foreignQueue = try DatabaseQueue(path: foreignDatabase.path)
    try await foreignQueue.write { database in
      try database.execute(sql: "CREATE TABLE foreign_sentinel (value TEXT NOT NULL)")
      try database.execute(
        sql: "INSERT INTO foreign_sentinel (value) VALUES (?)",
        arguments: ["foreign-omi-sentinel"])
    }
    try foreignQueue.close()
    XCTAssertTrue(FileManager.default.createFile(atPath: foreignWAL.path, contents: Data()))
    try foreignSentinel.write(to: foreignScreenshot)
    try foreignSentinel.write(to: foreignVideo)
    try foreignSentinel.write(to: foreignBackup)

    let database = RewindDatabase(applicationSupportRootURL: productRoot)
    await database.configure(userId: "target-owner")
    try await database.initialize()
    await database.close()

    XCTAssertTrue(FileManager.default.fileExists(atPath: foreignDatabase.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: foreignWAL.path))
    XCTAssertEqual(try Data(contentsOf: foreignScreenshot), foreignSentinel)
    XCTAssertEqual(try Data(contentsOf: foreignVideo), foreignSentinel)
    XCTAssertEqual(try Data(contentsOf: foreignBackup), foreignSentinel)

    let targetOwnerRoot = productRoot.appendingPathComponent("users/target-owner", isDirectory: true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: targetOwnerRoot.appendingPathComponent("Screenshots").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: targetOwnerRoot.appendingPathComponent("Videos").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: targetOwnerRoot.appendingPathComponent("backups").path))
  }
}
