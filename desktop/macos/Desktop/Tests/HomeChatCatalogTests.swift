import XCTest

@testable import Omi_Computer

private struct StubHomeSuggestionLocalSources: HomeSuggestionLocalSources {
  let memories: String?
  let conversations: String?
  let tasks: String?
  let goals: String?

  func memoryContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? { memories }
  func conversationContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? { conversations }
  func taskContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? { tasks }
  func goalContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? { goals }
}

final class HomeChatCatalogTests: XCTestCase {
  private enum CatalogTestError: Error { case unavailable }

  private actor GreetingGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
      await withCheckedContinuation { continuation = $0 }
    }

    func open() {
      continuation?.resume()
      continuation = nil
    }
  }

  private func goal(id: Int64, title: String) -> LocalGoal {
    LocalGoal(
      id: "local_\(id)",
      rowID: id,
      title: title,
      description: nil,
      isActive: true,
      completedAt: nil,
      createdAt: .distantPast,
      updatedAt: .distantPast
    )
  }

  private func task(id: Int64, description: String) -> TaskActionItem {
    TaskActionItem(
      id: "local_\(id)",
      description: description,
      completed: false,
      createdAt: .distantPast
    )
  }

  private final class DeletionProbe: @unchecked Sendable {
    var deletedChatIDs: [String] = []
  }

  private func summary(
    id: String,
    title: String = "New Chat",
    titleOrigin: String = "default",
    starred: Bool = false,
    preview: String? = nil,
    messageCount: Int = 0,
    lastActivityAtMs: Int64 = 1_000
  ) throws -> LocalChatSummary {
    var dictionary: [String: Any] = [
      "chatId": id,
      "title": title,
      "titleOrigin": titleOrigin,
      "messageCount": messageCount,
      "createdAtMs": 1_000,
      "lastActivityAtMs": lastActivityAtMs,
      "starred": starred,
    ]
    if let preview { dictionary["preview"] = preview }
    return try XCTUnwrap(LocalChatSummary(dictionary: dictionary))
  }

  func testCanonicalHomeOwnsTheCompleteCatalogAndDuplicatePageIsGone() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let home = try String(
      contentsOf: root.appendingPathComponent("Sources/MainWindow/Pages/DashboardPage.swift"),
      encoding: .utf8
    )
    let catalog = try String(
      contentsOf: root.appendingPathComponent("Sources/MainWindow/Components/HomeChatCatalog.swift"),
      encoding: .utf8
    )

    XCTAssertTrue(home.contains("HomeChatCatalog("))
    XCTAssertTrue(home.contains(".popover(isPresented: $isChatCatalogPresented"))
    XCTAssertTrue(home.contains("await chatProvider.refreshCatalogForPresentation()"))
    XCTAssertFalse(home.contains("HomeChatCatalog(chatProvider: chatProvider)\n          .frame(maxHeight: .infinity)"))
    XCTAssertTrue(home.contains("messages: chatProvider.messages"))
    XCTAssertTrue(home.contains("ChatInputView("))
    XCTAssertTrue(catalog.contains("createNewSession()"))
    XCTAssertTrue(catalog.contains("selectSession("))
    XCTAssertTrue(catalog.contains("updateSessionTitle("))
    XCTAssertTrue(catalog.contains("toggleStarred("))
    XCTAssertTrue(catalog.contains("deleteSession("))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Sources/MainWindow/Pages/ChatPage.swift").path
      )
    )
  }

  @MainActor
  func testMutationReceiptWinsOverAnOlderCatalogList() async throws {
    let provider = ChatProvider()
    let listStarted = expectation(description: "catalog list started")
    let listGate = GreetingGate()
    provider.multiChatEnabled = true
    provider.listChatCatalogForTests = {
      listStarted.fulfill()
      await listGate.wait()
      return [try self.summary(id: "default")]
    }
    provider.createChatCatalogForTests = { chatID, _ in
      try self.summary(id: chatID, title: "Receipt-backed chat")
    }

    let loading = Task { @MainActor in await provider.fetchSessions() }
    await fulfillment(of: [listStarted], timeout: 2)
    let created = await provider.createNewSession(title: "Receipt-backed chat", skipGreeting: true)
    let createdID = try XCTUnwrap(created?.id)

    await listGate.open()
    await loading.value

    XCTAssertTrue(provider.sessions.contains(where: { $0.id == createdID }))
    XCTAssertNil(provider.sessionsLoadError)
  }

  @MainActor
  func testCatalogPresentationRefreshProjectsRetainedVoiceExchangeSummary() async throws {
    let provider = ChatProvider()
    provider.multiChatEnabled = true
    var voiceExchangeRecorded = false
    provider.listChatCatalogForTests = {
      [
        try self.summary(
          id: "voice-chat",
          preview: voiceExchangeRecorded ? "Voice answer" : nil,
          messageCount: voiceExchangeRecorded ? 2 : 0,
          lastActivityAtMs: voiceExchangeRecorded ? 2_000 : 1_000
        )
      ]
    }
    provider.createChatCatalogForTests = { chatID, title in
      try self.summary(id: chatID, title: title ?? "New Chat")
    }

    await provider.fetchSessions()
    XCTAssertEqual(provider.sessions.first?.messageCount, 0)

    voiceExchangeRecorded = true
    await provider.refreshCatalogForPresentation()

    XCTAssertEqual(provider.sessions.first?.preview, "Voice answer")
    XCTAssertEqual(provider.sessions.first?.messageCount, 2)
  }

  @MainActor
  func testFirstRealVoicePairReceiptClaimsAutomaticTitle() async throws {
    let provider = ChatProvider()
    provider.multiChatEnabled = true
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.sessions = [ChatSession(id: "chat-a", title: "New Chat")]
    var titleOrigin = LocalChatTitleOrigin.defaultTitle
    var generatedInputs: [(String, String)] = []
    var expectedOrigins: [LocalChatTitleOrigin?] = []
    provider.generateTitleForTests = { userText, assistantText, _ in
      generatedInputs.append((userText, assistantText))
      return GenerateTitleResponse(title: "Voice Started Thread")
    }
    provider.updateChatCatalogForTests = { chatID, title, requestedOrigin, expectedOrigin, starred in
      expectedOrigins.append(expectedOrigin)
      titleOrigin = requestedOrigin ?? titleOrigin
      return try self.summary(
        id: chatID,
        title: title ?? "New Chat",
        titleOrigin: titleOrigin.rawValue,
        starred: starred ?? false
      )
    }

    await provider.catalogDidAcceptFirstCompletedExchange(
      chatID: "chat-a",
      ownerID: "owner-a",
      userText: "Voice question",
      assistantText: "Voice answer"
    )
    XCTAssertEqual(generatedInputs.count, 1)
    XCTAssertEqual(generatedInputs.first?.0, "Voice question")
    XCTAssertEqual(expectedOrigins, [.defaultTitle])
    XCTAssertEqual(provider.sessions.first(where: { $0.id == "chat-a" })?.title, "Voice Started Thread")
  }

  @MainActor
  func testOwnerTransitionRevokesDelayedCatalogListAndCreateReceipts() async throws {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    provider.multiChatEnabled = true
    provider.runtimeOwnerIdForTests = { ownerID }

    let listStarted = expectation(description: "owner A list started")
    let listGate = GreetingGate()
    provider.listChatCatalogForTests = {
      listStarted.fulfill()
      await listGate.wait()
      return [try self.summary(id: "owner-a-chat")]
    }
    let loading = Task { @MainActor in await provider.fetchSessions() }
    await fulfillment(of: [listStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await listGate.open()
    await loading.value
    XCTAssertTrue(provider.sessions.isEmpty)

    ownerID = "owner-a"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    let createStarted = expectation(description: "owner A create started")
    let createGate = GreetingGate()
    provider.createChatCatalogForTests = { chatID, _ in
      createStarted.fulfill()
      await createGate.wait()
      return try self.summary(id: chatID)
    }
    let creating = Task { @MainActor in
      await provider.createNewSession(title: "Owner A", skipGreeting: true)
    }
    await fulfillment(of: [createStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await createGate.open()

    let staleCreation = await creating.value
    XCTAssertNil(staleCreation)
    XCTAssertTrue(provider.sessions.isEmpty)
    XCTAssertNil(provider.currentSession)
  }

  @MainActor
  func testOwnerTransitionReleasesOldGreetingCreateLockBeforeOldRequestReturns() async throws {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    let ownerAGreetingStarted = expectation(description: "owner A greeting started")
    let ownerAGreetingGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.createChatCatalogForTests = { chatID, _ in try self.summary(id: chatID) }
    provider.refreshMemoriesForPromptForTests = {}
    provider.loadAIProfileForTests = { "" }
    provider.initialMessageForTests = { _, _, expectedOwnerID in
      XCTAssertEqual(expectedOwnerID, "owner-a")
      ownerAGreetingStarted.fulfill()
      await ownerAGreetingGate.wait()
      return InitialMessageResponse(message: "Stale owner A greeting")
    }
    provider.recordInitialGreetingForTests = { _, _, _ in true }

    let ownerACreation = Task { @MainActor in await provider.createNewSession() }
    await fulfillment(of: [ownerAGreetingStarted], timeout: 2)
    XCTAssertTrue(provider.isCreatingSession)

    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    XCTAssertFalse(provider.isCreatingSession)

    let ownerBSession = await provider.createNewSession(skipGreeting: true)
    let ownerBID = try XCTUnwrap(ownerBSession?.id)
    XCTAssertEqual(provider.currentSession?.id, ownerBID)

    await ownerAGreetingGate.open()
    let staleOwnerASession = await ownerACreation.value
    XCTAssertNil(staleOwnerASession)
    XCTAssertEqual(provider.currentSession?.id, ownerBID)
    XCTAssertFalse(provider.isCreatingSession)
  }

  @MainActor
  func testOwnerTransitionRevokesDelayedGoalPromptContext() async {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    let goalReadStarted = expectation(description: "owner A goal read started")
    let goalReadGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.refreshMemoriesForPromptForTests = {}
    provider.loadGoalsForTests = {
      goalReadStarted.fulfill()
      await goalReadGate.wait()
      return [self.goal(id: 1, title: "Owner A secret goal")]
    }
    provider.loadTasksForTests = { [] }
    provider.loadAIProfileForTests = { "" }

    let warming = Task { @MainActor in await provider.warmupPromptContext() }
    await fulfillment(of: [goalReadStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await goalReadGate.open()
    await warming.value

    XCTAssertFalse(provider.promptContextSectionsForTests().goals.contains("Owner A secret goal"))
  }

  @MainActor
  func testOwnerTransitionRevokesDelayedTaskPromptContext() async {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    let taskReadStarted = expectation(description: "owner A task read started")
    let taskReadGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.refreshMemoriesForPromptForTests = {}
    provider.loadGoalsForTests = { [] }
    provider.loadTasksForTests = {
      taskReadStarted.fulfill()
      await taskReadGate.wait()
      return [self.task(id: 1, description: "Owner A secret task")]
    }
    provider.loadAIProfileForTests = { "" }

    let warming = Task { @MainActor in await provider.warmupPromptContext() }
    await fulfillment(of: [taskReadStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await taskReadGate.open()
    await warming.value

    XCTAssertFalse(provider.promptContextSectionsForTests().tasks.contains("Owner A secret task"))
  }

  @MainActor
  func testCatalogKeepsEmptyAndDefaultChatsAndAppliesStarFilterLocally() {
    let provider = ChatProvider()
    provider.sessions = [
      ChatSession(id: "default", messageCount: 0),
      ChatSession(id: "empty-a", messageCount: 0),
      ChatSession(id: "empty-b", messageCount: 0, starred: true),
    ]

    XCTAssertEqual(provider.filteredSessions.map(\.id), ["default", "empty-a", "empty-b"])

    provider.showStarredOnly = true
    XCTAssertEqual(provider.filteredSessions.map(\.id), ["empty-b"])
  }

  func testSelectedChatPersistenceIsOwnerScoped() throws {
    let suiteName = "LocalChatSelectionStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = LocalChatSelectionStore(defaults: defaults)

    store.setSelectedChatID("chat-a", ownerID: "owner-a")

    XCTAssertEqual(store.selectedChatID(ownerID: "owner-a"), "chat-a")
    XCTAssertEqual(store.selectedChatID(ownerID: "owner-b"), "default")
    let persistedKeys = defaults.dictionaryRepresentation().keys
    XCTAssertTrue(persistedKeys.contains { $0.hasPrefix("intentive.chat.selected.v1.") })
    XCTAssertFalse(persistedKeys.contains { $0.hasPrefix("omi.chat.selected.v1.") })
  }

  @MainActor
  func testProviderDrivesCatalogSelectionRenameStarDeleteAndLoadFailure() async throws {
    let provider = ChatProvider()
    provider.multiChatEnabled = true
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { _ in true }
    provider.listChatCatalogForTests = {
      [
        try self.summary(id: "default"),
        try self.summary(id: "chat-a", title: "Alpha"),
        try self.summary(id: "chat-b", title: "Beta"),
      ]
    }
    provider.updateChatCatalogForTests = { chatID, title, titleOrigin, _, starred in
      try self.summary(
        id: chatID,
        title: title ?? (chatID == "chat-a" ? "Alpha" : "Beta"),
        titleOrigin: titleOrigin?.rawValue ?? "default",
        starred: starred ?? false
      )
    }
    let deletionProbe = DeletionProbe()
    provider.deleteChatCatalogForTests = { chatID in
      deletionProbe.deletedChatIDs.append(chatID)
      return []
    }

    await provider.fetchSessions()
    XCTAssertEqual(provider.sessions.map(\.id), ["default", "chat-a", "chat-b"])

    let chatA = try XCTUnwrap(provider.sessions.first(where: { $0.id == "chat-a" }))
    await provider.selectSession(chatA)
    XCTAssertEqual(provider.currentSession?.id, "chat-a")
    XCTAssertFalse(provider.isInDefaultChat)

    await provider.updateSessionTitle(chatA, title: "Renamed")
    XCTAssertEqual(provider.sessions.first(where: { $0.id == "chat-a" })?.title, "Renamed")

    let renamedChatA = try XCTUnwrap(provider.sessions.first(where: { $0.id == "chat-a" }))
    await provider.toggleStarred(renamedChatA)
    XCTAssertEqual(provider.sessions.first(where: { $0.id == "chat-a" })?.starred, true)

    let chatB = try XCTUnwrap(provider.sessions.first(where: { $0.id == "chat-b" }))
    await provider.deleteSession(chatB)
    XCTAssertEqual(deletionProbe.deletedChatIDs, ["chat-b"])
    XCTAssertFalse(provider.sessions.contains(where: { $0.id == "chat-b" }))

    provider.listChatCatalogForTests = { throw CatalogTestError.unavailable }
    await provider.fetchSessions()
    XCTAssertNotNil(provider.sessionsLoadError)
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        from: provider.sessionsLoadError ?? "",
        while: .chatSessions
      ),
      "Couldn't load chats. Try again."
    )
  }

  @MainActor
  func testOlderSelectionCannotCommitOrRollbackOverNewerSelection() async throws {
    let provider = ChatProvider()
    let firstSelectionStarted = expectation(description: "first selection reload started")
    let firstSelectionGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { surface in
      if surface.externalRefId == "chat-a" {
        firstSelectionStarted.fulfill()
        await firstSelectionGate.wait()
        return false
      }
      return true
    }
    let chatA = ChatSession(id: "chat-a", title: "Alpha")
    let chatB = ChatSession(id: "chat-b", title: "Beta")
    provider.sessions = [chatA, chatB]

    let selectingA = Task { @MainActor in await provider.selectSession(chatA) }
    await fulfillment(of: [firstSelectionStarted], timeout: 2)
    await provider.selectSession(chatB)
    XCTAssertEqual(provider.currentSession?.id, "chat-b")
    XCTAssertFalse(provider.isLoading)

    await firstSelectionGate.open()
    await selectingA.value

    XCTAssertEqual(provider.currentSession?.id, "chat-b")
    XCTAssertFalse(provider.isInDefaultChat)
    XCTAssertFalse(provider.isLoading)
    XCTAssertNil(provider.errorMessage)
  }

  @MainActor
  func testNewerFailedSelectionRollsBackToCommittedStateNotPendingSelection() async throws {
    let provider = ChatProvider()
    let firstSelectionStarted = expectation(description: "first selection reload started")
    let firstSelectionGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { surface in
      if surface.externalRefId == "chat-a" {
        firstSelectionStarted.fulfill()
        await firstSelectionGate.wait()
      }
      return false
    }
    let baselineMessage = ChatMessage(id: "baseline", text: "Committed default", sender: .ai)
    let chatA = ChatSession(id: "chat-a", title: "Alpha")
    let chatB = ChatSession(id: "chat-b", title: "Beta")
    provider.sessions = [chatA, chatB]
    provider.currentSession = nil
    provider.isInDefaultChat = true
    provider.messages = [baselineMessage]

    let selectingA = Task { @MainActor in await provider.selectSession(chatA) }
    await fulfillment(of: [firstSelectionStarted], timeout: 2)
    await provider.selectSession(chatB)

    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.isInDefaultChat)
    XCTAssertEqual(provider.messages.map(\.id), [baselineMessage.id])
    XCTAssertEqual(provider.errorMessage, "Failed to load chat")

    await firstSelectionGate.open()
    await selectingA.value

    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.isInDefaultChat)
    XCTAssertEqual(provider.messages.map(\.id), [baselineMessage.id])
  }

  @MainActor
  func testOwnerTransitionRevokesDelayedSingleChatHydration() async throws {
    var ownerID = "owner-a"
    var createCount = 0
    let provider = ChatProvider()
    let ownerACreateStarted = expectation(description: "owner A default create started")
    let ownerACreateGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.createChatCatalogForTests = { chatID, _ in
      createCount += 1
      if createCount == 1 {
        ownerACreateStarted.fulfill()
        await ownerACreateGate.wait()
      }
      return try self.summary(id: chatID)
    }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { _ in
      provider.messages = [
        ChatMessage(id: "owner-b-message", text: "Owner B timeline", sender: .ai)
      ]
      return true
    }

    let ownerALoad = Task { @MainActor in await provider.initializeVisibleMessages() }
    await fulfillment(of: [ownerACreateStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await provider.initializeVisibleMessages()

    XCTAssertEqual(provider.messages.map(\.id), ["owner-b-message"])
    XCTAssertFalse(provider.isLoading)
    XCTAssertNil(provider.sessionsLoadError)

    await ownerACreateGate.open()
    await ownerALoad.value

    XCTAssertEqual(provider.messages.map(\.id), ["owner-b-message"])
    XCTAssertFalse(provider.isLoading)
    XCTAssertNil(provider.sessionsLoadError)
  }

  @MainActor
  func testNewerSingleChatHydrationWinsWhenOlderLoadFailsLate() async throws {
    var createCount = 0
    let provider = ChatProvider()
    let olderCreateStarted = expectation(description: "older default create started")
    let olderCreateGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.createChatCatalogForTests = { chatID, _ in
      createCount += 1
      if createCount == 1 {
        olderCreateStarted.fulfill()
        await olderCreateGate.wait()
        throw CatalogTestError.unavailable
      }
      return try self.summary(id: chatID)
    }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { _ in
      provider.messages = [
        ChatMessage(id: "newer-message", text: "Newer timeline", sender: .ai)
      ]
      return true
    }

    let olderLoad = Task { @MainActor in await provider.initializeVisibleMessages() }
    await fulfillment(of: [olderCreateStarted], timeout: 2)
    await provider.initializeVisibleMessages()
    XCTAssertEqual(provider.messages.map(\.id), ["newer-message"])
    XCTAssertFalse(provider.isLoading)
    XCTAssertNil(provider.sessionsLoadError)

    await olderCreateGate.open()
    await olderLoad.value

    XCTAssertEqual(provider.messages.map(\.id), ["newer-message"])
    XCTAssertFalse(provider.isLoading)
    XCTAssertNil(provider.sessionsLoadError)
  }

  @MainActor
  func testOwnerTransitionDiscardsPendingSelectionRollbackBeforeNewOwnerFailure() async {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    let ownerASelectionStarted = expectation(description: "owner A selection started")
    let ownerASelectionGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { surface in
      if surface.externalRefId == "owner-a-pending" {
        ownerASelectionStarted.fulfill()
        await ownerASelectionGate.wait()
      }
      return false
    }
    provider.currentSession = ChatSession(id: "owner-a-committed")
    provider.isInDefaultChat = false
    provider.messages = [
      ChatMessage(id: "owner-a-message", text: "Owner A timeline", sender: .ai)
    ]

    let ownerASelection = Task { @MainActor in
      await provider.selectSession(ChatSession(id: "owner-a-pending"))
    }
    await fulfillment(of: [ownerASelectionStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)

    await provider.selectSession(ChatSession(id: "owner-b-chat"))

    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.isInDefaultChat)
    XCTAssertTrue(provider.messages.isEmpty)
    XCTAssertEqual(provider.errorMessage, "Failed to load chat")

    await ownerASelectionGate.open()
    await ownerASelection.value
    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.messages.isEmpty)
  }

  @MainActor
  func testStaleHarnessClearCleanupCannotReleaseNewOwnerTransaction() throws {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.beginRealtimeChatClearForTests = { _ in true }
    provider.endRealtimeChatClearForTests = { _ in }

    let ownerAAdmission = provider.beginAuthorizedHarnessClearTransaction(
      surface: .mainChat(chatId: "chat-a")
    )
    let ownerATransaction = try XCTUnwrap(ownerAAdmission.transaction)
    XCTAssertTrue(provider.isClearing)

    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    let ownerBAdmission = provider.beginAuthorizedHarnessClearTransaction(
      surface: .mainChat(chatId: "chat-b")
    )
    let ownerBTransaction = try XCTUnwrap(ownerBAdmission.transaction)
    XCTAssertTrue(provider.isClearing)

    provider.endAuthorizedHarnessClearTransaction(ownerATransaction)
    XCTAssertTrue(provider.isClearing)

    provider.endAuthorizedHarnessClearTransaction(ownerBTransaction)
    XCTAssertFalse(provider.isClearing)
  }

  @MainActor
  func testOwnerTransitionDuringHeldHarnessClearPreventsCatalogMutation() async throws {
    var ownerID = "owner-a"
    var deletedChatIDs: [String] = []
    let provider = ChatProvider()
    let session = ChatSession(id: "owner-a-chat")
    let clearStarted = expectation(description: "owner A journal clear started")
    let clearGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.beginRealtimeChatClearForTests = { _ in true }
    provider.endRealtimeChatClearForTests = { _ in }
    provider.sessions = [session]
    provider.currentSession = session
    provider.isInDefaultChat = false
    provider.deleteChatCatalogForTests = { chatID in
      deletedChatIDs.append(chatID)
      return []
    }
    provider.clearChatJournalForTests = { chatID in
      XCTAssertEqual(chatID, session.id)
      clearStarted.fulfill()
      await clearGate.wait()
      return true
    }

    let resetting = Task { @MainActor in
      await provider.resetChatForAuthorizedHarness()
    }
    await fulfillment(of: [clearStarted], timeout: 2)

    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await clearGate.open()
    let error = await resetting.value

    XCTAssertEqual(error, "owner changed during chat reset")
    XCTAssertTrue(deletedChatIDs.isEmpty)
    XCTAssertNil(provider.currentSession)
    XCTAssertFalse(provider.isClearing)
  }

  @MainActor
  func testClearIsRejectedWhileNewChatCatalogCreateIsPending() async throws {
    let provider = ChatProvider()
    let createStarted = expectation(description: "new chat catalog create started")
    let createGate = GreetingGate()
    let deletionProbe = DeletionProbe()
    provider.runtimeOwnerIdForTests = { "owner-a" }
    let existing = ChatSession(id: "chat-a", title: "Alpha")
    provider.sessions = [existing]
    provider.currentSession = existing
    provider.isInDefaultChat = false
    provider.createChatCatalogForTests = { chatID, _ in
      createStarted.fulfill()
      await createGate.wait()
      return try self.summary(id: chatID)
    }
    provider.deleteChatCatalogForTests = { chatID in
      deletionProbe.deletedChatIDs.append(chatID)
      return []
    }

    let creation = Task { @MainActor in
      await provider.createNewSession(skipGreeting: true)
    }
    await fulfillment(of: [createStarted], timeout: 2)
    await provider.clearCurrentChat()

    XCTAssertTrue(deletionProbe.deletedChatIDs.isEmpty)
    XCTAssertEqual(provider.currentSession?.id, "chat-a")
    XCTAssertEqual(
      provider.errorMessage,
      "Wait for the new chat to finish opening before clearing this chat."
    )

    await createGate.open()
    let created = await creation.value
    XCTAssertNotNil(created)
  }

  @MainActor
  func testDeletionGateRejectsSendCreateAndSelectionUntilCleanupBoundaryCompletes() async throws {
    let provider = ChatProvider()
    let deletionStarted = expectation(description: "catalog deletion started")
    let deletionGate = GreetingGate()
    provider.runtimeOwnerIdForTests = { "owner-a" }
    let chatA = ChatSession(id: "chat-a", title: "Alpha")
    let chatB = ChatSession(id: "chat-b", title: "Beta")
    provider.sessions = [chatA, chatB]
    provider.currentSession = chatA
    provider.isInDefaultChat = false
    provider.deleteChatCatalogForTests = { _ in
      deletionStarted.fulfill()
      await deletionGate.wait()
      return []
    }

    let deletion = Task { @MainActor in await provider.deleteSession(chatB) }
    await fulfillment(of: [deletionStarted], timeout: 2)

    let rejectedSend = await provider.sendMessage("Do not admit this")
    XCTAssertNil(rejectedSend)
    XCTAssertEqual(provider.errorMessage, "Wait for chat deletion to finish before sending.")
    let rejectedCreation = await provider.createNewSession(skipGreeting: true)
    XCTAssertNil(rejectedCreation)
    XCTAssertEqual(
      provider.errorMessage,
      "Wait for chat deletion to finish before creating another chat."
    )
    await provider.selectSession(chatB)
    XCTAssertEqual(provider.currentSession?.id, "chat-a")
    XCTAssertEqual(
      provider.errorMessage,
      "Wait for chat deletion to finish before switching chats."
    )

    await deletionGate.open()
    await deletion.value
    XCTAssertTrue(provider.deletingSessionIds.isEmpty)
  }

  @MainActor
  func testDeleteIsRejectedWhileNewChatGreetingIsPending() async throws {
    let provider = ChatProvider()
    let greetingStarted = expectation(description: "greeting request started")
    let greetingGate = GreetingGate()
    let deletionProbe = DeletionProbe()
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.refreshMemoriesForPromptForTests = {}
    provider.createChatCatalogForTests = { chatID, _ in
      try self.summary(id: chatID)
    }
    provider.initialMessageForTests = { _, _, _ in
      greetingStarted.fulfill()
      await greetingGate.wait()
      return InitialMessageResponse(message: "Hello")
    }
    provider.recordInitialGreetingForTests = { _, _, _ in true }
    provider.deleteChatCatalogForTests = { chatID in
      deletionProbe.deletedChatIDs.append(chatID)
      return []
    }

    let creation = Task { @MainActor in await provider.createNewSession() }
    await fulfillment(of: [greetingStarted], timeout: 2)
    let pendingSession = try XCTUnwrap(provider.currentSession)
    XCTAssertTrue(provider.isCreatingSession)

    let prematureSend = await provider.sendMessage("Too early")
    XCTAssertNil(prematureSend)
    XCTAssertEqual(
      provider.errorMessage,
      "Wait for the new chat to finish opening before sending."
    )

    await provider.deleteSession(pendingSession)
    XCTAssertTrue(deletionProbe.deletedChatIDs.isEmpty)
    XCTAssertTrue(provider.sessions.contains(where: { $0.id == pendingSession.id }))

    await greetingGate.open()
    _ = await creation.value
  }

  @MainActor
  func testDefaultClearKeepsStableIdentityAndHoldsVoiceBarrierUntilJournalClearCompletes() async {
    let provider = ChatProvider()
    let clearStarted = expectation(description: "default journal clear started")
    let clearGate = GreetingGate()
    var barrierSurface: AgentSurfaceReference?
    var clearedChatIDs: [String] = []
    provider.multiChatEnabled = true
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.sessions = [ChatSession(id: "default", title: "New Chat", messageCount: 2)]
    provider.messages = [ChatMessage(text: "Old answer", sender: .ai)]
    provider.beginRealtimeChatClearForTests = { surface in
      barrierSurface = surface
      return true
    }
    provider.endRealtimeChatClearForTests = { surface in
      if barrierSurface == surface { barrierSurface = nil }
    }
    provider.clearChatJournalForTests = { chatID in
      clearedChatIDs.append(chatID)
      clearStarted.fulfill()
      await clearGate.wait()
      return true
    }
    provider.listChatCatalogForTests = { [try self.summary(id: "default")] }

    let clearing = Task { @MainActor in await provider.clearCurrentChat() }
    await fulfillment(of: [clearStarted], timeout: 2)
    XCTAssertEqual(barrierSurface?.externalRefId, "default")
    XCTAssertTrue(provider.isClearing)

    await clearGate.open()
    await clearing.value

    XCTAssertEqual(clearedChatIDs, ["default"])
    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.isInDefaultChat)
    XCTAssertTrue(provider.messages.isEmpty)
    XCTAssertNil(barrierSurface)
  }

  @MainActor
  func testNamedClearDeletesOldCatalogAndCreatesFreshGreetingSession() async throws {
    let provider = ChatProvider()
    let oldSession = ChatSession(id: "chat-old", title: "Old", messageCount: 2)
    var deletedChatIDs: [String] = []
    var greetingSurface: AgentSurfaceReference?
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.sessions = [oldSession]
    provider.currentSession = oldSession
    provider.isInDefaultChat = false
    provider.messages = [ChatMessage(text: "Old answer", sender: .ai)]
    provider.beginRealtimeChatClearForTests = { _ in true }
    provider.endRealtimeChatClearForTests = { _ in }
    provider.deleteChatCatalogForTests = { chatID in
      deletedChatIDs.append(chatID)
      return []
    }
    provider.createChatCatalogForTests = { chatID, _ in
      try self.summary(id: chatID)
    }
    provider.refreshMemoriesForPromptForTests = {}
    provider.loadAIProfileForTests = { "" }
    provider.initialMessageForTests = { _, _, _ in
      InitialMessageResponse(message: "Fresh greeting")
    }
    provider.recordInitialGreetingForTests = { surface, message, _ in
      greetingSurface = surface
      return message.text == "Fresh greeting"
    }

    await provider.clearCurrentChat()

    let replacement = try XCTUnwrap(provider.currentSession)
    XCTAssertEqual(deletedChatIDs, ["chat-old"])
    XCTAssertNotEqual(replacement.id, oldSession.id)
    XCTAssertFalse(provider.sessions.contains(where: { $0.id == oldSession.id }))
    XCTAssertTrue(provider.sessions.contains(where: { $0.id == replacement.id }))
    XCTAssertFalse(provider.isInDefaultChat)
    XCTAssertEqual(greetingSurface?.externalRefId, replacement.id)
    XCTAssertNil(provider.errorMessage)
  }

  @MainActor
  func testNamedClearSurfacesAttachmentCleanupFailureAfterReplacement() async throws {
    let provider = ChatProvider()
    let oldSession = ChatSession(id: "chat-old", title: "Old")
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.sessions = [oldSession]
    provider.currentSession = oldSession
    provider.isInDefaultChat = false
    provider.beginRealtimeChatClearForTests = { _ in true }
    provider.endRealtimeChatClearForTests = { _ in }
    provider.deleteChatCatalogForTests = { _ in [] }
    provider.createChatCatalogForTests = { chatID, _ in try self.summary(id: chatID) }
    provider.garbageCollectChatAttachmentsForTests = { _, _ in
      throw CatalogTestError.unavailable
    }
    provider.refreshMemoriesForPromptForTests = {}
    provider.loadAIProfileForTests = { "" }
    provider.initialMessageForTests = { _, _, _ in InitialMessageResponse(message: "Hello") }
    provider.recordInitialGreetingForTests = { _, _, _ in true }

    await provider.clearCurrentChat()

    XCTAssertNotEqual(provider.currentSession?.id, oldSession.id)
    XCTAssertEqual(
      provider.errorMessage,
      "Chat cleared. Attachment cleanup will retry automatically."
    )
  }

  @MainActor
  func testOwnerSwitchDuringNamedClearCleanupCannotCreateReplacementForNewOwner() async {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    let cleanupStarted = expectation(description: "owner A attachment cleanup started")
    let cleanupGate = GreetingGate()
    let oldSession = ChatSession(id: "owner-a-chat", title: "Owner A")
    let ownerBSession = ChatSession(id: "owner-b-chat", title: "Owner B")
    var createdChatIDs: [String] = []
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.sessions = [oldSession]
    provider.currentSession = oldSession
    provider.isInDefaultChat = false
    provider.beginRealtimeChatClearForTests = { _ in true }
    provider.endRealtimeChatClearForTests = { _ in }
    provider.deleteChatCatalogForTests = { _ in [] }
    provider.garbageCollectChatAttachmentsForTests = { _, _ in
      cleanupStarted.fulfill()
      await cleanupGate.wait()
    }
    provider.createChatCatalogForTests = { chatID, _ in
      createdChatIDs.append(chatID)
      return try self.summary(id: chatID)
    }

    let clearing = Task { @MainActor in await provider.clearCurrentChat() }
    await fulfillment(of: [cleanupStarted], timeout: 2)
    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    provider.sessions = [ownerBSession]
    provider.currentSession = ownerBSession
    provider.isInDefaultChat = false

    await cleanupGate.open()
    await clearing.value

    XCTAssertTrue(createdChatIDs.isEmpty)
    XCTAssertEqual(provider.sessions, [ownerBSession])
    XCTAssertEqual(provider.currentSession, ownerBSession)
    XCTAssertFalse(provider.isClearing)
  }

  @MainActor
  func testCurrentSessionDeletePreservesAttachmentCleanupWarningAfterFallbackSelection() async throws {
    let provider = ChatProvider()
    let defaultSession = ChatSession(id: "default", title: "New Chat")
    let deletedSession = ChatSession(id: "chat-delete", title: "Delete")
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.sessions = [defaultSession, deletedSession]
    provider.currentSession = deletedSession
    provider.isInDefaultChat = false
    provider.deleteChatCatalogForTests = { _ in [] }
    provider.createChatCatalogForTests = { chatID, _ in try self.summary(id: chatID) }
    provider.ensureBridgeStartedForTests = { _ in true }
    provider.reloadChatJournalForTests = { _ in true }
    provider.garbageCollectChatAttachmentsForTests = { _, _ in
      throw CatalogTestError.unavailable
    }

    await provider.deleteSession(deletedSession)

    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.isInDefaultChat)
    XCTAssertEqual(
      provider.errorMessage,
      "Chat deleted. Attachment cleanup will retry automatically."
    )
  }

  @MainActor
  func testClearRejectsWhileVoicePersistenceBarrierIsBusy() async {
    let provider = ChatProvider()
    var journalClearCalled = false
    provider.runtimeOwnerIdForTests = { "owner-a" }
    provider.beginRealtimeChatClearForTests = { _ in false }
    provider.clearChatJournalForTests = { _ in
      journalClearCalled = true
      return true
    }

    await provider.clearCurrentChat()

    XCTAssertFalse(journalClearCalled)
    XCTAssertEqual(
      provider.errorMessage,
      "Wait for the current voice turn to finish before clearing this chat."
    )
  }

  @MainActor
  func testOwnerTransitionSynchronouslyRestoresDefaultSelectionState() {
    var ownerID = "owner-a"
    let provider = ChatProvider()
    provider.runtimeOwnerIdForTests = { ownerID }
    provider.currentSession = ChatSession(id: "owner-a-chat")
    provider.isInDefaultChat = false
    provider.isLoading = true
    provider.isLoadingMoreMessages = true
    provider.deletingSessionIds = ["owner-a-delete"]

    ownerID = "owner-b"
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)

    XCTAssertNil(provider.currentSession)
    XCTAssertTrue(provider.isInDefaultChat)
    XCTAssertFalse(provider.isLoading)
    XCTAssertFalse(provider.isLoadingMoreMessages)
    XCTAssertTrue(provider.deletingSessionIds.isEmpty)
  }

  @MainActor
  func testOwnerTransitionSuppressesLateRenameAndStarErrors() async {
    for operation in ["rename", "star"] {
      var ownerID = "owner-a"
      let provider = ChatProvider()
      let updateStarted = expectation(description: "owner A \(operation) started")
      let updateGate = GreetingGate()
      let chatA = ChatSession(id: "shared-chat", title: "Owner A")
      let chatB = ChatSession(id: "shared-chat", title: "Owner B")
      provider.runtimeOwnerIdForTests = { ownerID }
      provider.sessions = [chatA]
      provider.updateChatCatalogForTests = { _, _, _, _, _ in
        updateStarted.fulfill()
        await updateGate.wait()
        throw CatalogTestError.unavailable
      }

      let mutation = Task { @MainActor in
        if operation == "rename" {
          await provider.updateSessionTitle(chatA, title: "Late rename")
        } else {
          await provider.toggleStarred(chatA)
        }
      }
      await fulfillment(of: [updateStarted], timeout: 2)
      ownerID = "owner-b"
      NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
      provider.sessions = [chatB]
      await updateGate.open()
      await mutation.value

      XCTAssertEqual(provider.sessions, [chatB])
      XCTAssertNil(provider.errorMessage)
    }
  }

  func testRetiredChatRawValueResolvesSemanticallyToCanonicalHomeWithoutRenumbering() {
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 2))
    XCTAssertEqual(DesktopDestination.memories.rawValue, 3)
    XCTAssertEqual(DesktopDestination.tasks.rawValue, 4)
    XCTAssertEqual(DesktopDestination.rewind.rawValue, 7)
    XCTAssertEqual(DesktopDestination.settings.rawValue, 9)
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("chat"),
      DesktopNavigationResolution(destination: .home, effect: .openHomeChat)
    )
  }
}

@MainActor
final class HomeLocalSourceTests: XCTestCase {
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func tearDown() async throws {
    await ownerFixture.restore()
  }

  func testEveryContextSourceIsBounded() {
    let oversized = Array(repeating: String(repeating: "x", count: 800), count: 20)
    let result = GeminiHomeSuggestionGenerator.boundedContext(oversized)

    XCTAssertEqual(result.count, GeminiHomeSuggestionGenerator.maxSourceCharacters)
    XCTAssertLessThanOrEqual(
      result.split(separator: "\n").map(\.count).max() ?? 0,
      GeminiHomeSuggestionGenerator.maxItemCharacters
    )
  }

  @MainActor
  func testGeneratorLoadsAllFourLocalSourceAdapters() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "owner-a")
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let generator = GeminiHomeSuggestionGenerator(
      sources: StubHomeSuggestionLocalSources(
        memories: "Local memory",
        conversations: "Local conversation",
        tasks: "Local task",
        goals: "Local goal"
      )
    )

    let context = await generator.loadContext(snapshot: snapshot)

    XCTAssertEqual(
      context,
      .available(
        memories: "Local memory",
        conversations: "Local conversation",
        tasks: "Local task",
        goals: "Local goal"
      )
    )
    await fixture.restore()
  }

  func testDefaultAdapterHasNoRemoteProductDataFallback() throws {
    // Static boundary tripwire: behavioral adapter composition is covered
    // above; this catches accidental reintroduction of the forbidden clients.
    let path = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/MainWindow/Dashboard/HomeSuggestionsStore.swift")
    let source = try String(contentsOf: path, encoding: .utf8)

    XCTAssertTrue(source.contains("ActionItemStorage.shared.getLocalActionItems"))
    XCTAssertTrue(source.contains("GoalStorage.shared.getLocalGoals"))
    XCTAssertTrue(source.contains("LocalAuthorityConversationDataSource().list"))
    XCTAssertFalse(source.contains("APIClient.shared.getActionItems"))
    XCTAssertFalse(source.contains("APIClient.shared.getGoals"))
    XCTAssertFalse(source.contains("APIClient.shared.getConversations"))
    XCTAssertFalse(source.contains("APIClient.shared.getMemories"))
  }

  @MainActor
  func testRevokedSameUIDSnapshotCannotDispatchHomeSuggestionRequest() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await ownerFixture.establish(authOwnerID: "owner-a")
    let dispatchCounter = HomeRequestDispatchCounter()

    do {
      _ = try await GeminiHomeSuggestionGenerator.performAuthorizedTextRequest(
        authorizationSnapshot: staleSnapshot
      ) {
        await dispatchCounter.record()
        return #"{"questions":["Owner A private suggestion"]}"#
      }
      XCTFail("revoked authorization unexpectedly dispatched a Gemini request")
    } catch {
      XCTAssertEqual(error as? LocalMutationAuthorizationError, .revoked)
    }

    let dispatchCount = await dispatchCounter.count
    XCTAssertEqual(dispatchCount, 0)
  }
}

private actor HomeRequestDispatchCounter {
  private(set) var count = 0

  func record() {
    count += 1
  }
}
