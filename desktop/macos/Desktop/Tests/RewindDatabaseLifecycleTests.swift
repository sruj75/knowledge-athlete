import AppKit
import OmiSupport
import XCTest

@testable import Omi_Computer

final class RewindDatabaseLifecycleTests: XCTestCase {

  func testCloseClearsRunningFlag() async throws {
    let testUserId = "rewind-db-lifecycle-\(UUID().uuidString)"
    let userDir = try await configureTestStorage(ownerID: testUserId)

    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = testUserId
    await RewindDatabase.shared.configure(userId: testUserId)
    try await RewindDatabase.shared.initialize()

    let runningFlag = userDir.appendingPathComponent(".heyintentive_running")
    XCTAssertTrue(FileManager.default.fileExists(atPath: runningFlag.path))

    await RewindDatabase.shared.close()

    XCTAssertFalse(FileManager.default.fileExists(atPath: runningFlag.path))
    RewindDatabase.currentUserId = nil
  }

  func testPoolGenerationAdvancesAcrossReopen() async throws {
    let testUserId = "rewind-db-pool-generation-\(UUID().uuidString)"
    _ = try await configureTestStorage(ownerID: testUserId)

    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = testUserId
    await RewindDatabase.shared.configure(userId: testUserId)
    try await RewindDatabase.shared.initialize()

    let first = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    XCTAssertNotNil(first.pool)

    await RewindDatabase.shared.close()
    let closedGeneration = await RewindDatabase.shared.poolGeneration()
    XCTAssertGreaterThan(
      closedGeneration,
      first.generation,
      "closing the database must invalidate cached storage pools"
    )

    await RewindDatabase.shared.configure(userId: testUserId)
    try await RewindDatabase.shared.initialize()

    let reopened = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    XCTAssertNotNil(reopened.pool)
    XCTAssertGreaterThan(
      reopened.generation,
      closedGeneration,
      "reopening the database must invalidate caches independently from close()"
    )

    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = nil
  }

  func testInitializeReopensDatabaseClosedAfterIndexerInitialization() async throws {
    let testUserId = "rewind-indexer-reinitialize-\(UUID().uuidString)"
    _ = try await configureTestStorage(ownerID: testUserId)

    await RewindIndexer.shared.reset()
    await RewindStorage.shared.reset()
    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = testUserId
    await RewindDatabase.shared.configure(userId: testUserId)
    let ownerFixture = await MainActor.run { RuntimeOwnerAuthorityTestFixture() }
    await ownerFixture.establish(authOwnerID: testUserId)
    try await RewindIndexer.shared.initialize()
    let initializedBeforeClose = await RewindDatabase.shared.isInitialized
    XCTAssertTrue(initializedBeforeClose)

    // Runtime I/O/corruption recovery closes the pool without resetting the indexer.
    await RewindDatabase.shared.close()
    let initializedAfterClose = await RewindDatabase.shared.isInitialized
    XCTAssertFalse(initializedAfterClose)

    try await RewindIndexer.shared.initialize()
    let initializedAfterReinitialize = await RewindDatabase.shared.isInitialized
    XCTAssertTrue(
      initializedAfterReinitialize,
      "initializing the indexer must reopen a database closed after the indexer was initialized")

    await RewindIndexer.shared.reset()
    await RewindStorage.shared.reset()
    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = nil
    await ownerFixture.restore()
  }

  func testProcessFrameReopensDatabaseClosedAfterIndexerInitialization() async throws {
    let testUserId = "rewind-indexer-process-frame-reinitialize-\(UUID().uuidString)"
    _ = try await configureTestStorage(ownerID: testUserId)

    await RewindIndexer.shared.reset()
    await RewindStorage.shared.reset()
    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = testUserId
    await RewindDatabase.shared.configure(userId: testUserId)
    let ownerFixture = await MainActor.run { RuntimeOwnerAuthorityTestFixture() }
    await ownerFixture.establish(authOwnerID: testUserId)
    try await RewindIndexer.shared.initialize()
    let frame = try makeTestFrameImage()

    // Prime the frame pipeline before simulating recovery so its first-frame
    // retention cleanup cannot reopen the database independently of ensureInitialized.
    await RewindIndexer.shared.processFrame(
      cgImage: frame,
      appName: "RewindDatabaseLifecycleTests",
      windowTitle: "prime retention cleanup",
      captureTime: Date())

    // Runtime I/O/corruption recovery closes the pool without resetting the indexer.
    await RewindDatabase.shared.close()
    let initializedAfterClose = await RewindDatabase.shared.isInitialized
    XCTAssertFalse(initializedAfterClose)

    await RewindIndexer.shared.processFrame(
      cgImage: frame,
      appName: "RewindDatabaseLifecycleTests",
      windowTitle: "reopen after close",
      captureTime: Date())

    let initializedAfterProcessFrame = await RewindDatabase.shared.isInitialized
    XCTAssertTrue(
      initializedAfterProcessFrame,
      "processing a frame must reopen a database closed after the indexer was initialized")

    await RewindIndexer.shared.reset()
    await RewindStorage.shared.reset()
    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = nil
    await ownerFixture.restore()
  }

  private func configureTestStorage(ownerID: String) async throws -> URL {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("rewind-lifecycle-\(UUID().uuidString)", isDirectory: true)
    let storageLocation = RewindDatabaseStorageLocation(
      applicationSupportDirectoryURL: temporaryRoot,
      productPathComponents: ["Intentive"])

    await RewindDatabase.shared.close()
    await RewindDatabase.shared.configureStorageLocationForTesting(storageLocation)
    DesktopLocalProfile.configureApplicationSupportURLForTesting(storageLocation.productRootURL)
    RewindDatabase.currentUserId = ownerID

    addTeardownBlock {
      await RewindDatabase.shared.close()
      await RewindDatabase.shared.configureStorageLocationForTesting(nil)
      DesktopLocalProfile.configureApplicationSupportURLForTesting(nil)
      RewindDatabase.currentUserId = nil
      try? FileManager.default.removeItem(at: temporaryRoot)
    }

    return storageLocation.productRootURL
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(ownerID, isDirectory: true)
  }

  private func makeTestFrameImage() throws -> CGImage {
    let width = 96
    let height = 64
    let context = try XCTUnwrap(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try XCTUnwrap(context.makeImage())
  }
}
