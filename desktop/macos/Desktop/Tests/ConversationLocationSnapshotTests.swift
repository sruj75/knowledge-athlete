import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationLocationSnapshotTests: XCTestCase {
  func testAuthorizedReturnsOneSnapshotWhileDeniedAndTimeoutRemainNonblockingNil() async {
    let location = ConversationLocationSnapshot(latitude: 37.7749, longitude: -122.4194, label: "Office")
    let authorized = StubConversationLocationProvider(result: .success(location))
    let denied = StubConversationLocationProvider(result: .success(nil))

    let authorizedResult = await ConversationLocationSnapshotter.capture(
      using: authorized, timeoutNanoseconds: 50_000_000)
    let deniedResult = await ConversationLocationSnapshotter.capture(using: denied, timeoutNanoseconds: 50_000_000)
    XCTAssertEqual(authorizedResult, location)
    XCTAssertNil(deniedResult)
    XCTAssertEqual(authorized.requestCount, 1)
    XCTAssertEqual(denied.requestCount, 1)
  }

  func testTimeoutCancelsAPendingOneShotWithoutWallClockWaiting() async {
    let pending = StubConversationLocationProvider(result: .pending)
    let timeout = ControlledLocationTimeout()
    let capture = Task {
      await ConversationLocationSnapshotter.capture(
        using: pending,
        timeoutNanoseconds: 1,
        timeoutSleeper: timeout.sleep)
    }

    await pending.waitUntilRequested()
    await timeout.fire()

    let result = await capture.value
    XCTAssertNil(result)
    XCTAssertEqual(pending.requestCount, 1)
  }
}

@MainActor
private final class StubConversationLocationProvider: ConversationLocationProviding {
  enum Result {
    case success(ConversationLocationSnapshot?)
    case pending
  }

  private(set) var requestCount = 0
  private let result: Result
  private var pendingContinuation: CheckedContinuation<ConversationLocationSnapshot?, Never>?
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []

  init(result: Result) {
    self.result = result
  }

  func requestOneShotLocation() async throws -> ConversationLocationSnapshot? {
    requestCount += 1
    requestWaiters.forEach { $0.resume() }
    requestWaiters.removeAll()
    switch result {
    case .success(let value): return value
    case .pending:
      return await withTaskCancellationHandler {
        await withCheckedContinuation { pendingContinuation = $0 }
      } onCancel: {
        Task { @MainActor [weak self] in
          let continuation = self?.pendingContinuation
          self?.pendingContinuation = nil
          continuation?.resume(returning: nil)
        }
      }
    }
  }

  func waitUntilRequested() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }
}

private actor ControlledLocationTimeout {
  private var fired = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func sleep(_: UInt64) async throws {
    guard !fired else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func fire() {
    fired = true
    waiters.forEach { $0.resume() }
    waiters.removeAll()
  }
}
