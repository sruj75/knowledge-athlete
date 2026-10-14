import GRDB
import XCTest

@testable import Omi_Computer

@MainActor
final class FocusLocalAuthorityTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func setUp() async throws {
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "focus-local-authority")
    await ownerFixture.establish(authOwnerID: try XCTUnwrap(fixture?.testUserId))
  }

  override func tearDown() async throws {
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
  }

  func testAcceptedAnalysisCommitsExactlyOneFocusRowWithoutCreatingAMemory() async throws {
    let committed = try await ProactiveStorage.shared.insertFocusSession(
      FocusSessionRecord(
        status: "focused",
        appOrSite: "Xcode",
        windowTitle: "FocusLocalAuthorityTests.swift",
        description: "Writing the Focus authority regression test",
        message: "Keep going"
      ),
      authorization: .unrestricted
    )

    XCTAssertNotNil(committed.id)

    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    try await pool.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_sessions"), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM memories WHERE source = 'focus'"
        ),
        0
      )
    }
  }

  func testRevokedOwnerCannotCommitFocusRow() async throws {
    do {
      _ = try await ProactiveStorage.shared.insertFocusSession(
        FocusSessionRecord(
          status: "distracted",
          appOrSite: "Browser",
          description: "Reading unrelated material"
        ),
        authorization: LocalMutationAuthorization { false }
      )
      XCTFail("revoked owner unexpectedly committed a Focus row")
    } catch {
      XCTAssertEqual(error as? LocalMutationAuthorizationError, .revoked)
    }

    let count = try await ProactiveStorage.shared.getTotalFocusSessionCount()
    XCTAssertEqual(count, 0)
  }

  func testAdmissionEnforcesThirtyDayAndFiveHundredRowRetentionInItsCommit() async throws {
    let now = Date()
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    try await pool.write { db in
      for index in 0..<501 {
        try FocusSessionRecord(
          status: index.isMultiple(of: 2) ? "focused" : "distracted",
          appOrSite: "App \(index)",
          description: "Session \(index)",
          createdAt: now.addingTimeInterval(TimeInterval(-index))
        ).insert(db)
      }
      try FocusSessionRecord(
        status: "focused",
        appOrSite: "Old app",
        description: "Expired session",
        createdAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
      ).insert(db)
    }

    let newest = try await ProactiveStorage.shared.insertFocusSession(
      FocusSessionRecord(
        status: "focused",
        appOrSite: "Newest app",
        description: "Accepted now",
        createdAt: now.addingTimeInterval(1)
      ),
      authorization: .unrestricted
    )

    let retained = try await ProactiveStorage.shared.getFocusSessions(
      from: .distantPast,
      to: .distantFuture,
      limit: 1_000
    )
    XCTAssertEqual(retained.count, 500)
    XCTAssertEqual(retained.first?.id, newest.id)
    XCTAssertFalse(retained.contains { $0.description == "Expired session" })
  }

  func testDeleteAndClearAreDurableOwnerAuthorizedMutations() async throws {
    let first = try await ProactiveStorage.shared.insertFocusSession(
      FocusSessionRecord(status: "focused", appOrSite: "Xcode", description: "First"),
      authorization: .unrestricted
    )
    _ = try await ProactiveStorage.shared.insertFocusSession(
      FocusSessionRecord(status: "distracted", appOrSite: "Browser", description: "Second"),
      authorization: .unrestricted
    )

    try await ProactiveStorage.shared.deleteFocusSession(
      id: try XCTUnwrap(first.id),
      authorization: .unrestricted
    )
    let afterDelete = try await focusDescriptions()
    XCTAssertEqual(afterDelete, ["Second"])

    try await ProactiveStorage.shared.clearFocusSessions(authorization: .unrestricted)
    let afterClear = try await focusDescriptions()
    XCTAssertEqual(afterClear, [])
  }

  func testHistoricalFocusExportPagesPastFiveHundredWithoutPruning() async throws {
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    let historicalDate = Date(timeIntervalSince1970: 1_600_000_000)
    try await pool.write { db in
      for index in 0..<1_001 {
        try FocusSessionRecord(
          status: "focused", appOrSite: "Historical app",
          description: "Historical session \(index)", createdAt: historicalDate
        ).insert(db)
      }
    }

    let exported = try await LocalUserDataExportLiveReader.shared.focusData(authorization: authorization)
    XCTAssertEqual(exported.count, 1_001)
    XCTAssertEqual(Set(exported.compactMap(\.id)).count, 1_001)
    let remaining = try await ProactiveStorage.shared.getTotalFocusSessionCount()
    XCTAssertEqual(remaining, 1_001, "Export must not prune frozen history")
  }

  private func focusDescriptions() async throws -> [String] {
    try await ProactiveStorage.shared.getFocusSessions(
      from: .distantPast,
      to: .distantFuture,
      limit: 1_000
    ).map(\.description)
  }
}
