import Foundation

/// One typed request owns the conversational surface until its finalizer releases
/// the lease. Revisions and completion are fenced by the admitted request ID.
@MainActor
final class ConversationTextTurnLease {
  private(set) var turnID: String?
  private(set) var conversationID: String?
  private(set) var revision = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  var isActive: Bool { turnID != nil }
  var hasConversation: Bool { isActive || conversationID != nil }

  func begin(turnID: String, conversationID: String?) -> Bool {
    guard self.turnID == nil else { return false }
    self.turnID = turnID
    self.conversationID = conversationID ?? self.conversationID
    revision = 0
    return true
  }

  func bind(turnID: String, conversationID: String) -> Bool {
    guard self.turnID == turnID else { return false }
    self.conversationID = conversationID
    return true
  }

  func nextRevision(turnID: String) -> Int? {
    guard self.turnID == turnID else { return nil }
    revision += 1
    return revision
  }

  @discardableResult
  func finish(turnID: String) -> Bool {
    guard self.turnID == turnID else { return false }
    self.turnID = nil
    let ready = waiters
    waiters.removeAll()
    for waiter in ready { waiter.resume() }
    return true
  }

  func endConversation() {
    guard !isActive else { return }
    conversationID = nil
  }

  func waitUntilReleased() async {
    guard isActive else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}
