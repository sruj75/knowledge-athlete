import XCTest

@testable import Omi_Computer

/// Regression test for the Rewind data-retention bug: `RewindIndexer.runCleanup()`
/// existed and was correct, but was never called from anywhere, so screen
/// recordings accumulated forever regardless of the "Data Retention" setting.
///
/// This exercises the real cleanup path (DB delete → orphaned-chunk detection →
/// on-disk file deletion) against an isolated throwaway user directory and asserts
/// that chunks older than the retention window are physically removed while
/// in-window chunks are kept.
final class RewindRetentionCleanupTests: XCTestCase {

  private var testUserId: String!
  private var userDir: URL!
  private var savedRetentionDays: Int = 7
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?
  private var storageFixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()

    storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "retention-test")
    let storageFixture = try XCTUnwrap(storageFixture)
    testUserId = storageFixture.testUserId
    userDir = storageFixture.userDir
    ownerFixture = await MainActor.run { RuntimeOwnerAuthorityTestFixture() }
    try await XCTUnwrap(ownerFixture).establish(authOwnerID: testUserId)
    try await RewindStorage.shared.initialize()

    // Pin retention to a known value so the test is deterministic.
    savedRetentionDays = RewindSettings.shared.retentionDays
    RewindSettings.shared.retentionDays = 7
  }

  override func tearDown() async throws {
    RewindSettings.shared.retentionDays = savedRetentionDays
    if let ownerFixture {
      await ownerFixture.restore()
    }
    ownerFixture = nil
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture?.userDir)
    storageFixture = nil
    try await super.tearDown()
  }

  func testRunCleanupDeletesChunksOlderThanRetentionAndKeepsRecentOnes() async throws {
    let fm = FileManager.default
    let videosDir = userDir.appendingPathComponent("Videos", isDirectory: true)

    let retentionDays = RewindSettings.shared.retentionDays
    let oldDate = Calendar.current.date(byAdding: .day, value: -(retentionDays + 30), to: Date())!
    let recentDate = Date()

    let oldChunkRel = "2000-01-01/chunk_old.mp4"
    let recentChunkRel = "2099-01-01/chunk_recent.mp4"

    // Lay down two real on-disk chunk files.
    for rel in [oldChunkRel, recentChunkRel] {
      let full = videosDir.appendingPathComponent(rel)
      try fm.createDirectory(
        at: full.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("fake-mp4-bytes".utf8).write(to: full)
    }
    let oldPath = videosDir.appendingPathComponent(oldChunkRel).path
    let recentPath = videosDir.appendingPathComponent(recentChunkRel).path
    XCTAssertTrue(fm.fileExists(atPath: oldPath), "precondition: old chunk written")
    XCTAssertTrue(fm.fileExists(atPath: recentPath), "precondition: recent chunk written")

    // Reference each chunk from a screenshot row with the matching timestamp.
    _ = try await RewindDatabase.shared.insertScreenshot(
      Screenshot(
        timestamp: oldDate, appName: "RetentionTest", videoChunkPath: oldChunkRel,
        frameOffset: 0, isIndexed: true))
    _ = try await RewindDatabase.shared.insertScreenshot(
      Screenshot(
        timestamp: recentDate, appName: "RetentionTest", videoChunkPath: recentChunkRel,
        frameOffset: 0, isIndexed: true))

    // Exercise the exact production cleanup that the fix now schedules.
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: testUserId))
    await RewindIndexer.shared.runCleanup(
      authorizationSnapshot: authorizationSnapshot)

    XCTAssertFalse(
      fm.fileExists(atPath: oldPath),
      "retention cleanup must delete the chunk whose frames are older than the retention window")
    XCTAssertTrue(
      fm.fileExists(atPath: recentPath),
      "retention cleanup must keep chunks within the retention window")
  }
}
