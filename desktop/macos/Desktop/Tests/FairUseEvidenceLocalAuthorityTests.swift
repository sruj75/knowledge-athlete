import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class FairUseEvidenceLocalAuthorityTests: XCTestCase {
  func testProjectionUsesNewestThirtySevenDayRowsAndNeverExposesCanonicalIDs() async throws {
    let owner = try makeOwner()
    defer { owner.cleanup() }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var canonicalIDs = Set<String>()

    for index in 0..<32 {
      let createdAt = now.addingTimeInterval(TimeInterval(-index * 60))
      let handle = try await owner.storage.beginConversation(
        configuration: .testDefault,
        startedAt: createdAt.addingTimeInterval(-125),
        classifierSource: index == 0 ? "desktop" : nil)
      canonicalIDs.insert(handle.conversationId)
      _ = try await owner.storage.finishConversation(
        sessionId: handle.sessionId, reason: .userStop, finishedAt: createdAt.addingTimeInterval(-5))
      try await owner.pool.write { db in
        try db.execute(
          sql: """
            UPDATE transcription_sessions
            SET title = ?, overview = ?, classifierCategory = ?, createdAt = ?, status = 'completed'
            WHERE conversationId = ?
            """,
          arguments: [
            "Conversation \(index)", String(repeating: "x", count: 240), index == 0 ? "work" : nil,
            createdAt, handle.conversationId,
          ])
      }
    }

    let old = try await owner.storage.beginConversation(
      configuration: .testDefault,
      startedAt: now.addingTimeInterval(-8 * 24 * 60 * 60))
    _ = try await owner.storage.finishConversation(
      sessionId: old.sessionId, reason: .userStop, finishedAt: now.addingTimeInterval(-8 * 24 * 60 * 60 + 60))
    try await owner.pool.write { db in
      try db.execute(
        sql: "UPDATE transcription_sessions SET status = 'completed' WHERE conversationId = ?",
        arguments: [old.conversationId])
    }

    let evidence = try await owner.storage.fairUseEvidence(now: now)

    XCTAssertEqual(evidence.count, 30)
    XCTAssertEqual(evidence.first?.title, "Conversation 0")
    XCTAssertEqual(evidence.last?.title, "Conversation 29")
    XCTAssertEqual(evidence.first?.overview.count, 200)
    XCTAssertEqual(evidence.first?.category, "work")
    XCTAssertEqual(evidence.first?.source, "desktop")
    XCTAssertEqual(evidence.first?.durationMinutes, 2)
    XCTAssertEqual(evidence[1].category, "")
    XCTAssertEqual(evidence[1].source, "")
    XCTAssertTrue(evidence.allSatisfy { UUID(uuidString: $0.conversationId) != nil })
    XCTAssertTrue(evidence.allSatisfy { !canonicalIDs.contains($0.conversationId) })
  }

  private func makeOwner() throws -> FairUseEvidenceStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("FairUseEvidenceLocalAuthorityTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return FairUseEvidenceStorageOwner(
      directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct FairUseEvidenceStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
