import Foundation
import XCTest

@testable import Omi_Computer

final class OneAssistantChatContractTests: XCTestCase {
  private struct QueryProbeStop: Error {}

  private final class QueryCapture: @unchecked Sendable {
    var invocation: AgentClient.QueryTransportRequest?
    var events: [String] = []
  }

  @MainActor
  func testNewChatSendsPersonalizedExplicitAttachmentThroughOneAssistantPath() async throws {
    let defaults = UserDefaults.standard
    let previousGivenName = defaults.string(forKey: DefaultsKey.authGivenName)
    defer {
      if let previousGivenName {
        defaults.set(previousGivenName, forKey: DefaultsKey.authGivenName)
      } else {
        defaults.removeObject(forKey: DefaultsKey.authGivenName)
      }
    }
    defaults.set("Srujan", forKey: DefaultsKey.authGivenName)

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
    let capture = QueryCapture()
    provider.agentClientForTests = AgentClient.Session(harnessMode: "piMono") {
      _, request, _ in
      capture.events.append("query")
      capture.invocation = request
      throw QueryProbeStop()
    }
    provider.runtimeOwnerIdForTests = { "s06-one-assistant-test" }
    provider.createChatSessionForTests = { title in
      capture.events.append("create_session")
      return ChatSession(id: "session-1", title: title ?? "New Chat")
    }
    let greeting = "Welcome back, Srujan — what would you like to work on?"
    provider.initialMessageForTests = { sessionID, ownerID in
      capture.events.append("initial_message")
      XCTAssertEqual(sessionID, "session-1")
      XCTAssertEqual(ownerID, "s06-one-assistant-test")
      return InitialMessageResponse(message: greeting, messageId: "greeting-1")
    }
    provider.importInitialGreetingForTests = { surface, turn, ownerID in
      capture.events.append("import_greeting")
      XCTAssertEqual(surface.surfaceKind, "main_chat")
      XCTAssertEqual(surface.externalRefId, "session-1")
      XCTAssertEqual(turn.remoteId, "greeting-1")
      XCTAssertEqual(turn.canonicalTurnId, "greeting-1")
      XCTAssertEqual(turn.role, "assistant")
      XCTAssertEqual(turn.content, greeting)
      XCTAssertEqual(ownerID, "s06-one-assistant-test")
      return true
    }
    provider.refreshInitialGreetingForTests = { [weak provider] surface in
      capture.events.append("refresh_greeting")
      XCTAssertEqual(surface.surfaceKind, "main_chat")
      XCTAssertEqual(surface.externalRefId, "session-1")
      provider?.messages = [
        ChatMessage(
          id: "greeting-1",
          text: greeting,
          sender: .ai,
          isSynced: true,
          journalStatus: .completed
        )
      ]
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
    XCTAssertEqual(session.id, "session-1")
    XCTAssertEqual(session.title, "Fresh chat")
    XCTAssertEqual(provider.currentSession?.id, "session-1")
    XCTAssertEqual(provider.sessions.map(\.id), ["session-1"])
    XCTAssertNil(provider.onboardingOpener)
    XCTAssertEqual(provider.sessions.first?.preview, greeting)
    XCTAssertEqual(
      capture.events,
      [
        "create_session",
        "initial_message",
        "import_greeting",
        "refresh_greeting",
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
    XCTAssertEqual(invocation.surface.externalRefId, "session-1")
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
  }
}
