import Foundation

/// A requested voice opening can wait for a typed request to relinquish its
/// lease. Completion clears the request before opening, so the next tap closes.
@MainActor
final class ConversationOpeningRequest {
  private var requestID: UUID?
  private var task: Task<Void, Never>?
  var isPending: Bool { requestID != nil }

  func schedule(
    wait: @escaping @MainActor @Sendable () async -> Void,
    open: @escaping @MainActor @Sendable () -> Void
  ) {
    cancel()
    let id = UUID()
    requestID = id
    task = Task { [weak self] in
      await wait()
      guard let self, self.requestID == id, !Task.isCancelled else { return }
      self.requestID = nil
      self.task = nil
      open()
    }
  }

  @discardableResult
  func cancel() -> Bool {
    let wasPending = isPending
    requestID = nil
    task?.cancel()
    task = nil
    return wasPending
  }
}
