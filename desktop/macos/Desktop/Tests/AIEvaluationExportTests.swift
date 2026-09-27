import XCTest

@testable import Omi_Computer

final class AIEvaluationExportTests: XCTestCase {
  func testNormalTurnExportsOnlyReceipt() throws {
    let event = AIEvaluationObservation.terminal(
      sessionID: "session", turnID: "turn", decisionID: "decision", prompt: prompt,
      outcome: .cancelled, durationMs: 42,
      conversation: [.init(turnID: "turn", role: "assistant", text: "private spoken text", outcome: "cancelled")])
    let json = try jsonObject(event, sharing: false)
    XCTAssertEqual(json["evaluation_sharing"] as? Bool, false)
    XCTAssertNil(json["conversation"])
    XCTAssertEqual(json["outcome"] as? String, "cancelled")
    XCTAssertEqual(json["decision_id"] as? String, "decision")
    XCTAssertNil((json["prompt"] as? [String: Any])?["text"])
  }

  func testSelectedDecisionExportsBoundedTextWithoutObservationPayloads() throws {
    let event = AIEvaluationObservation.decision(
      sessionID: "session", decisionID: "decision", observationID: "observation", prompt: prompt,
      transcripts: [.init(id: "segment", text: String(repeating: "t", count: 3_000), source: .mixed)],
      conversation: [], note: String(repeating: "n", count: 3_000))
    let json = try jsonObject(event, sharing: true)
    XCTAssertEqual((json["note"] as? String)?.count, 2_000)
    XCTAssertEqual(((json["transcripts"] as? [[String: Any]])?.first?["text"] as? String)?.count, 2_000)
    for key in ["screen", "profile", "memories", "tools", "audio"] { XCTAssertNil(json[key]) }
    XCTAssertNil((json["prompt"] as? [String: Any])?["text"])
  }

  func testRevocationAndSessionChangeInvalidatePreviouslySelectedContent() {
    var consent = AIEvaluationConsent(sessionID: "first")
    consent.update(sessionID: "first", sharing: true)
    let ticket = consent.ticket
    XCTAssertTrue(consent.permitsContent(ticket))
    consent.update(sessionID: "first", sharing: false)
    XCTAssertFalse(consent.permitsContent(ticket))
    consent.update(sessionID: "first", sharing: true)
    XCTAssertFalse(consent.permitsContent(ticket), "Re-enabling cannot release old queued content")
    let newTicket = consent.ticket
    consent.update(sessionID: "second", sharing: true)
    XCTAssertFalse(consent.permitsContent(newTicket))
  }

  func testNormalDecisionCannotIncludePrivateNote() throws {
    let event = AIEvaluationObservation.decision(
      sessionID: "session", decisionID: "decision", observationID: "observation", prompt: prompt,
      transcripts: [.init(id: "segment", text: "ambient", source: .microphone)],
      conversation: [], note: "private note")
    let json = try jsonObject(event, sharing: false)
    XCTAssertNil(json["note"])
    XCTAssertNil(json["transcripts"])
    XCTAssertNil(json["conversation"])
  }

  func testChatExportUsesSuccessfulRequestWithoutBorrowingLivePrompt() throws {
    let event = AIEvaluationObservation.chatTerminal(
      sessionID: "session", turnID: "accepted-turn", requestID: "successful-retry",
      outcome: .completed, durationMs: 50,
      conversation: [
        .init(turnID: "accepted-turn", role: "user", text: "canonical question", outcome: "completed"),
        .init(
          turnID: "accepted-turn", role: "assistant", text: String(repeating: "a", count: 3_000), outcome: "completed"),
      ])
    let normal = try jsonObject(event, sharing: false)
    XCTAssertEqual(normal["request_id"] as? String, "successful-retry")
    XCTAssertNil(normal["conversation"])
    XCTAssertNil(normal["prompt"])
    let selected = try jsonObject(event, sharing: true)
    let conversation = try XCTUnwrap(selected["conversation"] as? [[String: Any]])
    XCTAssertEqual(conversation.count, 2)
    XCTAssertEqual(conversation[0]["text"] as? String, "canonical question")
    XCTAssertEqual((conversation[1]["text"] as? String)?.count, 2_000)
    for key in ["prompt", "screen", "profile", "memories", "tools", "audio"] { XCTAssertNil(selected[key]) }
  }

  func testChatFeedbackRetainsActualRequestCorrelation() throws {
    let event = AIEvaluationObservation.score(
      sessionID: "session", turnID: "turn", decisionID: nil, value: 1, requestID: "actual-request")
    let json = try jsonObject(event, sharing: false)
    XCTAssertEqual(json["request_id"] as? String, "actual-request")
    XCTAssertEqual(json["value"] as? Int, 1)
    XCTAssertNil(json["conversation"])
  }

  private var prompt: AIManagedPrompt {
    AIManagedPrompt(text: "prompt instruction", name: "intentive-live-system", version: "7", source: "langfuse")
  }

  private func jsonObject(_ event: AIEvaluationObservation, sharing: Bool) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: event.encoded(sharing: sharing)) as? [String: Any])
  }
}
