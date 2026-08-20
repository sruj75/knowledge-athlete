import XCTest

@testable import Omi_Computer

final class LocalChatCatalogTests: XCTestCase {
  func testSummaryDecodesTheKernelCatalogReceipt() throws {
    let summary = try XCTUnwrap(
      LocalChatSummary(dictionary: [
        "chatId": "chat-a",
        "title": "Local decisions",
        "titleOrigin": "manual",
        "preview": "Keep Chat local",
        "messageCount": 2,
        "createdAtMs": 1_000,
        "lastActivityAtMs": 2_000,
        "starred": true,
      ]))

    XCTAssertEqual(summary.chatID, "chat-a")
    XCTAssertEqual(summary.titleOrigin, .manual)
    XCTAssertEqual(summary.chatSession.preview, "Keep Chat local")
    XCTAssertEqual(summary.chatSession.messageCount, 2)
    XCTAssertTrue(summary.chatSession.starred)
  }

  func testCatalogWireOperationsCarryOnlyOwnerScopedCatalogInputs() {
    let list = AgentRuntimeProcess.chatCatalogWireMessage(
      operation: .list,
      clientId: "main-chat",
      requestId: "list-1",
      ownerID: "owner-a"
    )
    let create = AgentRuntimeProcess.chatCatalogWireMessage(
      operation: .create,
      clientId: "main-chat",
      requestId: "create-1",
      ownerID: "owner-a",
      chatID: "chat-a"
    )
    let update = AgentRuntimeProcess.chatCatalogWireMessage(
      operation: .update,
      clientId: "main-chat",
      requestId: "update-1",
      ownerID: "owner-a",
      chatID: "chat-a",
      title: "Manual title",
      titleOrigin: .manual,
      expectedTitleOrigin: .automatic,
      starred: true
    )
    let delete = AgentRuntimeProcess.chatCatalogWireMessage(
      operation: .delete,
      clientId: "main-chat",
      requestId: "delete-1",
      ownerID: "owner-a",
      chatID: "chat-a"
    )

    XCTAssertEqual(list["type"] as? String, "chat_catalog_list")
    XCTAssertNil(list["chatId"])
    XCTAssertEqual(create["chatId"] as? String, "chat-a")
    XCTAssertEqual(update["titleOrigin"] as? String, "manual")
    XCTAssertEqual(update["expectedTitleOrigin"] as? String, "automatic")
    XCTAssertEqual(update["starred"] as? Bool, true)
    XCTAssertEqual(delete["type"] as? String, "chat_catalog_delete")
    for message in [list, create, update, delete] {
      XCTAssertEqual(message["ownerId"] as? String, "owner-a")
      XCTAssertNil(message["sessionId"])
      XCTAssertNil(message["messages"])
    }
  }

  @MainActor
  func testCreateRetryReusesTheCallerGeneratedChatIdentity() async throws {
    let provider = ChatProvider()
    var attemptedChatIDs: [String] = []
    provider.createChatCatalogForTests = { chatID, _ in
      attemptedChatIDs.append(chatID)
      if attemptedChatIDs.count == 1 { throw URLError(.timedOut) }
      return try XCTUnwrap(
        LocalChatSummary(dictionary: [
          "chatId": chatID,
          "title": "New Chat",
          "titleOrigin": "default",
          "preview": "",
          "messageCount": 0,
          "createdAtMs": 1,
          "lastActivityAtMs": 1,
          "starred": false,
        ]))
    }

    let firstAttempt = await provider.createNewSession(skipGreeting: true)
    let retry = await provider.createNewSession(skipGreeting: true)
    XCTAssertNil(firstAttempt)
    XCTAssertNotNil(retry)
    XCTAssertEqual(attemptedChatIDs.count, 2)
    XCTAssertEqual(attemptedChatIDs[0], attemptedChatIDs[1])
  }

  func testAutomaticTitleEligibilityRequiresNoCompletedRealExchange() {
    let failedFirstAttempt = [
      ChatMessage(
        text: "First question",
        sender: .user,
        journalStatus: .completed
      ),
      ChatMessage(
        text: "Partial answer",
        sender: .ai,
        journalStatus: .failed
      ),
    ]
    let completedPair =
      failedFirstAttempt + [
        ChatMessage(
          text: "Second question",
          sender: .user,
          journalStatus: .completed
        ),
        ChatMessage(
          text: "Completed answer",
          sender: .ai,
          journalStatus: .completed
        ),
      ]

    XCTAssertFalse(ChatProvider.hasCompletedRealExchange(failedFirstAttempt))
    XCTAssertTrue(ChatProvider.hasCompletedRealExchange(completedPair))
  }
}
