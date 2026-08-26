import XCTest

@testable import Omi_Computer

@MainActor
final class DeferredUpdateInstallTests: XCTestCase {
  func testBusyActivityIsResampledUntilIdleAndInstallsExactlyOnce() {
    let scheduler = ManualUpdateInstallScheduler()
    let state = MutableUpdateInstallState(
      snapshot: .init(ambientTranscriptionActive: true)
    )
    let deferred = DeferredUpdateInstall(
      version: "1.2.3",
      retryInterval: 5,
      scheduler: scheduler,
      activitySnapshotProvider: { state.snapshot },
      install: { state.installCount += 1 }
    )

    deferred.start()

    XCTAssertEqual(state.installCount, 0)
    XCTAssertEqual(scheduler.activeCount, 1)

    state.snapshot = .idle
    XCTAssertTrue(scheduler.fireNext())
    XCTAssertEqual(state.installCount, 1)
    XCTAssertEqual(scheduler.activeCount, 0)

    deferred.start()
    XCTAssertEqual(state.installCount, 1)
  }

  func testIdleActivityInstallsImmediatelyWithoutScheduling() {
    let scheduler = ManualUpdateInstallScheduler()
    let state = MutableUpdateInstallState(snapshot: .idle)
    let deferred = DeferredUpdateInstall(
      version: "1.2.3",
      retryInterval: 5,
      scheduler: scheduler,
      activitySnapshotProvider: { .idle },
      install: { state.installCount += 1 }
    )

    deferred.start()

    XCTAssertEqual(state.installCount, 1)
    XCTAssertEqual(scheduler.activeCount, 0)
  }

  func testCancellationInvalidatesAnAlreadyScheduledResample() {
    let scheduler = ManualUpdateInstallScheduler()
    let state = MutableUpdateInstallState(snapshot: .init(chatSendActive: true))
    let deferred = DeferredUpdateInstall(
      version: "1.2.3",
      retryInterval: 5,
      scheduler: scheduler,
      activitySnapshotProvider: { state.snapshot },
      install: { state.installCount += 1 }
    )

    deferred.start()
    state.snapshot = .idle
    deferred.cancel()

    XCTAssertTrue(scheduler.fireNextIgnoringCancellation())
    XCTAssertEqual(state.installCount, 0)
  }

  func testDeallocationCannotInstallFromAnOldResample() {
    let scheduler = ManualUpdateInstallScheduler()
    let state = MutableUpdateInstallState(snapshot: .init(voicePlaybackActive: true))
    var deferred: DeferredUpdateInstall? = DeferredUpdateInstall(
      version: "1.2.3",
      retryInterval: 5,
      scheduler: scheduler,
      activitySnapshotProvider: { state.snapshot },
      install: { state.installCount += 1 }
    )

    deferred?.start()
    state.snapshot = .idle
    deferred = nil

    XCTAssertTrue(scheduler.fireNextIgnoringCancellation())
    XCTAssertEqual(state.installCount, 0)
  }
}

@MainActor
private final class MutableUpdateInstallState {
  var snapshot: UpdateInstallationActivitySnapshot
  var installCount = 0

  init(snapshot: UpdateInstallationActivitySnapshot) {
    self.snapshot = snapshot
  }
}

@MainActor
private final class ManualUpdateInstallScheduler: DelayedActionScheduling {
  private final class Cancellation: DelayedActionCancellation {
    var isCancelled = false

    func cancel() {
      isCancelled = true
    }
  }

  private struct ScheduledAction {
    let cancellation: Cancellation
    let action: @MainActor () -> Void
  }

  private var scheduled: [ScheduledAction] = []

  var activeCount: Int {
    scheduled.filter { !$0.cancellation.isCancelled }.count
  }

  func schedule(
    after interval: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> DelayedActionCancellation {
    _ = interval
    let cancellation = Cancellation()
    scheduled.append(.init(cancellation: cancellation, action: action))
    return cancellation
  }

  func fireNext() -> Bool {
    guard let index = scheduled.firstIndex(where: { !$0.cancellation.isCancelled }) else {
      return false
    }
    let item = scheduled.remove(at: index)
    item.action()
    return true
  }

  func fireNextIgnoringCancellation() -> Bool {
    guard !scheduled.isEmpty else { return false }
    let item = scheduled.removeFirst()
    item.action()
    return true
  }
}
