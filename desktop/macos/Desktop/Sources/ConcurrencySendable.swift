import Foundation

/// A lock-protected serial tail for callbacks that originate outside Swift
/// concurrency (for example URLSession WebSocket callbacks). `submit` registers
/// work synchronously, so a lifecycle owner can stop the producer and then
/// await `drain()` without a fire-and-forget gap.
final class OrderedAsyncOperationQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var tail: Task<Void, Never>?
  private var generation: UInt64 = 0

  func submit(_ operation: @escaping @Sendable () async -> Void) {
    lock.lock()
    let previous = tail
    generation &+= 1
    let task = Task {
      await previous?.value
      await operation()
    }
    tail = task
    lock.unlock()
  }

  func drain() async {
    let (current, drainedGeneration) = drainSnapshot()
    await current?.value
    clearDrainedTail(generation: drainedGeneration)
  }

  private func drainSnapshot() -> (Task<Void, Never>?, UInt64) {
    lock.lock()
    defer { lock.unlock() }
    return (tail, generation)
  }

  private func clearDrainedTail(generation drainedGeneration: UInt64) {
    lock.lock()
    defer { lock.unlock() }
    if generation == drainedGeneration { tail = nil }
  }
}

// KeyPath is an immutable reference type that is safe to share across concurrency
// domains. The standard library does not declare it Sendable, which blocks
// AttributedString attribute-scope key paths under strict concurrency.
extension KeyPath: @retroactive @unchecked Sendable {}

// Strict-concurrency bridge: the types below are wire DTOs (OpenAPI-generated) or
// immutable domain value records that are decoded once and then passed across actor
// boundaries as values. They are marked `@unchecked Sendable` because the compiler
// cannot always prove Sendability through their nested/`Any` fields, even though they
// are effectively immutable after decoding.

extension ToolChatResult: @unchecked Sendable {}
extension GeminiRequest.GenerationConfig.ResponseSchema: @unchecked Sendable {}
extension GeminiRequest.GenerationConfig.ResponseSchema.Property: @unchecked Sendable {}
