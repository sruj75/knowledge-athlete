import XCTest

@testable import Omi_Computer

final class AgentRuntimeProcessTests: XCTestCase {
  func testOutOfOrderStdoutChunksPreserveJSONLOrderAndIgnoreDuplicates() {
    var buffer = AgentRuntimeOrderedStdoutBuffer()
    XCTAssertEqual(buffer.ingest(Data("second\n".utf8), sequence: 1), [])
    XCTAssertEqual(
      buffer.ingest(Data("first\n".utf8), sequence: 0).map { String(decoding: $0, as: UTF8.self) }, ["first", "second"])
    XCTAssertEqual(buffer.ingest(Data("duplicate\n".utf8), sequence: 1), [])
    buffer.reset()
    XCTAssertEqual(buffer.ingest(Data("new\n".utf8), sequence: 0).count, 1)
  }
  func testEmptyJournalReceiptRetainsGenerationForFutureWriteAdmission() throws {
    let receipt = try AgentBridge.journalResult(
      [
        "operation": "list", "conversationId": "chat", "conversationGeneration": 7,
        "generationBaseTurnSeq": 20, "highWaterTurnSeq": 20, "turns": [],
      ], surface: .mainChat(chatId: "default"))
    XCTAssertEqual(receipt.conversationGeneration, 7)
    XCTAssertEqual(receipt.generationBaseTurnSeq, 20)
    XCTAssertTrue(receipt.turns.isEmpty)
  }
  func testJournalReceiptRejectsMissingGenerationRatherThanAssumingFreshHistory() {
    XCTAssertThrowsError(
      try AgentBridge.journalResult(
        [
          "operation": "list", "conversationId": "chat", "turns": [],
        ], surface: .mainChat(chatId: "default")))
  }
  func testStateDirectoryPreservesExistingDatabaseAuthority() throws {
    let path = try AgentRuntimeProcess.defaultStateDirectory(
      bundleIdentifier: "com.heyintentive.intentive", homeDirectory: URL(fileURLWithPath: "/tmp/owner"))
    XCTAssertTrue(path.hasSuffix("/AgentRuntime"))
    XCTAssertTrue(path.hasPrefix("/tmp/owner/Library/Application Support/"))
  }
}
