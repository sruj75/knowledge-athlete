import GRDB
import XCTest

@testable import Omi_Computer

@MainActor
final class MemoryLocalAuthorityTests: XCTestCase {
  private var userDir: URL?

  override func setUp() async throws {
    let fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "memory-local-authority")
    userDir = fixture.userDir
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: userDir)
  }

  func testExplicitAssertionIsReadableLocallyBeforeNormalization() async throws {
    let now = Date()
    let accepted = try await MemoryStorage.shared.acceptExplicitAssertion(
      content: "  I prefer dark roast coffee.  ",
      now: now
    )

    XCTAssertEqual(accepted.content, "I prefer dark roast coffee.")
    XCTAssertEqual(accepted.category, .manual)
    XCTAssertEqual(accepted.layer, .shortTerm)
    XCTAssertEqual(accepted.revision, 1)
    XCTAssertEqual(accepted.expiresAt, now.addingTimeInterval(MemoryStorage.shortTermLifetime))

    let visible = try await MemoryStorage.shared.list(
      scope: .defaultAccess,
      limit: 100,
      offset: 0
    )
    XCTAssertEqual(visible.map(\.id), [accepted.id])
  }

  func testWhitespaceAssertionIsRejectedWithoutCreatingARecord() async throws {
    do {
      _ = try await MemoryStorage.shared.acceptExplicitAssertion(
        content: " \n\t ",
        now: Date(timeIntervalSince1970: 1_000)
      )
      XCTFail("Whitespace-only assertions must not be accepted")
    } catch MemoryStorageError.emptyContent {
      // Expected: validation happens before the transaction writes anything.
    }

    let visible = try await MemoryStorage.shared.list(
      scope: .defaultAccess,
      limit: 100,
      offset: 0
    )
    XCTAssertTrue(visible.isEmpty)
  }

  func testInlineEditKeepsItsDraftWhenTheAcceptedRevisionIsStale() async throws {
    let original = try await MemoryStorage.shared.acceptExplicitAssertion(
      content: "I prefer tea.", now: Date(timeIntervalSince1970: 1_000))
    _ = try await MemoryStorage.shared.correct(
      id: original.id,
      expectedRevision: original.revision,
      content: "I prefer coffee.",
      now: Date(timeIntervalSince1970: 1_001),
      ownerGeneration: await RewindDatabase.shared.poolGeneration())
    let viewModel = MemoriesViewModel()
    viewModel.editText = "  I prefer espresso.  "

    let saved = await viewModel.saveEditedMemory(original)
    let persisted = try await MemoryStorage.shared.memory(id: original.id)

    XCTAssertFalse(saved)
    XCTAssertEqual(viewModel.editText, "  I prefer espresso.  ")
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(persisted?.content, "I prefer coffee.")
  }

  func testRevokedAuthorizationCannotMutateMemoryPresentationFlags() async throws {
    let memory = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Owner-fenced Memory", layer: .longTerm))

    do {
      try await MemoryStorage.shared.markRead(
        id: memory.id,
        isRead: true,
        authorization: LocalMutationAuthorization { false })
      XCTFail("a revoked owner lease must reject the mutation")
    } catch LocalMutationAuthorizationError.revoked {
      // Expected: authorization is checked inside the write transaction.
    }

    let persisted = try await MemoryStorage.shared.memory(id: memory.id)
    XCTAssertEqual(persisted?.isRead, false)
  }

  func testDefaultScopeExcludesArchiveAndLiteralSearchStaysLocal() async throws {
    _ = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Enjoys Ethiopian coffee", category: .system, layer: .longTerm),
      now: Date(timeIntervalSince1970: 1_000)
    )
    let archived = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Used to drink tea", category: .system, layer: .archive),
      now: Date(timeIntervalSince1970: 900)
    )

    let defaults = try await MemoryStorage.shared.list(
      scope: .defaultAccess,
      limit: 100,
      offset: 0
    )
    XCTAssertEqual(defaults.count, 1)

    let archive = try await MemoryStorage.shared.list(
      scope: .archiveOnly,
      limit: 100,
      offset: 0
    )
    XCTAssertEqual(archive.map(\.id), [archived.id])

    let literal = try await MemoryStorage.shared.literalSearch(
      "ETHIOPIAN",
      scope: .defaultAccess,
      categories: [],
      limit: 100,
      offset: 0
    )
    XCTAssertEqual(literal.map(\.content), ["Enjoys Ethiopian coffee"])
  }

  func testStartingAnotherDeleteFinalizesThePreviousTombstone() async throws {
    let first = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "First local Memory", layer: .longTerm))
    let second = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Second local Memory", layer: .longTerm))
    let viewModel = MemoriesViewModel(
      sleeper: { _ in
        let cancellationStream = AsyncStream<Void> { continuation in
          continuation.onTermination = { _ in }
        }
        for await _ in cancellationStream {}
        try Task.checkCancellation()
      })

    await viewModel.deleteMemory(first)
    await viewModel.deleteMemory(second)
    let finalizedFirst = try await MemoryStorage.shared.memory(
      id: first.id, includePendingDelete: true)
    let pendingSecond = try await MemoryStorage.shared.memory(
      id: second.id, includePendingDelete: true)

    XCTAssertNil(
      finalizedFirst,
      "a second delete must hard-delete the first tombstone instead of orphaning it")
    XCTAssertNotNil(
      pendingSecond,
      "the newest delete remains undoable during its four-second window")
    await viewModel.undoDelete()
  }

  func testMemoriesPageCopyDescribesLocalDurabilityExactly() {
    XCTAssertEqual(MemoryPageCopy.subtitle, "Memories and insights saved on this Mac")
  }

  func testLegacyTipsMigrationPreservesInsightAndSchedulesExpiryAndEmbedding() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("memory-s12-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = try DatabaseQueue(path: directory.appendingPathComponent("omi.db").path)
    try queue.write { db in
      try db.create(table: "screenshots") { table in
        table.autoIncrementedPrimaryKey("id")
      }
      try db.create(table: "memories") { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("content", .text).notNull()
        table.column("category", .text).notNull()
        table.column("tier", .text)
        table.column("tagsJson", .text)
        table.column("manuallyAdded", .boolean).notNull().defaults(to: false)
        table.column("createdAt", .datetime).notNull()
        table.column("updatedAt", .datetime).notNull()
      }
      try db.execute(
        sql: """
          INSERT INTO memories
            (content, category, tier, tagsJson, manuallyAdded, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          "A retained productivity tip", "system", "short_term", "[\"tips\",\"productivity\"]",
          false, Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 1_000),
        ])
    }

    var migrator = DatabaseMigrator()
    RewindDatabase.registerMemoryLocalAuthorityMigration(on: &migrator)
    try migrator.migrate(queue)

    try queue.read { db in
      let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM memories"))
      XCTAssertEqual(row["category"] as String, MemoryCategory.interesting.rawValue)
      XCTAssertNotNil(row["expiresAt"] as Date?)
      let workKinds = Set(
        try String.fetchAll(db, sql: "SELECT kind FROM memory_processing_work ORDER BY kind"))
      XCTAssertEqual(workKinds, Set([MemoryProcessingKind.consolidate.rawValue, MemoryProcessingKind.embed.rawValue]))
    }
  }
}
