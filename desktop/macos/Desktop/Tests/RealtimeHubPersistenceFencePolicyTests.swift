import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

/// Regression coverage for the persistence-fence retry busy-loop.
///
/// `refreshVoiceContextAfterPersistenceFence` used to `continue` on every failed
/// `refreshVoiceContextSnapshot()`. When the owner signed out or the session was
/// invalidated mid-turn, the kernel snapshot could never resolve (the agent
/// bridge refuses to start without a current authorization) and the failure
/// returned instantly, so the loop spun agent-bridge startup at full speed —
/// ~56k "sign in to use AI chat" failures per minute in one observed session,
/// bloating the log to gigabytes. The loop now consults
/// `RealtimeHubLifecyclePolicy.canRetryPersistenceFence`, which only permits a
/// retry while the fence still owns its original authenticated scope.
final class RealtimeHubPersistenceFencePolicyTests: XCTestCase {
  private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
      guard !isOpen else { return }
      await withCheckedContinuation { continuation = $0 }
    }

    func open() {
      isOpen = true
      continuation?.resume()
      continuation = nil
    }
  }

  private let ownerA = RealtimeHubOwnerScope.authenticated("uid-A")
  private let ownerB = RealtimeHubOwnerScope.authenticated("uid-B")

  func testRetriesWhileOwnerUnchangedAndAuthenticated() {
    XCTAssertTrue(
      RealtimeHubLifecyclePolicy.canRetryPersistenceFence(
        taskCancelled: false, fenceOwnerScope: ownerA, currentOwnerScope: ownerA))
  }

  func testStopsWhenTaskCancelled() {
    XCTAssertFalse(
      RealtimeHubLifecyclePolicy.canRetryPersistenceFence(
        taskCancelled: true, fenceOwnerScope: ownerA, currentOwnerScope: ownerA))
  }

  func testStopsWhenOwnerSignsOutMidFence() {
    // The exact busy-loop trigger: fence started authenticated, owner is now signedOut.
    XCTAssertFalse(
      RealtimeHubLifecyclePolicy.canRetryPersistenceFence(
        taskCancelled: false, fenceOwnerScope: ownerA, currentOwnerScope: .signedOut))
  }

  func testStopsWhenOwnerSwaps() {
    XCTAssertFalse(
      RealtimeHubLifecyclePolicy.canRetryPersistenceFence(
        taskCancelled: false, fenceOwnerScope: ownerA, currentOwnerScope: ownerB))
  }

  func testNeverRetriesWhileSignedOut() {
    // Even if the scope "matches", a signed-out bridge can never start, so never spin.
    XCTAssertFalse(
      RealtimeHubLifecyclePolicy.canRetryPersistenceFence(
        taskCancelled: false, fenceOwnerScope: .signedOut, currentOwnerScope: .signedOut))
  }

  @MainActor
  func testChatClearBarrierRejectsNewVoiceAdmissionAndSameSurfacePersistence() {
    let controller = RealtimeHubController()
    let surface = AgentSurfaceReference.mainChat(chatId: "default")
    defer { controller.endChatClearBarrier(surface: surface) }

    XCTAssertTrue(controller.beginChatClearBarrier(surface: surface))
    XCTAssertTrue(controller.chatClearBarrierBlocksVoiceAdmission())
    XCTAssertFalse(controller.chatClearBarrierAllowsPersistence(to: surface))
    XCTAssertFalse(
      controller.chatClearBarrierAllowsPersistence(
        to: surface.realtimeVoiceCompanion()))
    XCTAssertTrue(
      controller.chatClearBarrierAllowsPersistence(
        to: .mainChat(chatId: "another-chat")))
    XCTAssertEqual(controller.beginTurn(), .rejected)
    XCTAssertFalse(controller.beginChatClearBarrier(surface: surface))
  }

  @MainActor
  func testAdmittedVoiceTurnPersistsToPinnedChatAfterSelectionChangeThenRetiresPin() async {
    let controller = RealtimeHubController()
    let turnID = VoiceTurnID(UUID())
    let continuityKey = "voice:\(turnID.rawValue.uuidString.lowercased())"
    let admittedSurface = AgentSurfaceReference.realtimeVoice(chatId: "chat-a")
    let laterSelection = AgentSurfaceReference.mainChat(chatId: "chat-b")
    let persistenceGate = Gate()
    var persistedSurface: AgentSurfaceReference?
    controller.pinVoiceJournal(
      continuityKey: continuityKey,
      surface: admittedSurface,
      sessionID: "session-a"
    )

    let persistence = controller.enqueueTurnPersistence(idempotencyKey: continuityKey) {
      await persistenceGate.wait()
      persistedSurface = controller.journalPinsByContinuityKey[continuityKey]?.surface
      return true
    }
    controller.prefetchedVoiceContextSurface = laterSelection
    controller.markVoiceJournalPinTerminal(continuityKey: continuityKey)
    XCTAssertEqual(controller.journalPinsByContinuityKey[continuityKey]?.surface, admittedSurface)

    await persistenceGate.open()
    let accepted = await persistence.value
    XCTAssertTrue(accepted)

    XCTAssertEqual(persistedSurface, admittedSurface)
    XCTAssertNil(controller.journalPinsByContinuityKey[continuityKey])
    XCTAssertFalse(controller.terminalJournalContinuityKeys.contains(continuityKey))
  }
}
