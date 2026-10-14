import XCTest

@testable import Omi_Computer

final class ConversationHistoryProjectionTests: XCTestCase {
  func testSameMillisecondExchangeKeepsJournalAdmissionOrder() throws {
    // Hash-derived IDs deliberately sort opposite to their admitted roles.
    let user = try XCTUnwrap(
      KernelJournalTurn(dictionary: [
        "turnId": "z-user", "turnSeq": 1, "role": "user", "content": "Question",
        "status": "completed", "createdAtMs": 1000,
      ]))
    let assistant = try XCTUnwrap(
      KernelJournalTurn(dictionary: [
        "turnId": "a-assistant", "turnSeq": 14, "role": "assistant", "content": "Answer",
        "status": "completed", "createdAtMs": 1000,
      ]))
    let history = ChatProvider.conversationHistory(from: [user, assistant])
    XCTAssertEqual(history.map(\.role), ["user", "assistant"])
    XCTAssertEqual(history.map(\.text), ["Question", "Answer"])
  }
}
