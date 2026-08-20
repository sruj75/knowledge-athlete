import XCTest

@testable import Omi_Computer

final class TaskDeduplicationSafetyTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "local-task-dedupe")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testDirectAdmissionIsCaseInsensitiveAndIdempotent() async throws {
    let first = try await ActionItemStorage.shared.insertLocalActionItemIfDescriptionAbsent(
      ActionItemRecord(description: "  Draft the Q3 report  ", source: "screenshot"),
      authorization: .unrestricted
    )
    let duplicate = try await ActionItemStorage.shared.insertLocalActionItemIfDescriptionAbsent(
      ActionItemRecord(description: "draft THE q3 REPORT", source: "screenshot"),
      authorization: .unrestricted
    )

    XCTAssertNotNil(first)
    XCTAssertNil(duplicate)
    let count = try await ActionItemStorage.shared.getLocalActionItemsCount()
    XCTAssertEqual(count, 1)
  }
}
