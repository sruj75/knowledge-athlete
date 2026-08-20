import XCTest

@testable import Omi_Computer

final class MemoryCitationResolutionTests: XCTestCase {
  private var userDir: URL?

  override func setUp() async throws {
    let fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "memory-citation")
    userDir = fixture.userDir
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: userDir)
  }

  func testCitedMemoriesResolveByStableLocalIdentityOutsideTheVisiblePage() async throws {
    let cited = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "the cited one", layer: .longTerm),
      now: Date(timeIntervalSince1970: 1))
    _ = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "not cited", layer: .longTerm),
      now: Date(timeIntervalSince1970: 2))

    let resolved = try await MemoryStorage.shared.memories(ids: [cited.id])

    XCTAssertEqual(resolved.map(\.id), [cited.id])
    XCTAssertEqual(resolved.first?.content, "the cited one")
  }

  func testCitationLookupIgnoresLayerAndDismissalFilters() async throws {
    let shortTerm = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "short term", layer: .shortTerm))
    let dismissed = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "dismissed", layer: .longTerm))
    try await MemoryStorage.shared.markDismissed(id: dismissed.id, isDismissed: true)

    let resolved = try await MemoryStorage.shared.memories(ids: [shortTerm.id, dismissed.id])

    XCTAssertEqual(Set(resolved.map(\.id)), Set([shortTerm.id, dismissed.id]))
  }

  func testUnknownAndDuplicateCitationsAreAbsentAndDeduplicatedNewestFirst() async throws {
    let older = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "older", layer: .longTerm),
      now: Date(timeIntervalSince1970: 1_000))
    let newer = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "newer", layer: .longTerm),
      now: Date(timeIntervalSince1970: 9_000))

    let resolved = try await MemoryStorage.shared.memories(
      ids: [older.id, newer.id, older.id, "999999999"])

    XCTAssertEqual(resolved.map(\.id), [newer.id, older.id])
    let empty = try await MemoryStorage.shared.memories(ids: [])
    XCTAssertTrue(empty.isEmpty)
  }
}
