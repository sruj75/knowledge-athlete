import XCTest

@testable import Omi_Computer

final class ConversationPromptBindingTests: XCTestCase {
  @MainActor
  func testEndingDuringResolutionRejectsEveryWaitingRoute() async throws {
    var continuation: CheckedContinuation<ConversationPromptReceipt, Never>?
    let store = ConversationPromptBindingStore<String> { _, _ in
      await withCheckedContinuation { continuation = $0 }
    }
    let first = Task { try await store.resolve(key: "owner:chat") }
    while continuation == nil { await Task.yield() }
    var secondEntered = false
    let second = Task {
      secondEntered = true
      return try await store.resolve(key: "owner:chat")
    }
    while !secondEntered { await Task.yield() }
    store.reset()
    continuation?.resume(
      returning: ConversationPromptReceipt(
        text: "old", name: "intentive-live-system",
        version: "1", source: "langfuse", sha256: "fixture"))
    for waiter in [first, second] {
      do {
        _ = try await waiter.value
        XCTFail("A route must not adopt instructions from an ended conversation")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
  }

  @MainActor
  func testRepliesReusePinnedInstructionsUntilConversationEnds() async throws {
    var resolutions = 0
    let store = ConversationPromptBindingStore<String> { _, _ in
      resolutions += 1
      return ConversationPromptReceipt(
        text: "instructions", name: "intentive-live-system",
        version: String(resolutions), source: "langfuse", sha256: "fixture")
    }
    let first = try await store.resolve(key: "owner:chat")
    let reply = try await store.resolve(key: "owner:chat")
    XCTAssertEqual(first.id, reply.id)
    XCTAssertEqual(first.prompt, reply.prompt)
    XCTAssertEqual(resolutions, 1)
    store.end(id: first.id)
    let next = try await store.resolve(key: "owner:chat")
    XCTAssertNotEqual(first.id, next.id)
    XCTAssertEqual(next.prompt.version, "2")
  }
}
