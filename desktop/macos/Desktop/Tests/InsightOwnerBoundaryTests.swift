import XCTest

@testable import Omi_Computer

private actor SuspendedInsightLanguageLoader {
  private var started = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var responseContinuation: CheckedContinuation<String, Never>?

  func load() async -> String {
    started = true
    startedWaiters.forEach { $0.resume() }
    startedWaiters.removeAll()
    return await withCheckedContinuation { responseContinuation = $0 }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func release(with language: String) {
    responseContinuation?.resume(returning: language)
    responseContinuation = nil
  }
}

@MainActor
private final class InsightEventPublicationCounter {
  var count = 0
}

@MainActor
final class InsightOwnerBoundaryTests: XCTestCase {
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func tearDown() async throws {
    await ownerFixture.restore()
  }

  func testSameUIDReauthenticationResetsContextAndRejectsQueuedWork() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let oldSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var boundary = InsightOwnerBoundary(authorizationSnapshot: oldSnapshot)

    XCTAssertFalse(boundary.bind(oldSnapshot))
    XCTAssertTrue(boundary.accepts(oldSnapshot))

    await ownerFixture.establish(authOwnerID: "owner-a")
    let newSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    XCTAssertTrue(boundary.bind(newSnapshot), "new auth generation must request a context reset")
    XCTAssertFalse(boundary.accepts(oldSnapshot), "old queued frames must not cross reauthentication")
    XCTAssertTrue(boundary.accepts(newSnapshot))
  }

  func testDelayedOwnerChangeReconcilePreservesAlreadyBoundNewOwnerFrame() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let assistant = try InsightAssistant(
      apiKey: "test-api-key",
      startProcessingImmediately: false)
    let ownerASnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await assistant.bindAndQueueFrameForTesting(
      frame(number: 1),
      authorizationSnapshot: ownerASnapshot)

    await ownerFixture.establish(authOwnerID: "owner-b")
    let ownerBSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await assistant.bindAndQueueFrameForTesting(
      frame(number: 2),
      authorizationSnapshot: ownerBSnapshot)

    // Model the observer task reaching the actor after B already queued work.
    await assistant.reconcileOwnerContextAfterChangeForTesting()

    let preserved = await assistant.hasPendingFrameForTesting(
      authorizationSnapshot: ownerBSnapshot)
    XCTAssertTrue(preserved)
    await assistant.stop()
  }

  func testSuspendedOwnerALanguageLoadCannotRepopulateCacheAfterSameUIDReauth() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let languageLoader = SuspendedInsightLanguageLoader()
    let assistant = try InsightAssistant(
      apiKey: "test-api-key",
      startProcessingImmediately: false,
      languageLoader: { _ in await languageLoader.load() })
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await assistant.bindAndQueueFrameForTesting(
      frame(number: 1),
      authorizationSnapshot: staleSnapshot)
    let staleLoad = Task {
      await assistant.loadUserLanguageForTesting(
        authorizationSnapshot: staleSnapshot)
    }
    await languageLoader.waitUntilStarted()

    await ownerFixture.establish(authOwnerID: "owner-a")
    let currentSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await assistant.bindAndQueueFrameForTesting(
      frame(number: 2),
      authorizationSnapshot: currentSnapshot)
    await languageLoader.release(with: "fr")

    let staleLanguage = await staleLoad.value
    XCTAssertNil(staleLanguage)
    let cachedLanguage = await assistant.cachedLanguageForTesting()
    XCTAssertNil(cachedLanguage)
    let currentFramePreserved = await assistant.hasPendingFrameForTesting(
      authorizationSnapshot: currentSnapshot)
    XCTAssertTrue(currentFramePreserved)
    await assistant.stop()
  }

  func testDelayedEventPublicationRejectsRevokedSameUIDSnapshot() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await ownerFixture.establish(authOwnerID: "owner-a")
    let counter = InsightEventPublicationCounter()

    await InsightAssistant.publishOwnerBoundEvent(
      authorizationSnapshot: staleSnapshot,
      value: "owner-a-private-insight"
    ) { _ in
      counter.count += 1
    }

    XCTAssertEqual(counter.count, 0)
  }

  private func frame(number: Int) -> CapturedFrame {
    CapturedFrame(
      jpegData: Data([0xFF, 0xD8, 0xFF]),
      appName: "Owner-bound test frame",
      frameNumber: number)
  }
}
