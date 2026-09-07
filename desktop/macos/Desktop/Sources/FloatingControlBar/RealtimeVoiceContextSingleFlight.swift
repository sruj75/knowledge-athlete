import Foundation

/// Controller-owned readiness work is shared across speculative warmup and the
/// active PTT turn. Cancelling a turn waiter must not cancel the underlying
/// owner-scoped snapshot, otherwise a cold first turn leaves the hub cold until
/// the user presses PTT a second time.
@MainActor
final class RealtimeVoiceContextSingleFlight {
  private struct Flight {
    let id: UInt64
    let task: Task<Bool, Never>
  }

  private var activeFlight: Flight?
  private var settledResult: Bool?
  private var readinessWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
  private var nextFlightID: UInt64 = 0

  var isRunning: Bool {
    activeFlight != nil
  }

  /// Await the newest requested snapshot, including a successor that settled
  /// before an older cancelled load returned. Cancellation never cancels the
  /// shared work; it only withdraws this waiter.
  func latestResult() async -> Bool {
    guard !Task.isCancelled else { return false }
    if let settledResult { return settledResult }
    guard activeFlight != nil else { return false }
    let waiterID = UUID()
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: false)
        } else {
          readinessWaiters[waiterID] = continuation
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.readinessWaiters.removeValue(forKey: waiterID)?.resume(returning: false)
      }
    }
    return !Task.isCancelled && result
  }

  @discardableResult
  func joinOrStart(
    onSettled: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
    _ operation: @escaping @MainActor @Sendable () async -> Bool
  ) -> Task<Bool, Never> {
    if let activeFlight {
      return activeFlight.task
    }
    return start(operation, onSettled: onSettled)
  }

  @discardableResult
  func restart(
    onSettled: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
    _ operation: @escaping @MainActor @Sendable () async -> Bool
  ) -> Task<Bool, Never> {
    // Existing waiters follow the new request; unlike owner reset/cancel,
    // supersession must not fail them or wait for the obsolete load to return.
    activeFlight?.task.cancel()
    return start(operation, onSettled: onSettled)
  }

  private func start(
    _ operation: @escaping @MainActor @Sendable () async -> Bool,
    onSettled: @escaping @MainActor @Sendable (Bool) -> Void
  ) -> Task<Bool, Never> {
    nextFlightID &+= 1
    settledResult = nil
    let flightID = nextFlightID
    let task = Task { @MainActor [weak self] in
      let result = await operation()
      if let self, self.activeFlight?.id == flightID {
        self.activeFlight = nil
        self.settledResult = result
        onSettled(result)
        // A completion may synchronously request newer work or cancel ownership.
        if self.nextFlightID == flightID, self.settledResult != nil {
          self.finishReadinessWaiters(result)
        }
      }
      return result
    }
    activeFlight = Flight(id: flightID, task: task)
    return task
  }

  func cancel() {
    let flight = activeFlight
    activeFlight = nil
    settledResult = nil
    flight?.task.cancel()
    finishReadinessWaiters(false)
  }

  private func finishReadinessWaiters(_ result: Bool) {
    let waiters = readinessWaiters.values
    readinessWaiters.removeAll()
    for waiter in waiters { waiter.resume(returning: result) }
  }
}
