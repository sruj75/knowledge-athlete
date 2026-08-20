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
      sleeper: { _ in try await Task.sleep(nanoseconds: 60_000_000_000) })

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
  }

  func testMemoriesPageCopyDescribesLocalDurabilityExactly() {
    XCTAssertEqual(MemoryPageCopy.subtitle, "Memories and insights saved on this Mac")
  }
}
