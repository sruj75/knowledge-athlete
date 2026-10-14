import XCTest

@testable import Omi_Computer

@MainActor
final class SupervisorVoiceDeliveryJournalTests: XCTestCase {
  func testInterruptedAssistantJournalRoundTripRetainsDeliveryAndCorrelation() throws {
    let metadata = """
      {"continuityKey":"supervisor:decision-fixture","messageSource":"supervisor",
       "sessionId":"session-fixture","voiceDeliveryOutcome":"cancelled"}
      """
    let turn = try XCTUnwrap(
      KernelJournalTurn(dictionary: [
        "turnId": "assistant-fixture", "role": "assistant", "content": "A generated reply",
        "origin": "realtime_voice", "status": "completed", "metadataJson": metadata,
      ]))

    let replayed = turn.chatMessage()
    let written = replayed.journalWrite(origin: "realtime_voice", status: .completed)
    let retained = try metadataObject(written.metadataJSON)
    XCTAssertEqual(retained["voiceDeliveryOutcome"] as? String, "cancelled")
    XCTAssertEqual(retained["continuityKey"] as? String, "supervisor:decision-fixture")
    XCTAssertEqual(retained["messageSource"] as? String, "supervisor")
    XCTAssertEqual(retained["sessionId"] as? String, "session-fixture")
    XCTAssertFalse(replayed.isStreaming)
    XCTAssertEqual(replayed.journalDeliveryStatusLabel, "Interrupted")

    let updated = try metadataObject(XCTUnwrap(replayed.journalUpdate(status: .completed).metadataJSON))
    XCTAssertEqual(updated["voiceDeliveryOutcome"] as? String, "cancelled")
    XCTAssertEqual(updated["continuityKey"] as? String, "supervisor:decision-fixture")
    XCTAssertEqual(updated["messageSource"] as? String, "supervisor")
    XCTAssertEqual(updated["sessionId"] as? String, "session-fixture")
  }

  func testActualJournalFailureKeepsWarningEvenWhenDeliveryWasInterruptedOrCompleted() {
    for outcome in [AIVoiceTurnOutcome.cancelled, .completed, .failed, .suppressed] {
      let message = ChatMessage(
        text: "Generated reply", sender: .ai, journalStatus: .failed, voiceDeliveryOutcome: outcome)
      XCTAssertEqual(message.journalDeliveryStatusLabel, "Couldn't save this reply")
    }
    let legacy = ChatMessage(text: "Legacy failed reply", sender: .ai, journalStatus: .failed)
    XCTAssertEqual(legacy.journalDeliveryStatusLabel, "Couldn't save this reply")
  }

  func testUnknownDeliveryMetadataCannotClaimCompletedPlayback() throws {
    let turn = try XCTUnwrap(
      KernelJournalTurn(dictionary: [
        "turnId": "unknown-outcome", "role": "assistant", "content": "Generated reply",
        "status": "completed", "metadataJson": "{\"voiceDeliveryOutcome\":\"delivered_probably\"}",
      ]))
    let replayed = turn.chatMessage()
    XCTAssertNil(replayed.voiceDeliveryOutcome)
    let written = replayed.journalWrite(origin: "realtime_voice", status: .completed)
    XCTAssertNil(try metadataObject(written.metadataJSON)["voiceDeliveryOutcome"])
  }

  private func metadataObject(_ raw: String) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
  }
}
