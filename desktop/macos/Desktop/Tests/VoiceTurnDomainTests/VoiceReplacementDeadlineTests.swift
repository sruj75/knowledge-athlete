import XCTest

@testable import VoiceTurnDomain

final class VoiceReplacementDeadlineTests: XCTestCase {
  private let reducer = VoiceTurnReducer()

  func testRequiredReplacementOwnsDeadlineInsteadOfOrdinaryWarmWait() {
    let fixture = replacing()
    XCTAssertFalse(fixture.model.turn?.deadlines.contains(.hubWarm) == true)
    XCTAssertTrue(fixture.model.turn?.deadlines.contains(.bargeInReplacement) == true)
    let oldWarm = reducer.reduce(
      fixture.model, .deadlineFired(turnID: fixture.turnID, deadline: .hubWarm))
    XCTAssertEqual(oldWarm.model.turn?.route, .hubWarmWait)
    XCTAssertEqual(oldWarm.model.turn?.providerConnection, fixture.model.turn?.providerConnection)
    XCTAssertFalse(
      oldWarm.effects.contains {
        if case .fallbackToTranscription = $0 { return true }
        return false
      })
  }

  func testReplacementTimeoutRecoversRecordingAndReleasedCaptureAndFencesLateReady() {
    for released in [false, true] {
      let fixture = replacing()
      var model = fixture.model
      if released { model = reducer.reduce(model, .finalize(turnID: fixture.turnID)).model }
      let expired = reducer.reduce(model, .deadlineFired(turnID: fixture.turnID, deadline: .bargeInReplacement))
      XCTAssertEqual(expired.model.turn?.route, .managedBatch)
      XCTAssertEqual(expired.model.turn?.phase, released ? .finalizing : .recording)
      XCTAssertEqual(
        expired.effects.filter {
          if case .fallbackToTranscription = $0 { return true }
          return false
        },
        [.fallbackToTranscription(turnID: fixture.turnID, reason: .bargeInReplacementTimeout)])
      let lateReady = reducer.reduce(
        expired.model,
        .providerReplacementReady(
          turnID: fixture.turnID, identity: fixture.identity,
          sessionID: VoiceSessionID(), responseID: fixture.responseID))
      XCTAssertEqual(lateReady.model.turn?.route, .managedBatch)
      XCTAssertEqual(lateReady.model.staleEventCount, expired.model.staleEventCount + 1)
    }
  }

  func testReplacementReadyRearmsShortRescueUntilManagerAdmitsItsCapture() {
    let fixture = replacing()
    let sessionID = VoiceSessionID()
    let ready = reducer.reduce(
      fixture.model,
      .providerReplacementReady(
        turnID: fixture.turnID, identity: fixture.identity,
        sessionID: sessionID, responseID: fixture.responseID))
    XCTAssertTrue(
      ready.effects.contains(.scheduleDeadline(turnID: fixture.turnID, deadline: .hubWarm, after: 1)))
    XCTAssertFalse(ready.model.turn?.deadlines.contains(.bargeInReplacement) == true)
    let admitted = reducer.reduce(ready.model, .hubReady(turnID: fixture.turnID, sessionID: sessionID))
    XCTAssertEqual(admitted.model.turn?.route, .hub(sessionID: sessionID))
    XCTAssertFalse(admitted.model.turn?.deadlines.contains(.hubWarm) == true)
    let noAdmission = reducer.reduce(ready.model, .deadlineFired(turnID: fixture.turnID, deadline: .hubWarm))
    XCTAssertEqual(noAdmission.model.turn?.route, .managedBatch)
  }

  func testOrdinaryColdPTTKeepsOneSecondWarmRecovery() {
    let turnID = VoiceTurnID()
    let started = reducer.reduce(.idle, .start(turnID: turnID, ownerID: nil, intent: .hold)).model
    let waiting = reducer.reduce(started, .selectRoute(turnID: turnID, route: .hubWarmWait))
    XCTAssertTrue(waiting.effects.contains(.scheduleDeadline(turnID: turnID, deadline: .hubWarm, after: 1)))
    let expired = reducer.reduce(waiting.model, .deadlineFired(turnID: turnID, deadline: .hubWarm))
    XCTAssertEqual(expired.model.turn?.route, .managedBatch)
    XCTAssertEqual(expired.model.turn?.phase, .recording)
  }

  private func replacing() -> (
    model: VoiceTurnModel, turnID: VoiceTurnID, identity: VoiceEffectIdentity, responseID: VoiceResponseID
  ) {
    let turnID = VoiceTurnID()
    let responseID = VoiceResponseID("required-replacement")
    var model = reducer.reduce(.idle, .start(turnID: turnID, ownerID: nil, intent: .hold)).model
    model = reducer.reduce(model, .selectRoute(turnID: turnID, route: .hubWarmWait)).model
    let identity = VoiceEffectIdentity(turnID: turnID, effectID: model.turn?.nextEffectID ?? 0)
    model = reducer.reduce(model, .effectIdentityReserved(turnID: turnID)).model
    model =
      reducer.reduce(
        model,
        .providerReplacementStarted(
          turnID: turnID, identity: identity, previousResponseID: nil, nextResponseID: responseID)
      ).model
    return (model, turnID, identity, responseID)
  }
}
