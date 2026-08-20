import Foundation
import XCTest

@testable import Omi_Computer

final class OneAssistantChatContractTests: XCTestCase {
  private struct QueryProbeStop: Error {}

  private actor JournalAdmissionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
      await withCheckedContinuation { continuation = $0 }
    }

    func open() {
      continuation?.resume()
      continuation = nil
    }
  }

  private final class QueryCapture: @unchecked Sendable {
    var invocation: AgentClient.QueryTransportRequest?
    var createdChatID: String?
    var events: [String] = []
    var deletedChatIDs: [String] = []
  }

  @MainActor
  func testNewChatSendsPersonalizedExplicitAttachmentThroughOneAssistantPath() async throws {
    let defaults = UserDefaults.standard
    let previousGivenName = defaults.string(forKey: DefaultsKey.authGivenName)
    let previousOwnerID = defaults.string(forKey: .authUserId)
    defer {
      ChatDraftStore.shared.clearAll(ownerID: "s06-one-assistant-test")
      ChatDraftStore.shared.flush()
      if let previousGivenName {
        defaults.set(previousGivenName, forKey: DefaultsKey.authGivenName)
      } else {
        defaults.removeObject(forKey: DefaultsKey.authGivenName)
      }
      if let previousOwnerID {
        defaults.set(previousOwnerID, forKey: .authUserId)
      } else {
        defaults.removeObject(forKey: .authUserId)
      }
    }
    defaults.set("Srujan", forKey: DefaultsKey.authGivenName)
    defaults.set("s06-one-assistant-test", forKey: .authUserId)

    let profile = try XCTUnwrap(
      AgentExecutionProfile(dictionary: [
        "profileGeneration": 1,
        "adapterId": "acp",
        "credentialScope": "local_user",
        "modelProfile": "test-model",
        "workingDirectory": "/tmp",
        "executionRole": "coordinator",
      ]))
    let agentSession = AgentSurfaceSession(
      created: true,
      conversationId: "conversation-1",
      sessionId: "agent-session-1",
      profile: profile
    )
    let contextSnapshot = try XCTUnwrap(
      AgentContextSnapshot(dictionary: [
        "snapshotId": "snapshot-1",
        "version": "context-v1",
        "snapshotGeneration": 1,
        "rendererPolicyVersion": "renderer-v1",
        "rendererFingerprint": "renderer-fingerprint-1",
        "capabilityVersion": "capability-v1",
        "renderedContext": "retained personal context",
        "ownerId": "s06-one-assistant-test",
        "sessionId": agentSession.sessionId,
        "conversationId": agentSession.conversationId,
        "recentTurns": [[String: Any]](),
        "sourceOutcomes": [[String: Any]](),
        "activeRuns": [[String: Any]](),
        "capabilities": [
          "executionRole": "coordinator",
          "manifestVersion": 1,
          "manifestDigest": "manifest-1",
          "allowedToolNames": ["read_file"],
        ],
        "contextPlan": [
          "version": 1,
          "planId": "plan-1",
          "semanticGuidanceVersion": "guidance-v1",
          "semanticGuidance": "",
          "retainedTurnCount": 0,
          "totalTurnCount": 0,
          "omittedTurnCount": 0,
          "olderHistoryStrategy": "none",
          "stableCacheIdentity": "stable-1",
          "dynamicContextIdentity": "dynamic-1",
        ],
      ]))

    let provider = ChatProvider()
    provider.multiChatEnabled = true
    let capture = QueryCapture()
    provider.agentClientForTests = AgentClient.Session(harnessMode: "piMono") {
      _, request, _ in
      capture.events.append("query")
      capture.invocation = request
      throw QueryProbeStop()
    }
    provider.runtimeOwnerIdForTests = { "s06-one-assistant-test" }
    provider.createChatCatalogForTests = { chatID, title in
      capture.events.append("create_catalog")
      capture.createdChatID = chatID
      return try XCTUnwrap(
        LocalChatSummary(dictionary: [
          "chatId": chatID,
          "title": title ?? "New Chat",
          "titleOrigin": "default",
          "messageCount": 0,
          "createdAtMs": 1_000,
          "lastActivityAtMs": 1_000,
          "starred": false,
        ]))
    }
    let greeting = "Welcome back, Srujan — what would you like to work on?"
    provider.listChatCatalogForTests = {
      let createdChatID = try XCTUnwrap(capture.createdChatID)
      return [
        try XCTUnwrap(
          LocalChatSummary(dictionary: [
            "chatId": "default",
            "title": "New Chat",
            "titleOrigin": "default",
            "messageCount": 0,
            "createdAtMs": 1_000,
            "lastActivityAtMs": 1_000,
            "starred": false,
          ])),
        try XCTUnwrap(
          LocalChatSummary(dictionary: [
            "chatId": createdChatID,
            "title": "Fresh chat",
            "titleOrigin": "manual",
            "preview": greeting,
            "messageCount": 1,
            "createdAtMs": 1_000,
            "lastActivityAtMs": 2_000,
            "starred": false,
          ])),
      ]
    }
    provider.initialMessageForTests = { profileText, memories, ownerID in
      capture.events.append("initial_message")
      XCTAssertTrue(profileText.isEmpty)
      XCTAssertTrue(memories.isEmpty)
      XCTAssertEqual(ownerID, "s06-one-assistant-test")
      return InitialMessageResponse(message: greeting)
    }
    provider.recordInitialGreetingForTests = { [weak provider] surface, turn, ownerID in
      capture.events.append("record_greeting")
      XCTAssertEqual(surface.surfaceKind, "main_chat")
      XCTAssertEqual(surface.externalRefId, capture.createdChatID)
      XCTAssertEqual(turn.sender, .ai)
      XCTAssertEqual(turn.text, greeting)
      XCTAssertEqual(ownerID, "s06-one-assistant-test")
      provider?.messages = [
        ChatMessage(
          id: turn.id,
          text: greeting,
          sender: .ai,
          isSynced: true,
          journalStatus: .completed
        )
      ]
      return true
    }
    provider.ensureBridgeStartedForTests = { _ in
      capture.events.append("ensure_bridge")
      return true
    }
    provider.resolveKernelQuerySessionForTests = { _, _ in
      capture.events.append("resolve_session")
      return agentSession
    }
    provider.prepareKernelQueryContextForTests = { _, _ in
      capture.events.append("prepare_context")
      return (agentSession, contextSnapshot)
    }
    provider.warmupKernelQuerySessionForTests = { _ in
      capture.events.append("warmup")
    }
    provider.refreshMemoriesForPromptForTests = {
      capture.events.append("refresh_memories")
    }
    provider.recordStreamingJournalExchangeForTests = { userMessage, assistantMessage in
      capture.events.append("record_exchange")
      return [userMessage, assistantMessage]
    }
    let createdSession = await provider.createNewSession(title: "Fresh chat")
    let session = try XCTUnwrap(createdSession)
    XCTAssertEqual(provider.messages.map(\.text), [greeting])
    XCTAssertEqual(provider.messages.map(\.sender), [.ai])
    let fileURL = URL(fileURLWithPath: "/tmp/selected-notes.txt")
    let attachment = ChatAttachment(
      id: "local-file-1",
      fileName: "selected-notes.txt",
      mimeType: "text/plain",
      localFileURL: fileURL,
      state: .localOnly
    )
    let prompt = "Summarize my selected notes"
    provider.pendingAttachments = [attachment]
    provider.draftText = prompt

    let response = await provider.sendMainDraft(prompt)
    let invocation = try XCTUnwrap(
      capture.invocation,
      "events=\(capture.events) error=\(provider.errorMessage ?? "nil") messages=\(provider.messages.count)"
    )
    let requestAttachment = try XCTUnwrap(invocation.attachments.first)
    let requestPayload = requestAttachment.dictionary

    XCTAssertNil(response)
    XCTAssertEqual(session.id, capture.createdChatID)
    XCTAssertEqual(session.title, "Fresh chat")
    XCTAssertEqual(provider.currentSession?.id, capture.createdChatID)
    XCTAssertEqual(provider.sessions.map(\.id), ["default", capture.createdChatID])
    XCTAssertNil(provider.onboardingOpener)
    XCTAssertEqual(provider.sessions.first(where: { $0.id == session.id })?.preview, greeting)
    XCTAssertEqual(
      capture.events,
      [
        "create_catalog",
        "refresh_memories",
        "initial_message",
        "record_greeting",
        "ensure_bridge",
        "resolve_session",
        "record_exchange",
        "refresh_memories",
        "prepare_context",
        "warmup",
        "query",
      ]
    )
    XCTAssertEqual(invocation.prompt, prompt)
    XCTAssertEqual(invocation.session, agentSession)
    XCTAssertEqual(invocation.surface.surfaceKind, "main_chat")
    XCTAssertEqual(invocation.surface.externalRefId, capture.createdChatID)
    XCTAssertEqual(invocation.mode, ChatMode.act.rawValue)
    XCTAssertEqual(invocation.reasoningEffort, "adaptive")
    XCTAssertEqual(requestAttachment.attachmentId, "local-file-1")
    XCTAssertEqual(requestAttachment.displayName, "selected-notes.txt")
    XCTAssertEqual(requestAttachment.mimeType, "text/plain")
    XCTAssertEqual(requestAttachment.uri, fileURL.absoluteString)
    XCTAssertEqual(
      Set(requestPayload.keys),
      ["attachmentId", "displayName", "mimeType", "uri"]
    )
    XCTAssertTrue(provider.pendingAttachments.isEmpty)
    XCTAssertTrue(provider.draftText.isEmpty)
    XCTAssertFalse(requestPayload.keys.contains("app_id"))
    XCTAssertFalse(requestPayload.keys.contains("persona_id"))
    XCTAssertFalse(requestPayload.keys.contains("marketplace_id"))

    let failedAttachment = ChatAttachment(
      id: "local-file-2",
      fileName: "retry-notes.txt",
      mimeType: "text/plain",
      localFileURL: URL(fileURLWithPath: "/tmp/retry-notes.txt"),
      state: .localOnly
    )
    let admissionStarted = expectation(description: "journal admission started")
    let admissionGate = JournalAdmissionGate()
    provider.recordStreamingJournalExchangeForTests = { _, _ in
      admissionStarted.fulfill()
      await admissionGate.wait()
      return nil
    }
    provider.pendingAttachments = [failedAttachment]
    provider.draftText = "This send must stay recoverable"

    let failedSend = Task { @MainActor in
      await provider.sendMainDraft("This send must stay recoverable")
    }
    await fulfillment(of: [admissionStarted], timeout: 2)

    provider.removePendingAttachment(id: failedAttachment.id)
    XCTAssertEqual(provider.pendingAttachments.map(\.id), [failedAttachment.id])
    let otherChat = ChatSession(id: "other-chat", title: "Other")
    provider.sessions.append(otherChat)
    provider.deleteChatCatalogForTests = { chatID in
      capture.deletedChatIDs.append(chatID)
      return []
    }
    await provider.deleteSession(otherChat)
    XCTAssertTrue(capture.deletedChatIDs.isEmpty)
    XCTAssertTrue(provider.sessions.contains(where: { $0.id == otherChat.id }))

    await admissionGate.open()
    _ = await failedSend.value
    XCTAssertEqual(provider.pendingAttachments.map(\.id), [failedAttachment.id])
    XCTAssertEqual(provider.draftText, "This send must stay recoverable")
    XCTAssertEqual(provider.errorMessage, "Could not save this message. Try again.")
  }
}
