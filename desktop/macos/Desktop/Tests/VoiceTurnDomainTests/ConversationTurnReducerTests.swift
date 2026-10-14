import XCTest

@testable import VoiceTurnDomain

final class ConversationTurnReducerTests: XCTestCase {
  func testConversationDoesNotOwnOrCloseThePersistentMicrophone() {
    let reducer = VoiceTurnReducer()
    let id = VoiceTurnID()
    let started = reducer.reduce(.idle, .start(turnID: id, ownerID: "owner", intent: .conversation))
    XCTAssertEqual(started.model.turn?.phase, .finalizing)
    XCTAssertFalse(started.model.turn?.deadlines.contains(.captureStart) ?? true)
    let cancelled = reducer.reduce(started.model, .cancel(turnID: id, reason: .cancelled))
    XCTAssertFalse(
      cancelled.effects.contains {
        if case .stopCapture = $0 { return true }
        return false
      })
  }

  func testUnansweredConversationCanMoveFromLiveToBatchWithoutChangingUtteranceID() {
    let reducer = VoiceTurnReducer()
    let id = VoiceTurnID()
    let session = VoiceSessionID()
    var model = reducer.reduce(.idle, .start(turnID: id, ownerID: "owner", intent: .conversation)).model
    model = reducer.reduce(model, .selectRoute(turnID: id, route: .hub(sessionID: session))).model
    model = reducer.reduce(model, .hubCommitAccepted(turnID: id, sessionID: session, responseID: nil)).model
    let oldProvider = model.turn?.providerEffectIdentity
    model = reducer.reduce(model, .selectRoute(turnID: id, route: .managedBatch)).model
    XCTAssertEqual(model.turn?.id, id)
    XCTAssertEqual(model.turn?.phase, .finalizing)
    XCTAssertNil(model.turn?.sessionID)
    model = reducer.reduce(model, .transcriptionFinal(turnID: id, text: "My reply")).model
    XCTAssertNotEqual(model.turn?.providerEffectIdentity, oldProvider)
    XCTAssertEqual(model.invalidTransitionCount, 0)
  }
}
