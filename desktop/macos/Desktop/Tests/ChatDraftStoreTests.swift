import XCTest

@testable import Omi_Computer

@MainActor
final class ChatDraftStoreTests: XCTestCase {
  private var rootURL: URL!

  override func setUp() async throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ChatDraftStoreTests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: rootURL)
    rootURL = nil
  }

  func testDraftsRoundTripIndependentlyAcrossRelaunch() {
    let first = makeStore(ownerID: "user-a")
    first.setText("main draft\nwith detail", for: .mainChat(contextID: "omi:default"))
    first.setText("notch draft", for: .floatingMain)
    first.flush()

    let relaunched = makeStore(ownerID: "user-a")
    XCTAssertEqual(relaunched.text(for: .mainChat(contextID: "omi:default")), "main draft\nwith detail")
    XCTAssertEqual(relaunched.text(for: .floatingMain), "notch draft")
  }

  func testManagedAttachmentSelectionRoundTripsAcrossRelaunch() throws {
    let managedURL = rootURL.appendingPathComponent("managed.png")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47, 0x01]).write(to: managedURL)
    let key = ChatDraftKey.mainChat(contextID: "chat-a")
    let first = makeStore(ownerID: "user-a")
    first.setAttachments(
      [
        ChatAttachment(
          id: "attachment-a",
          fileName: "selected.png",
          mimeType: "image/png",
          localFileURL: managedURL,
          state: .localOnly
        )
      ],
      for: key
    )
    first.flush()

    let restored = try XCTUnwrap(makeStore(ownerID: "user-a").attachments(for: key).first)
    XCTAssertEqual(restored.id, "attachment-a")
    XCTAssertEqual(restored.fileName, "selected.png")
    XCTAssertEqual(restored.localFileURL, managedURL)
    XCTAssertEqual(restored.state, .localOnly)
    XCTAssertEqual(restored.data, Data([0x89, 0x50, 0x4E, 0x47, 0x01]))
  }

  func testLatestEditWinsWhenWritesAreCoalesced() {
    let store = makeStore(ownerID: "user-a")
    store.setText("first", for: .floatingMain)
    store.setText("second", for: .floatingMain)
    store.setText("latest", for: .floatingMain)
    store.flush()

    XCTAssertEqual(makeStore(ownerID: "user-a").text(for: .floatingMain), "latest")
  }

  func testDraftsAreIsolatedByAccount() {
    let firstUser = makeStore(ownerID: "user-a")
    firstUser.setText("Alice's draft", for: .floatingMain)
    firstUser.flush()

    let secondUser = makeStore(ownerID: "user-b")
    XCTAssertEqual(secondUser.text(for: .floatingMain), "")
    secondUser.setText("Bob's draft", for: .floatingMain)
    secondUser.flush()

    XCTAssertEqual(makeStore(ownerID: "user-a").text(for: .floatingMain), "Alice's draft")
    XCTAssertEqual(makeStore(ownerID: "user-b").text(for: .floatingMain), "Bob's draft")
  }

  func testDefaultChatDraftRehydratesSynchronouslyOnOwnerSwitch() {
    let defaults = UserDefaults.standard
    let previousOwner = defaults.object(forKey: .authUserId)
    let ownerA = "draft-owner-a-\(UUID().uuidString)"
    let ownerB = "draft-owner-b-\(UUID().uuidString)"
    let key = ChatDraftKey.mainChat(contextID: "default")
    defer {
      ChatDraftStore.shared.clearAll(ownerID: ownerA)
      ChatDraftStore.shared.clearAll(ownerID: ownerB)
      ChatDraftStore.shared.flush()
      if let previousOwner {
        defaults.set(previousOwner, forKey: .authUserId)
      } else {
        defaults.removeObject(forKey: .authUserId)
      }
    }

    defaults.set(ownerA, forKey: .authUserId)
    let provider = ChatProvider()
    provider.draftText = "Owner A private draft"
    ChatDraftStore.shared.flush()

    defaults.set(ownerB, forKey: .authUserId)
    ChatDraftStore.shared.setText("Owner B draft", for: key)
    ChatDraftStore.shared.flush()
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)

    XCTAssertEqual(provider.draftText, "Owner B draft")
    XCTAssertNotEqual(provider.draftText, "Owner A private draft")
  }

  func testManagedDefaultChatAttachmentSurvivesOwnerRoundTrip() async throws {
    let defaults = UserDefaults.standard
    let previousOwner = defaults.object(forKey: .authUserId)
    let ownerA = "attachment-owner-a-\(UUID().uuidString)"
    let ownerB = "attachment-owner-b-\(UUID().uuidString)"
    let key = ChatDraftKey.mainChat(contextID: "default")
    let sourceURL = rootURL.appendingPathComponent("owner-a-source.txt")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try Data("owner A draft attachment".utf8).write(to: sourceURL)

    defaults.set(ownerA, forKey: .authUserId)
    let sourceAttachment = try XCTUnwrap(ChatAttachment.from(url: sourceURL))
    let managed = try await LocalChatAttachmentStore.shared.materialize(
      sourceAttachment,
      ownerID: ownerA,
      chatID: "default"
    )
    let managedURL = try XCTUnwrap(managed.localFileURL)
    await LocalChatAttachmentStore.shared.releaseMaterializationProtection([managedURL])
    ChatDraftStore.shared.setAttachments([managed], for: key)
    ChatDraftStore.shared.flush()

    defer {
      ChatDraftStore.shared.clearAll(ownerID: ownerA)
      ChatDraftStore.shared.clearAll(ownerID: ownerB)
      ChatDraftStore.shared.flush()
      if let previousOwner {
        defaults.set(previousOwner, forKey: .authUserId)
      } else {
        defaults.removeObject(forKey: .authUserId)
      }
      try? FileManager.default.removeItem(at: managedURL)
    }

    let provider = ChatProvider()
    XCTAssertEqual(provider.pendingAttachments.map(\.id), [managed.id])

    defaults.set(ownerB, forKey: .authUserId)
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)
    await Task.yield()
    XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
    XCTAssertTrue(provider.pendingAttachments.isEmpty)

    defaults.set(ownerA, forKey: .authUserId)
    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)

    XCTAssertEqual(provider.pendingAttachments.map(\.id), [managed.id])
    let restoredURL = try XCTUnwrap(provider.pendingAttachments.first?.localFileURL)
    XCTAssertEqual(try Data(contentsOf: restoredURL), Data("owner A draft attachment".utf8))
  }

  func testExplicitSignOutClearsOnlyThatAccountsDrafts() {
    let firstUser = makeStore(ownerID: "user-a")
    firstUser.setText("remove me", for: .floatingMain)
    firstUser.flush()

    let secondUser = makeStore(ownerID: "user-b")
    secondUser.setText("keep me", for: .floatingMain)
    secondUser.flush()

    firstUser.clearAll(ownerID: "user-a")

    XCTAssertEqual(makeStore(ownerID: "user-a").text(for: .floatingMain), "")
    XCTAssertEqual(makeStore(ownerID: "user-b").text(for: .floatingMain), "keep me")
  }

  func testCatalogReconciliationRemovesOnlyOrphanedMainChatDrafts() {
    let store = makeStore(ownerID: "user-a")
    store.setText("default survives", for: .mainChat(contextID: "default"))
    store.setText("live survives", for: .mainChat(contextID: "chat-live"))
    store.setText("orphan is removed", for: .mainChat(contextID: "chat-orphan"))
    store.setText("floating survives", for: .floatingMain)
    store.flush()

    store.reconcileMainChatCatalog(
      ownerID: "user-a",
      retainingChatIDs: ["default", "chat-live"]
    )

    let relaunched = makeStore(ownerID: "user-a")
    XCTAssertEqual(relaunched.text(for: .mainChat(contextID: "default")), "default survives")
    XCTAssertEqual(relaunched.text(for: .mainChat(contextID: "chat-live")), "live survives")
    XCTAssertEqual(relaunched.text(for: .mainChat(contextID: "chat-orphan")), "")
    XCTAssertEqual(relaunched.text(for: .floatingMain), "floating survives")
  }

  func testClearingDraftDeletesItsPersistedRecord() {
    let store = makeStore(ownerID: "user-a")
    store.setText("temporary", for: .floatingMain)
    store.flush()
    store.clear(.floatingMain)
    store.flush()

    XCTAssertEqual(makeStore(ownerID: "user-a").text(for: .floatingMain), "")
    XCTAssertTrue(allJSONFiles().isEmpty)
  }

  func testCorruptRecordDoesNotAffectOtherDrafts() throws {
    let store = makeStore(ownerID: "user-a")
    store.setText("main unique value", for: .mainChat(contextID: "omi:default"))
    store.setText("notch survives", for: .floatingMain)
    store.flush()

    let mainFile = try XCTUnwrap(
      allJSONFiles().first { url in
        (try? String(contentsOf: url, encoding: .utf8))?.contains("main unique value") == true
      })
    try Data("not-json".utf8).write(to: mainFile, options: .atomic)

    let relaunched = makeStore(ownerID: "user-a")
    XCTAssertEqual(relaunched.text(for: .mainChat(contextID: "omi:default")), "")
    XCTAssertEqual(relaunched.text(for: .floatingMain), "notch survives")
  }

  func testDraftPersistenceHarnessActionsAreDiscoverable() {
    let registry = DesktopAutomationActionRegistry.shared
    registry.registerBuiltins()
    let names = Set(registry.descriptors().map(\.name))

    XCTAssertTrue(names.contains("set_chat_drafts"))
    XCTAssertTrue(names.contains("chat_drafts_snapshot"))
  }

  func testAcceptedFloatingDraftClearsWhenUnchanged() {
    let state = FloatingControlBarState()
    state.switchAIDraft(to: .onboardingFloating)
    defer {
      ChatDraftStore.shared.clear(.onboardingFloating)
      ChatDraftStore.shared.flush()
    }

    state.aiInputText = "submitted"
    state.markAIDraftSubmitted("submitted")
    state.clearSubmittedAIDraftIfUnchanged("submitted")

    XCTAssertEqual(state.aiInputText, "")
  }

  func testAcceptedFloatingDraftDoesNotClearNewSameTextRevision() {
    let state = FloatingControlBarState()
    state.switchAIDraft(to: .onboardingFloating)
    defer {
      ChatDraftStore.shared.clear(.onboardingFloating)
      ChatDraftStore.shared.flush()
    }

    state.aiInputText = "submitted"
    state.markAIDraftSubmitted("submitted")
    state.aiInputText = "new draft"
    state.aiInputText = "submitted"
    state.clearSubmittedAIDraftIfUnchanged("submitted")

    XCTAssertEqual(state.aiInputText, "submitted")
  }

  private func makeStore(ownerID: String) -> ChatDraftStore {
    ChatDraftStore(
      rootURL: rootURL,
      writeDelay: 60,
      ownerIDProvider: { ownerID }
    )
  }

  private func allJSONFiles() -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
  }
}
