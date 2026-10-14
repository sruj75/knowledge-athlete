import AppKit
import XCTest

@testable import Omi_Computer
@testable import VoiceTurnDomain

/// Fast, deterministic contract coverage that joins the production seams shared
/// by main chat, realtime voice, and the floating-bar presentation.  Keep this
/// suite independent of the app process: network, TCC, audio capture, and
/// wall-clock deadlines belong to their respective integration suites.
@MainActor
final class CrossSurfaceContractSmokeTests: XCTestCase {

  func testSharedChatIdentityContextAndJournalAdmissionStayCanonical() async throws {
    let provider = ChatProvider()
    let main = provider.mainChatSurfaceReference()
    let voice = main.realtimeVoiceCompanion()
    XCTAssertEqual(voice.externalRefKind, main.externalRefKind)
    XCTAssertEqual(voice.externalRefId, main.externalRefId)

    let continuityKey = "cross-surface:turn-1"
    let userID = KernelTurnProjection.stableTurnID(continuityKey: continuityKey, role: "user")
    let assistantID = KernelTurnProjection.stableTurnID(
      continuityKey: continuityKey,
      role: "assistant"
    )
    let userTurn = try journalTurn(
      surface: main,
      turnID: userID,
      sequence: 1,
      role: "user",
      content: "Typed and voice share this history"
    )
    let assistantTurn = try journalTurn(
      surface: voice,
      turnID: assistantID,
      sequence: 2,
      role: "assistant",
      content: "One canonical exchange."
    )
    let admitted = await provider.admitJournalExchange(
      continuityKey: continuityKey,
      userText: "Typed and voice share this history",
      assistantText: "One canonical exchange."
    ) {
      provider.projectJournalTurn(userTurn)
      provider.projectJournalTurn(assistantTurn)
      return true
    }

    XCTAssertEqual(admitted.user?.id, userID)
    XCTAssertEqual(admitted.assistant?.id, assistantID)
    XCTAssertEqual(provider.messages.map(\.id), [userID, assistantID])

    // A replay of the same canonical turn IDs cannot duplicate a visible row.
    provider.projectJournalTurn(
      try journalTurn(
        surface: voice,
        turnID: assistantID,
        sequence: 3,
        role: "assistant",
        content: "One canonical exchange."
      ))
    XCTAssertEqual(provider.messages.map(\.id), [userID, assistantID])
  }

  func testNotchChromeStaysPinned() {
    let screen = NSRect(x: 1_920, y: -100, width: 1_728, height: 1_117)
    let transient = NSRect(x: 2_637, y: 959, width: 351, height: 58)
    let placement = FloatingControlBarGeometry.SurfacePlacement.notch(screenFrame: screen)
    for transition in [
      FloatingControlBarGeometry.SurfaceTransition.pushToTalk(expanded: true),
      .agentSwitcher(visible: true),
      .agentSwitcher(visible: false),
    ] {
      let frame = FloatingControlBarGeometry.surfaceTransitionFrame(
        currentFrame: transient,
        targetSize: NSSize(width: 430, height: 180),
        transition: transition,
        placement: placement
      )
      XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
      XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.5)
    }
    for progress in [CGFloat(0), 0.5, 1] {
      XCTAssertEqual(
        NotchChromeLayout.width(
          chromeWidth: 268,
          expandedWidth: 900,
          switcherProgress: progress,
          isChatPresented: true
        ),
        268
      )
    }
  }

  private func journalTurn(
    surface: AgentSurfaceReference,
    turnID: String,
    sequence: Int,
    role: String,
    content: String
  ) throws -> KernelJournalTurn {
    try XCTUnwrap(
      KernelJournalTurn(
        dictionary: [
          "conversationId": surface.externalRefId,
          "turnId": turnID,
          "turnSeq": sequence,
          "conversationGeneration": 1,
          "generationBaseTurnSeq": 0,
          "producerId": "producer:\(turnID)",
          "payloadHash": "sha256:\(turnID)",
          "role": role,
          "surfaceKind": surface.surfaceKind,
          "externalRefKind": surface.externalRefKind,
          "externalRefId": surface.externalRefId,
          "content": content,
          "createdAtMs": sequence,
          "updatedAtMs": sequence,
          "origin": role == "user" ? "typed_chat" : "realtime_voice",
          "status": "completed",
          "contentBlocks": [],
          "resources": [],
          "metadataJson": "{}",
        ], surfaceFallback: surface))
  }
}
