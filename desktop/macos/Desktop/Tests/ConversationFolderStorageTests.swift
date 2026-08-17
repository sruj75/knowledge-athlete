import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationFolderStorageTests: XCTestCase {
  func testCreateTrimsBoundsAllowsDuplicatesAndListsInCreationOrder() async throws {
    let owner = try makeFolderOwner()
    defer { owner.cleanup() }
    let first = try await owner.storage.createConversationFolder(
      name: "  Project  ", color: "#111111", authorization: .unrestricted)
    let second = try await owner.storage.createConversationFolder(
      name: "Project", color: "#222222", authorization: .unrestricted)

    let folders = try await owner.storage.conversationFolders()
    XCTAssertEqual(folders.map(\.id), [first.id, second.id])
    XCTAssertEqual(folders.map(\.name), ["Project", "Project"])

    for invalid in ["   ", String(repeating: "x", count: 101)] {
      do {
        _ = try await owner.storage.createConversationFolder(
          name: invalid, color: "#000000", authorization: .unrestricted)
        XCTFail("Expected invalid folder name")
      } catch TranscriptionStorageError.invalidState {
        // Expected.
      }
    }
  }

  func testAssignmentUnassignmentAndDeleteMoveAreAtomicAndDurable() async throws {
    let owner = try makeFolderOwner()
    defer { owner.cleanup() }
    let source = try await owner.storage.createConversationFolder(
      name: "Source", color: "#111111", authorization: .unrestricted)
    let destination = try await owner.storage.createConversationFolder(
      name: "Destination", color: "#222222", authorization: .unrestricted)
    let first = try await finished(owner.storage)
    let second = try await finished(owner.storage)
    _ = try await owner.storage.moveConversation(
      id: first.conversationId, toFolder: source.id, authorization: .unrestricted)
    _ = try await owner.storage.moveConversation(
      id: second.conversationId, toFolder: source.id, authorization: .unrestricted)

    let beforeDelete = try await owner.storage.conversationFolders()
    let sourceRecord = try XCTUnwrap(beforeDelete.first { $0.id == source.id })
    XCTAssertEqual(sourceRecord.conversationCount, 2)
    XCTAssertEqual(Folder(local: sourceRecord).conversationCount, 2)
    XCTAssertEqual(beforeDelete.first { $0.id == destination.id }?.conversationCount, 0)

    try await owner.storage.deleteConversationFolder(
      id: source.id, moveConversationsTo: destination.id, authorization: .unrestricted)
    _ = try await owner.storage.moveConversation(
      id: second.conversationId, toFolder: nil, authorization: .unrestricted)

    let restarted = TranscriptionStorage(databasePool: owner.pool)
    let firstDetail = try await restarted.conversationDetail(id: first.conversationId)
    let secondDetail = try await restarted.conversationDetail(id: second.conversationId)
    let folders = try await restarted.conversationFolders()
    XCTAssertEqual(firstDetail?.folderId, destination.id)
    XCTAssertNil(secondDetail?.folderId)
    XCTAssertEqual(folders.map(\.id), [destination.id])
  }

  private func finished(_ storage: TranscriptionStorage) async throws -> ConversationCaptureHandle {
    let start = Date()
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: start)
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: start.addingTimeInterval(1))
    return handle
  }

  private func makeFolderOwner() throws -> FolderStorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationFolderStorageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return FolderStorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct FolderStorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
