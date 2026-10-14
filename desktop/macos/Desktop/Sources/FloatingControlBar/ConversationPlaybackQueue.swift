import Foundation

/// A streaming response ends only after the provider seals it AND every chunk
/// has physically played. Stop invalidates all callbacks from the old answer.
struct ConversationPlaybackQueue {
  struct Token: Hashable, Sendable {
    let generation: UInt64
    let ordinal: UInt64
  }
  private var generation: UInt64 = 0
  private var ordinal: UInt64 = 0
  private var pending: Set<Token> = []
  private var sealed = false
  private var drained = false
  func contains(_ token: Token) -> Bool { pending.contains(token) }
  mutating func enqueue() -> Token {
    ordinal &+= 1
    let token = Token(generation: generation, ordinal: ordinal)
    pending.insert(token)
    return token
  }
  mutating func played(_ token: Token) -> Bool {
    guard pending.remove(token) != nil else { return false }
    return checkDrain()
  }
  mutating func seal() -> Bool {
    sealed = true
    return checkDrain()
  }
  private mutating func checkDrain() -> Bool {
    guard sealed, pending.isEmpty, !drained else { return false }
    drained = true
    return true
  }
  mutating func reset() {
    generation &+= 1
    pending.removeAll()
    sealed = false
    drained = false
  }
}
