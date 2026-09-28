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

  func testFinalOnlySupervisorWriteSeparatesAcceptedJournalFromEveryDeliveryOutcome() throws {
    let projection = RealtimeStreamingJournalProjection(
      ownerID: "owner-fixture", continuityKey: "supervisor:decision-fixture",
      admissionSurface: .realtimeVoice(chatId: "chat-fixture"))
    let expected: [(AIVoiceTurnOutcome, String?)] = [
      (.completed, nil), (.cancelled, "Interrupted"),
      (.failed, "Voice reply incomplete"), (.suppressed, "Not spoken"),
    ]
    for (outcome, label) in expected {
      let terminal = projection.terminalAssistantTurn(text: "Generated assistant reply", deliveryOutcome: outcome)
      let write = terminal.message.journalWrite(
        origin: "realtime_voice", status: terminal.status,
        continuityKey: projection.continuityKey, messageSource: projection.messageSource)
      let metadata = try metadataObject(write.metadataJSON)
      XCTAssertEqual(write.role, "assistant")
      XCTAssertEqual(write.status, .completed, "Accepted journal storage does not assert complete playback")
      XCTAssertEqual(write.turnId, projection.assistantTurnID)
      XCTAssertEqual(metadata["voiceDeliveryOutcome"] as? String, outcome.rawValue)
      XCTAssertEqual(Set(metadata.keys), ["continuityKey", "messageSource", "voiceDeliveryOutcome"])

      let replayed = try XCTUnwrap(KernelJournalTurn(dictionary: write.dictionary)).chatMessage()
      XCTAssertEqual(replayed.journalDeliveryStatusLabel, label)
      XCTAssertFalse(replayed.isStreaming)
    }
  }

  func testStreamingFinalizationPreservesOneAssistantIdentityAndCancelledDelivery() throws {
    let projection = RealtimeStreamingJournalProjection(
      ownerID: "owner-fixture", continuityKey: "supervisor:streamed-fixture",
      admissionSurface: .realtimeVoice(chatId: "chat-fixture"))
    let admission = projection.admissionTurns(userText: "")
    XCTAssertEqual(admission.count, 1, "An automatic turn must never fabricate a user entry")
    let pending = try XCTUnwrap(admission.first)
    XCTAssertTrue(pending.message.isStreaming)
    XCTAssertNil(pending.message.voiceDeliveryOutcome, "Generated text is not proof of playback")

    let terminal = projection.terminalAssistantTurn(text: "Partly spoken reply", deliveryOutcome: .cancelled)
    let update = terminal.message.journalUpdate(status: terminal.status)
    let metadata = try metadataObject(XCTUnwrap(update.metadataJSON))
    XCTAssertEqual(update.turnId, pending.message.id)
    XCTAssertEqual(update.status, .completed)
    XCTAssertEqual(metadata["voiceDeliveryOutcome"] as? String, "cancelled")
    XCTAssertEqual(metadata["continuityKey"] as? String, "supervisor:streamed-fixture")
    XCTAssertEqual(metadata["messageSource"] as? String, "supervisor")
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
