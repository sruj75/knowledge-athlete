import CoreGraphics
import Foundation

/// Owns special-mode window enumeration. Only a boolean crosses back to the UI.
@MainActor
final class SystemCaptureModeProbe {
  private let lookup: @Sendable () -> Bool?
  private let onFallback: @MainActor () -> Void
  private let now: @Sendable () -> ContinuousClock.Instant
  private var refreshTask: Task<Void, Never>?
  private var refreshStartedAt: ContinuousClock.Instant?
  private var snapshot: (blocked: Bool, at: ContinuousClock.Instant)?
  private var reportedPendingFallback = false
  private let refreshInterval: Duration = .seconds(1)
  private let cacheLifetime: Duration = .seconds(5)

  init(
    lookup: @escaping @Sendable () -> Bool? = SystemCaptureModeProbe.queryWindowServer,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
    onFallback: @escaping @MainActor () -> Void = {}
  ) {
    self.lookup = lookup
    self.onFallback = onFallback
    self.now = now
  }

  func blocksCapture(frontmostBundleID: String?) -> Bool {
    if frontmostBundleID == "com.apple.dock" { return true }
    let instant = now()
    if snapshot.map({ $0.at.duration(to: instant) >= refreshInterval }) ?? true {
      refresh()
    }
    if let snapshot, snapshot.at.duration(to: instant) <= cacheLifetime {
      return snapshot.blocked
    }
    if let refreshStartedAt, refreshStartedAt.duration(to: instant) > cacheLifetime,
      !reportedPendingFallback
    {
      reportedPendingFallback = true
      onFallback()
    }
    // Same unavailable-query behavior as the original probe. The permission,
    // owner, lock-screen and capture-error boundaries still run independently.
    return false
  }

  @discardableResult
  func refresh() -> Task<Void, Never> {
    if let refreshTask { return refreshTask }
    refreshStartedAt = now()
    reportedPendingFallback = false
    let lookup = lookup
    // A Task inheriting MainActor still blocks the UI inside the synchronous
    // WindowServer call. Detach the lookup, and coalesce all pending refreshes.
    let task = Task.detached(priority: .utility) { [weak self] in
      let result = lookup()
      await self?.complete(result)
    }
    refreshTask = task
    return task
  }

  private func complete(_ result: Bool?) {
    if let result {
      snapshot = (result, now())
    } else {
      onFallback()
    }
    refreshTask = nil
    refreshStartedAt = nil
  }

  nonisolated static func queryWindowServer() -> Bool? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
      return nil
    }
    return containsBlockingOverlay(windows)
  }

  nonisolated static func containsBlockingOverlay(_ windows: [[String: Any]]) -> Bool {
    windows.contains { window in
      guard let owner = window[kCGWindowOwnerName as String] as? String else { return false }
      if owner == "NotificationCenter" { return true }
      guard owner == "Dock",
        (window[kCGWindowName as String] as? String)?.isEmpty != false,
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
        let width = bounds["Width"], let height = bounds["Height"]
      else { return false }
      return width > 500 && height > 300
    }
  }
}
