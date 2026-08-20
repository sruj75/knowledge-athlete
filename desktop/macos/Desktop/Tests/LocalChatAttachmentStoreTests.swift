import Foundation
import XCTest

@testable import Omi_Computer

final class LocalChatAttachmentStoreTests: XCTestCase {
  func testMaterializesDiskAndPastedAttachmentsWithoutDeletingTheSource() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source notes.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("source".utf8).write(to: source)
    let store = LocalChatAttachmentStore(rootURL: root.appendingPathComponent("managed", isDirectory: true))

    let disk = try await store.materialize(
      ChatAttachment(fileName: source.lastPathComponent, mimeType: "text/plain", localFileURL: source),
      ownerID: "owner/../a",
      chatID: "chat/../a"
    )
    let pasted = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x89, 0x50, 0x4E, 0x47, 0x01])),
      ownerID: "owner/../a",
      chatID: "chat/../a"
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(disk.localFileURL)), Data("source".utf8))
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(pasted.localFileURL)), pasted.data)
    XCTAssertFalse(try XCTUnwrap(disk.localFileURL).path.contains("owner/../a"))
    XCTAssertEqual(disk.state, .localOnly)
  }

  func testMaterializingSymbolicLinkCopiesTargetBytesIntoIndependentRegularFile() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("target.txt")
    let link = root.appendingPathComponent("selected-link.txt")
    try Data("stable bytes".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let store = LocalChatAttachmentStore(rootURL: root.appendingPathComponent("managed", isDirectory: true))

    let managed = try await store.materialize(
      ChatAttachment(fileName: link.lastPathComponent, mimeType: "text/plain", localFileURL: link),
      ownerID: "owner-a",
      chatID: "chat-a"
    )
    let managedURL = try XCTUnwrap(managed.localFileURL)
    try FileManager.default.removeItem(at: link)
    try FileManager.default.removeItem(at: target)

    XCTAssertEqual(try Data(contentsOf: managedURL), Data("stable bytes".utf8))
    XCTAssertEqual(try managedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, true)
  }

  func testMaterializationRejectsDirectories() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("selected-directory", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = LocalChatAttachmentStore(rootURL: root.appendingPathComponent("managed", isDirectory: true))

    do {
      _ = try await store.materialize(
        ChatAttachment(fileName: "selected-directory", mimeType: "application/octet-stream", localFileURL: directory),
        ownerID: "owner-a",
        chatID: "chat-a"
      )
      XCTFail("directory input was accepted")
    } catch {}
  }

  func testGarbageCollectionDeletesOnlyUnreferencedManagedFiles() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LocalChatAttachmentStore(rootURL: root)
    let keep = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x89, 0x50, 0x4E, 0x47, 0x01]), suggestedName: "keep.png"),
      ownerID: "owner-a",
      chatID: "chat-a"
    )
    let remove = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x89, 0x50, 0x4E, 0x47, 0x02]), suggestedName: "remove.png"),
      ownerID: "owner-a",
      chatID: "chat-b"
    )
    await store.releaseMaterializationProtection(
      [try XCTUnwrap(keep.localFileURL), try XCTUnwrap(remove.localFileURL)]
    )

    try await store.garbageCollect(
      ownerID: "owner-a",
      retaining: [try XCTUnwrap(keep.localFileURL).absoluteString]
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(keep.localFileURL).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(remove.localFileURL).path))
  }

  func testDiscardRemovesOnlyManagedStagedCopies() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.txt")
    try Data("source".utf8).write(to: source)
    let store = LocalChatAttachmentStore(rootURL: root.appendingPathComponent("managed", isDirectory: true))
    let managed = try await store.materialize(
      ChatAttachment(fileName: "source.txt", mimeType: "text/plain", localFileURL: source),
      ownerID: "owner-a",
      chatID: "chat-a"
    )

    try await store.discardManagedFiles(
      [source, try XCTUnwrap(managed.localFileURL)],
      ownerID: "owner-a",
      chatID: "chat-a"
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(managed.localFileURL).path))
  }

  func testInFlightMaterializationIsProtectedUntilDraftRegistration() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LocalChatAttachmentStore(rootURL: root)
    let managed = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x89, 0x50, 0x4E, 0x47, 0x01])),
      ownerID: "owner-a",
      chatID: "chat-a"
    )
    let managedURL = try XCTUnwrap(managed.localFileURL)

    try await store.garbageCollect(ownerID: "owner-a", retaining: [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))

    await store.releaseMaterializationProtection([managedURL])
    try await store.garbageCollect(ownerID: "owner-a", retaining: [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
  }

  func testExplicitSignOutDiscardDeletesOnlyListedFilesForThatOwner() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-chat-attachments-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LocalChatAttachmentStore(rootURL: root)
    let ownerADraftOnly = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x01]), suggestedName: "owner-a-draft.png"),
      ownerID: "owner-a",
      chatID: "chat-a"
    )
    let ownerASharedWithJournal = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x02]), suggestedName: "owner-a-shared.png"),
      ownerID: "owner-a",
      chatID: "chat-a"
    )
    let ownerB = try await store.materialize(
      ChatAttachment.fromImageData(Data([0x03]), suggestedName: "owner-b.png"),
      ownerID: "owner-b",
      chatID: "chat-b"
    )
    let ownerADraftOnlyURL = try XCTUnwrap(ownerADraftOnly.localFileURL)
    let ownerASharedURL = try XCTUnwrap(ownerASharedWithJournal.localFileURL)
    let ownerBURL = try XCTUnwrap(ownerB.localFileURL)
    await store.releaseMaterializationProtection([ownerADraftOnlyURL, ownerASharedURL, ownerBURL])

    try await store.discardManagedDraftFiles(
      [ownerADraftOnlyURL, ownerBURL],
      ownerID: "owner-a"
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: ownerADraftOnlyURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: ownerASharedURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: ownerBURL.path))
  }
}
