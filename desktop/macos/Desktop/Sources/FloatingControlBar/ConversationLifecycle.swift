import Foundation

/// Logical conversation ownership is separate from provider connections and
/// individual answers. Time is injected so suspension never consumes silence.
struct ConversationLifecycle: Equatable, Sendable {
  enum State: String, Sendable { case closed, connecting, open, reconnecting, ending }
  enum Route: Sendable { case live, batch }
  private(set) var id: String?
  private(set) var state: State = .closed
  private(set) var route: Route = .live
  private(set) var generation: UInt64 = 0
  private(set) var userActivity: UInt64 = 0
  private var endAfterActivity: UInt64?
  private var listeningSince: TimeInterval?
  private var listeningElapsed: TimeInterval = 0

  var isOpen: Bool { state != .closed && state != .ending }
  var shouldEndAfterPlayback: Bool { endAfterActivity == userActivity }

  mutating func open(id: String, now: TimeInterval) {
    guard state == .closed else { return }
    generation &+= 1
    self.id = id
    state = .connecting
    route = .live
    userActivity = 0
    endAfterActivity = nil
    listeningSince = nil
    listeningElapsed = 0
  }

  mutating func connected(now: TimeInterval) {
    guard isOpen else { return }
    state = .open
    setBusy(false, now: now)
  }

  mutating func bind(id: String) {
    guard state == .connecting else { return }
    self.id = id
  }

  mutating func reconnect(now: TimeInterval) {
    guard isOpen, route == .live else { return }
    setBusy(true, now: now)
    state = .reconnecting
  }

  mutating func useFallback(now: TimeInterval) {
    guard isOpen else { return }
    route = .batch
    state = .open
    setBusy(false, now: now)
  }

  @discardableResult
  mutating func userBeganSpeaking(now: TimeInterval) -> UInt64 {
    userActivity &+= 1
    endAfterActivity = nil
    listeningElapsed = 0
    listeningSince = nil
    return userActivity
  }

  mutating func setBusy(_ busy: Bool, now: TimeInterval) {
    if busy {
      if let since = listeningSince { listeningElapsed += max(0, now - since) }
      listeningSince = nil
    } else if state == .open, listeningSince == nil {
      listeningSince = now
    }
  }

  func silenceExpired(now: TimeInterval) -> Bool {
    guard state == .open, let since = listeningSince else { return false }
    return listeningElapsed + max(0, now - since) >= 60
  }

  mutating func requestEnd(afterActivity activity: UInt64) {
    guard activity == userActivity else { return }
    endAfterActivity = activity
  }

  mutating func close() {
    generation &+= 1
    state = .closed
    id = nil
    endAfterActivity = nil
    listeningSince = nil
    listeningElapsed = 0
  }
}
