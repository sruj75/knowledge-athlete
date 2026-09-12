import Foundation

/// Delivery boundary for disposable meter samples, never recorded audio bytes.
final class AudioLevelDelivery: @unchecked Sendable {
  typealias Handler = @MainActor @Sendable (Float) -> Void
  typealias Schedule = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
  private let schedule: Schedule
  private let lock = NSLock()
  private var latest: (Float, Handler)?
  private var scheduled = false
  private var generation: UInt64 = 0
  private var acceptingSamples = false

  struct Capture: Sendable { fileprivate let generation: UInt64 }

  init(schedule: @escaping Schedule = { work in DispatchQueue.main.async { work() } }) {
    self.schedule = schedule
  }

  func submit(_ level: Float, to handler: @escaping Handler) {
    let admittedGeneration: UInt64? = lock.withLock {
      guard acceptingSamples else { return nil }
      latest = (level, handler)
      guard !scheduled else { return nil }
      scheduled = true
      return generation
    }
    guard let admittedGeneration else { return }
    schedule { [weak self] in self?.drain(generation: admittedGeneration) }
  }

  /// Invalidates queued and still-arriving samples synchronously at Stop.
  /// A new capture may activate this receipt only after the old HAL has quiesced.
  @discardableResult
  func invalidate() -> Capture {
    lock.withLock {
      generation &+= 1
      acceptingSamples = false
      latest = nil
      scheduled = false
      return Capture(generation: generation)
    }
  }

  func activate(_ capture: Capture) {
    lock.withLock {
      guard generation == capture.generation else { return }
      acceptingSamples = true
    }
  }

  @MainActor
  private func drain(generation admittedGeneration: UInt64) {
    let sample: (Float, Handler)? = lock.withLock {
      guard generation == admittedGeneration else { return nil }
      defer {
        latest = nil
        scheduled = false
      }
      return latest
    }
    if let (level, handler) = sample { handler(level) }
  }
}
