import Foundation

struct ConversationPromptBinding: Sendable {
  let id: String
  let prompt: ConversationPromptReceipt
}

/// Serializes prompt resolution for a logical conversation. A mutable prompt
/// label is read only when a new binding is created, never between replies.
@MainActor
final class ConversationPromptBindingStore<Key: Equatable & Sendable> {
  typealias Bootstrap = @MainActor @Sendable (String, Key) async throws -> ConversationPromptReceipt
  private let bootstrap: Bootstrap
  private var pending: (key: Key, id: String, task: Task<ConversationPromptBinding, Error>)?

  init(bootstrap: @escaping Bootstrap) { self.bootstrap = bootstrap }

  func resolve(key: Key) async throws -> ConversationPromptBinding {
    if let pending, pending.key == key {
      let binding = try await pending.task.value
      guard self.pending?.id == pending.id else { throw CancellationError() }
      return binding
    }
    reset()
    let id = UUID().uuidString
    let task = Task { ConversationPromptBinding(id: id, prompt: try await bootstrap(id, key)) }
    pending = (key, id, task)
    do {
      let binding = try await task.value
      guard pending?.id == id else { throw CancellationError() }
      return binding
    } catch {
      if pending?.id == id { pending = nil }
      throw error
    }
  }

  func end(id: String) {
    guard pending?.id == id else { return }
    reset()
  }

  func end(key: Key) {
    guard pending?.key == key else { return }
    reset()
  }

  func reset() {
    pending?.task.cancel()
    pending = nil
  }
}
