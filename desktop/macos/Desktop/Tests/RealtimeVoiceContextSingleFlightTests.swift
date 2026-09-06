import XCTest

@testable import Omi_Computer

@MainActor
final class RealtimeVoiceContextSingleFlightTests: XCTestCase {
  @MainActor
  private final class Gate {
    var startCount = 0
    var continuation: CheckedContinuation<Bool, Never>?
    var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func run() async -> Bool {
      return await withCheckedContinuation { continuation in
        self.continuation = continuation
        startCount += 1
        for waiter in startedWaiters {
          waiter.resume()
        }
        startedWaiters.removeAll()
      }
    }

    func waitUntilStarted() async {
      guard startCount == 0 else { return }
      await withCheckedContinuation { continuation in
        startedWaiters.append(continuation)
      }
    }

    func finish(_ result: Bool) {
      continuation?.resume(returning: result)
      continuation = nil
    }
  }

  @MainActor
  private final class Signal {
    private var didFire = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
      didFire = true
      for waiter in waiters {
        waiter.resume()
      }
      waiters.removeAll()
    }

    func wait() async {
      guard !didFire else { return }
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }
  }

  private func waitUntilStarted(_ gate: Gate) async {
    await gate.waitUntilStarted()
  }

  func testCancelledTurnWaiterDoesNotCancelSharedReadiness() async {
    let singleFlight = RealtimeVoiceContextSingleFlight()
    let gate = Gate()
    let turnWaiterJoined = Signal()

    let speculative = singleFlight.joinOrStart { await gate.run() }
    let turnWaiter = Task {
      let sharedReadiness = singleFlight.joinOrStart { await gate.run() }
      turnWaiterJoined.fire()
      return await sharedReadiness.value
    }
    await waitUntilStarted(gate)
    await turnWaiterJoined.wait()

    XCTAssertEqual(gate.startCount, 1)
    XCTAssertTrue(singleFlight.isRunning)

    turnWaiter.cancel()
    gate.finish(true)

    let speculativeResult = await speculative.value
    let turnWaiterResult = await turnWaiter.value
    XCTAssertTrue(speculativeResult)
    XCTAssertTrue(turnWaiterResult)
    await Task.yield()
    XCTAssertFalse(singleFlight.isRunning)
    XCTAssertEqual(gate.startCount, 1)
  }

  func testForcedRefreshDoesNotReuseAnOlderSpeculativeRead() async {
    let singleFlight = RealtimeVoiceContextSingleFlight()
    let speculativeGate = Gate()
    let forcedGate = Gate()

    let speculative = singleFlight.joinOrStart { await speculativeGate.run() }
    await waitUntilStarted(speculativeGate)
    let forced = singleFlight.restart { await forcedGate.run() }
    await waitUntilStarted(forcedGate)

    XCTAssertEqual(speculativeGate.startCount, 1)
    XCTAssertEqual(forcedGate.startCount, 1)
    XCTAssertTrue(singleFlight.isRunning)

    speculativeGate.finish(false)
    forcedGate.finish(true)

    let speculativeResult = await speculative.value
    let forcedResult = await forced.value
    XCTAssertFalse(speculativeResult)
    XCTAssertTrue(forcedResult)
    XCTAssertFalse(singleFlight.isRunning)
  }

  func testCompletedFailureClearsBeforeAnotherReadJoins() async {
    let singleFlight = RealtimeVoiceContextSingleFlight()
    let failedGate = Gate()
    let retryGate = Gate()

    let failed = singleFlight.joinOrStart { await failedGate.run() }
    await waitUntilStarted(failedGate)
    failedGate.finish(false)
    let failedResult = await failed.value
    XCTAssertFalse(failedResult)
    XCTAssertFalse(singleFlight.isRunning)

    let retry = singleFlight.joinOrStart { await retryGate.run() }
    await waitUntilStarted(retryGate)
    XCTAssertEqual(retryGate.startCount, 1)
    retryGate.finish(true)
    let retryResult = await retry.value
    XCTAssertTrue(retryResult)
  }

  func testReadinessUsesCompletedSuccessorWhenCancelledPredecessorFinishesLast() async {
    let singleFlight = RealtimeVoiceContextSingleFlight()
    let older = Gate()
    let newer = Gate()
    let joined = Signal()
    let ready = expectation(description: "newest snapshot releases waiter before obsolete read")
    singleFlight.joinOrStart { await older.run() }
    await older.waitUntilStarted()
    let waiter = Task {
      joined.fire()
      let result = await singleFlight.latestResult()
      ready.fulfill()
      return result
    }
    await joined.wait()
    let successor = singleFlight.restart { await newer.run() }
    await newer.waitUntilStarted()
    newer.finish(true)
    _ = await successor.value
    XCTAssertFalse(singleFlight.isRunning)
    await fulfillment(of: [ready], timeout: 1)
    older.finish(false)
    let result = await waiter.value
    XCTAssertTrue(result, "the completed newer snapshot supersedes the cancelled read")
    XCTAssertEqual(newer.startCount, 1, "joining a completed successor must not trigger another read")
  }

  func testLatestFailureSettlesOnceAfterRunningClearsWithoutRetry() async {
    let singleFlight = RealtimeVoiceContextSingleFlight()
    var starts = 0
    var completions: [Bool] = []
    singleFlight.joinOrStart(onSettled: { result in
      XCTAssertFalse(singleFlight.isRunning)
      completions.append(result)
    }) {
      starts += 1
      return false
    }
    let result = await singleFlight.latestResult()
    XCTAssertFalse(result)
    XCTAssertEqual(starts, 1)
    XCTAssertEqual(completions, [false])
  }

  func testCancelledLatestWaiterDoesNotCancelOrSettleSharedWorkEarly() async {
    let singleFlight = RealtimeVoiceContextSingleFlight()
    let gate = Gate()
    let joined = Signal()
    let withdrawn = expectation(description: "cancelled waiter withdraws before shared work settles")
    var completions: [Bool] = []
    let speculative = singleFlight.joinOrStart(onSettled: { completions.append($0) }) {
      await gate.run()
    }
    await gate.waitUntilStarted()
    let waiter = Task {
      joined.fire()
      let result = await singleFlight.latestResult()
      withdrawn.fulfill()
      return result
    }
    await joined.wait()
    waiter.cancel()
    XCTAssertTrue(singleFlight.isRunning)
    XCTAssertTrue(completions.isEmpty)
    await fulfillment(of: [withdrawn], timeout: 1)
    gate.finish(true)
    let speculativeResult = await speculative.value
    let waiterResult = await waiter.value
    XCTAssertTrue(speculativeResult)
    XCTAssertFalse(waiterResult)
    XCTAssertEqual(completions, [true])
  }
}
