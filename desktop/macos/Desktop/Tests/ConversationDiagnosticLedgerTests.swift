import XCTest

@testable import Omi_Computer

final class ConversationDiagnosticLedgerTests: XCTestCase {
  func testOnlyAdmittedCurrentConversationPCMCountsAndCloseRetainsMetadata() {
    var ledger = ConversationDiagnosticLedger<String>()
    ledger.begin(owner: "owner-epoch-1", generation: 4, conversationID: "logical-one")
    ledger.recordProcessedPCM(byteCount: 3200, owner: "owner-epoch-1", generation: 4)
    ledger.recordProcessedPCM(byteCount: 6400, owner: "owner-epoch-1", generation: 3)
    ledger.recordProcessedPCM(byteCount: 6400, owner: "owner-epoch-2", generation: 4)
    ledger.recordProcessedPCM(byteCount: 0, owner: "owner-epoch-1", generation: 4)
    var snapshot = ledger.snapshot(owner: "owner-epoch-1")
    XCTAssertEqual(snapshot.acceptedProcessedPCMBytes, 3200)
    XCTAssertEqual(snapshot.acceptedProcessedPCMChunks, 1)
    ledger.close(owner: "owner-epoch-1", generation: 4)
    ledger.recordProcessedPCM(byteCount: 6400, owner: "owner-epoch-1", generation: 4)
    snapshot = ledger.snapshot(owner: "owner-epoch-1")
    XCTAssertEqual(snapshot.state, "closed")
    XCTAssertEqual(snapshot.logicalConversationID, "logical-one")
    XCTAssertEqual(snapshot.acceptedProcessedPCMBytes, 3200)
  }
  func testDeliveryReceiptsRequireCurrentTurnAndCountEachTerminalOnce() {
    var ledger = ConversationDiagnosticLedger<String>()
    ledger.begin(owner: "owner-epoch-1", generation: 4, conversationID: "logical-one")
    ledger.beginTurn(id: "first", owner: "owner-epoch-1", generation: 4)
    ledger.recordDelivery(
      turnID: "first", outcome: .interrupted, renderObserved: true,
      playbackDrainObserved: false, owner: "owner-epoch-1", generation: 4)
    ledger.beginTurn(id: "second", owner: "owner-epoch-1", generation: 4)
    ledger.recordDelivery(
      turnID: "first", outcome: .completed, renderObserved: true,
      playbackDrainObserved: true, owner: "owner-epoch-1", generation: 4)
    ledger.recordDelivery(
      turnID: "second", outcome: .completed, renderObserved: true,
      playbackDrainObserved: true, owner: "owner-epoch-2", generation: 4)
    ledger.recordDelivery(
      turnID: "second", outcome: .completed, renderObserved: true,
      playbackDrainObserved: true, owner: "owner-epoch-1", generation: 4)
    ledger.recordDelivery(
      turnID: "second", outcome: .completed, renderObserved: true,
      playbackDrainObserved: true, owner: "owner-epoch-1", generation: 4)
    let snapshot = ledger.snapshot(owner: "owner-epoch-1")
    XCTAssertEqual(snapshot.interruptedCount, 1)
    XCTAssertEqual(snapshot.completedCount, 1)
    XCTAssertEqual(snapshot.failedCount, 0)
    XCTAssertEqual(snapshot.lastDelivery?.turnID, "second")
    XCTAssertEqual(snapshot.lastDelivery?.outcome, .completed)
    XCTAssertEqual(snapshot.lastDelivery?.renderObserved, true)
    XCTAssertEqual(snapshot.lastDelivery?.playbackDrainObserved, true)
  }

  func testInputCountersSaturateInsteadOfGrowingWithoutLimit() {
    var ledger = ConversationDiagnosticLedger<String>()
    ledger.begin(owner: "owner-epoch-1", generation: 4, conversationID: "logical-one")
    ledger.recordProcessedPCM(byteCount: 2_000_000_000_000, owner: "owner-epoch-1", generation: 4)
    ledger.recordProcessedPCM(byteCount: 3200, owner: "owner-epoch-1", generation: 4)
    XCTAssertEqual(ledger.snapshot(owner: "owner-epoch-1").acceptedProcessedPCMBytes, 1_000_000_000_000)
  }

  func testSnapshotBoundsMetadataAndClearsItForReauthenticatedOwnerEpoch() throws {
    var ledger = ConversationDiagnosticLedger<String>()
    ledger.begin(owner: "account-one-epoch-1-private", generation: 4, conversationID: "logical-one")
    let long = String(repeating: "a", count: 500)
    ledger.updateMetadata(
      logicalID: long, journalID: "journal-one", connectionID: "connection-one",
      prompt: .init(name: long, version: long, source: long, sha256: long),
      owner: "account-one-epoch-1-private", generation: 4)
    ledger.updateRuntime(
      state: "open", route: "live", microphoneAvailable: true,
      userSpeaking: true, listening: true, rendering: false,
      owner: "account-one-epoch-1-private", generation: 4)
    ledger.close(owner: "account-one-epoch-1-private", generation: 4)
    let saved = ledger.snapshot(owner: "account-one-epoch-1-private")
    XCTAssertEqual(saved.logicalConversationID?.count, 128)
    XCTAssertEqual(saved.promptReference?.name.count, 128)
    XCTAssertEqual(saved.promptReference?.version.count, 128)
    XCTAssertEqual(saved.promptReference?.source.count, 32)
    XCTAssertEqual(saved.promptReference?.sha256.count, 64)
    XCTAssertFalse(saved.microphoneAvailable)
    XCTAssertFalse(saved.listening)
    let encoded = try JSONEncoder().encode(saved)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(object["state"] as? String, "closed")
    XCTAssertEqual(object["journalID"] as? String, "journal-one")
    XCTAssertNil(object["owner"])
    XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("account-one-epoch-1-private"))
    let reference = try XCTUnwrap(object["promptReference"] as? [String: Any])
    XCTAssertEqual(Set(reference.keys), Set(["name", "version", "source", "sha256"]))
    XCTAssertEqual(ledger.snapshot(owner: "account-one-epoch-2-private"), ConversationDiagnosticSnapshot())
    XCTAssertEqual(
      ledger.snapshot(owner: "account-one-epoch-1-private"), ConversationDiagnosticSnapshot(),
      "Old metadata stays cleared even if the prior caller appears again")
  }

}
