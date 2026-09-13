import Foundation
import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

@MainActor
final class StreamingPCMPlayerLifecycleTests: XCTestCase {
  func testStalledAudioStartDoesNotBlockMainActorAndStopRejectsOldSpeech() async {
    let entered = expectation(description: "audio start entered")
    let resumed = expectation(description: "new speech scheduled")
    let output = ControlledPCMOutput()
    let gate = DispatchSemaphore(value: 0)
    output.start = {
      XCTAssertFalse(Thread.isMainThread, "Audio hardware must never stall the UI thread")
      entered.fulfill()
      // A controllable external hardware wait, released by the test, not a timer.
      if !Thread.isMainThread { gate.wait() }
      return true
    }
    let player = StreamingPCMPlayer(makeOutput: { _, _ in output })
    var staleResultDelivered = false
    var staleFinishDelivered = false
    player.enqueue(Data([1, 0])) { _ in staleResultDelivered = true }
    player.afterPendingEnqueues { staleFinishDelivered = true }
    await fulfillment(of: [entered], timeout: 3)
    // Reaching this line while the audio SDK is blocked proves UI responsiveness.
    player.stop()
    output.start = { true }
    player.enqueue(Data([2, 0])) { accepted in
      XCTAssertTrue(accepted)
      resumed.fulfill()
    }
    gate.signal()
    await fulfillment(of: [resumed], timeout: 3)
    XCTAssertFalse(staleResultDelivered)
    XCTAssertFalse(staleFinishDelivered)
    XCTAssertEqual(output.scheduledData, [Data([2, 0])])
    player.stop()
  }

  func testConfigurationChangeReplaysOnlyUnplayedTailAndIgnoresOldCompletions() async {
    let accepted = expectation(description: "initial chunks accepted")
    accepted.expectedFulfillmentCount = 2
    let replayed = expectation(description: "tail replay scheduled")
    let drained = expectation(description: "replayed tail drained")
    let output = ControlledPCMOutput()
    let player = StreamingPCMPlayer(makeOutput: { changed, _ in
      output.configurationChanged = changed
      return output
    })
    var epochs: [Int] = []
    player.onPlaybackScheduled = { epoch in
      epochs.append(epoch)
      if epochs.count == 3 { replayed.fulfill() }
    }
    var idleEpochs: [Int] = []
    player.onPlaybackIdle = { epoch in
      idleEpochs.append(epoch)
      drained.fulfill()
    }
    player.enqueue(Data([1, 0])) { _ in accepted.fulfill() }
    player.enqueue(Data([2, 0])) { _ in accepted.fulfill() }
    await fulfillment(of: [accepted], timeout: 3)
    output.finish(0)
    output.configurationChanged()
    await fulfillment(of: [replayed], timeout: 3)
    XCTAssertEqual(output.scheduledData, [Data([1, 0]), Data([2, 0]), Data([2, 0])])
    XCTAssertEqual(epochs, [1, 2, 3])
    output.finish(1)  // Completion from the discarded pre-rebuild schedule.
    output.finish(2)
    await fulfillment(of: [drained], timeout: 3)
    XCTAssertEqual(idleEpochs, [3])
    player.stop()
  }

  func testConfigurationRestartCanStallWithoutBlockingStopOrReplayingCancelledTail() async {
    let accepted = expectation(description: "initial audio accepted")
    let restarting = expectation(description: "configuration restart blocked")
    let stopped = expectation(description: "physical stop completed")
    let output = ControlledPCMOutput()
    let player = StreamingPCMPlayer(makeOutput: { changed, _ in
      output.configurationChanged = changed
      return output
    })
    player.enqueue(Data([7, 0])) { _ in accepted.fulfill() }
    await fulfillment(of: [accepted], timeout: 3)
    let gate = DispatchSemaphore(value: 0)
    output.start = {
      XCTAssertFalse(Thread.isMainThread)
      restarting.fulfill()
      if !Thread.isMainThread { gate.wait() }
      return true
    }
    output.configurationChanged()
    await fulfillment(of: [restarting], timeout: 3)
    player.stop { stopped.fulfill() }
    gate.signal()
    await fulfillment(of: [stopped], timeout: 3)
    XCTAssertEqual(output.scheduledData, [Data([7, 0])], "Stopped speech must not be replayed")
    XCTAssertFalse(player.hasPendingEnqueues)
  }

  func testFailedStartReportsFailureBeforeDeferredProviderCompletion() async {
    let settled = expectation(description: "provider completion released")
    let output = ControlledPCMOutput()
    output.start = { false }
    let player = StreamingPCMPlayer(makeOutput: { _, _ in output })
    var results: [String] = []
    player.onPlaybackScheduled = { _ in XCTFail("Failure is not scheduled audio") }
    player.enqueue(Data([1, 0])) { accepted in
      XCTAssertFalse(accepted)
      results.append("failed")
    }
    player.afterPendingEnqueues {
      results.append("provider-finished")
      settled.fulfill()
    }
    await fulfillment(of: [settled], timeout: 3)
    XCTAssertEqual(results, ["failed", "provider-finished"])
    XCTAssertTrue(output.scheduledData.isEmpty)
    player.stop()
  }

  func testIdleConfigurationChangeDoesNotRestartAudio() async {
    let accepted = expectation(description: "audio accepted")
    let drained = expectation(description: "audio drained")
    let rebuilt = expectation(description: "configuration handled")
    let stopped = expectation(description: "commands completed")
    let output = ControlledPCMOutput()
    let player = StreamingPCMPlayer(makeOutput: { changed, _ in
      output.configurationChanged = changed
      return output
    })
    player.onPlaybackIdle = { _ in drained.fulfill() }
    player.enqueue(Data([1, 0])) { _ in accepted.fulfill() }
    await fulfillment(of: [accepted], timeout: 3)
    output.finish(0)
    await fulfillment(of: [drained], timeout: 3)
    output.start = {
      XCTFail("Idle device change must not start playback")
      return true
    }
    output.rebuildBody = { rebuilt.fulfill() }
    output.configurationChanged()
    await fulfillment(of: [rebuilt], timeout: 3)
    player.stop { stopped.fulfill() }
    await fulfillment(of: [stopped], timeout: 3)
  }

  func testRecoveryFailureIsReportedForTheCurrentPlaybackEpoch() async {
    let accepted = expectation(description: "audio accepted")
    let failed = expectation(description: "recovery failure reported")
    let output = ControlledPCMOutput()
    let player = StreamingPCMPlayer(makeOutput: { changed, _ in
      output.configurationChanged = changed
      return output
    })
    player.enqueue(Data([1, 0])) { _ in accepted.fulfill() }
    await fulfillment(of: [accepted], timeout: 3)
    let epoch = player.playbackEpoch
    player.onPlaybackFailed = { failureEpoch in
      XCTAssertEqual(failureEpoch, epoch)
      failed.fulfill()
    }
    output.start = { false }
    output.configurationChanged()
    await fulfillment(of: [failed], timeout: 3)
    player.stop()
  }

  func testQueuedChunksCannotRestartFailedOutputBeforeTheNextTurn() async {
    let failed = expectation(description: "both pending chunks rejected")
    failed.expectedFulfillmentCount = 2
    let output = ControlledPCMOutput()
    output.start = { false }
    let player = StreamingPCMPlayer(makeOutput: { _, _ in output })
    for sample: UInt8 in [1, 2] {
      player.enqueue(Data([sample, 0])) { accepted in
        XCTAssertFalse(accepted)
        failed.fulfill()
      }
    }
    await fulfillment(of: [failed], timeout: 3)
    XCTAssertEqual(output.startCount, 1)
    XCTAssertTrue(output.scheduledData.isEmpty)
    player.stop()
    output.start = { true }
    let restarted = expectation(description: "new turn starts")
    player.enqueue(Data([3, 0])) { accepted in
      XCTAssertTrue(accepted)
      restarted.fulfill()
    }
    await fulfillment(of: [restarted], timeout: 3)
    XCTAssertEqual(output.scheduledData, [Data([3, 0])])
    player.stop()
  }

  #if DEBUG
    func testControllerDefersFinalTextUntilNativeSchedulingIsAccepted() async throws {
      let output = ControlledPCMOutput()
      try await withNativeController(output: output) { controller, session, identity, lease, player in
        let entered = self.expectation(description: "hardware stalled")
        let settled = self.expectation(description: "native acceptance and final text handled")
        let gate = DispatchSemaphore(value: 0)
        output.start = {
          entered.fulfill()
          if !Thread.isMainThread { gate.wait() }
          return true
        }
        controller.enqueueNativeAudio(Data([1, 0]), identity: identity, source: session, lease: lease)
        await self.fulfillment(of: [entered], timeout: 3)
        controller.hubDidEmitText("fixture reply", isFinal: true, identity: identity, source: session)
        XCTAssertFalse(controller.audioReceivedThisTurn, "Queued work is not accepted audio")
        XCTAssertTrue(controller.assistantText.isEmpty, "Final text must not choose fallback ahead of audio")
        player.afterPendingEnqueues { settled.fulfill() }
        gate.signal()
        await self.fulfillment(of: [settled], timeout: 3)
        XCTAssertTrue(controller.audioReceivedThisTurn)
        XCTAssertEqual(controller.assistantText, "fixture reply")
        XCTAssertEqual(VoiceTurnCoordinator.shared.outputSnapshot.activeLease, lease)
      }
    }

    func testControllerDoesNotFinishProviderTurnAheadOfPendingAudioOrAfterStop() async throws {
      let output = ControlledPCMOutput()
      try await withNativeController(output: output) { controller, session, identity, lease, player in
        let entered = self.expectation(description: "hardware stalled")
        let stopped = self.expectation(description: "cancelled hardware work settled")
        let gate = DispatchSemaphore(value: 0)
        output.start = {
          entered.fulfill()
          if !Thread.isMainThread { gate.wait() }
          return true
        }
        controller.enqueueNativeAudio(Data([1, 0]), identity: identity, source: session, lease: lease)
        await self.fulfillment(of: [entered], timeout: 3)
        controller.hubDidFinishTurn(identity: identity, source: session)
        XCTAssertFalse(VoiceTurnCoordinator.shared.activeTurn?.providerFinished ?? true)
        player.stop { stopped.fulfill() }
        gate.signal()
        await self.fulfillment(of: [stopped], timeout: 3)
        XCTAssertFalse(controller.audioReceivedThisTurn)
        XCTAssertFalse(VoiceTurnCoordinator.shared.activeTurn?.providerFinished ?? true)
        XCTAssertTrue(output.scheduledData.isEmpty)
      }
    }

    func testControllerFinishesProviderTurnAfterPendingAudioAcceptance() async throws {
      let output = ControlledPCMOutput()
      try await withNativeController(output: output) { controller, session, identity, lease, player in
        let entered = self.expectation(description: "hardware stalled")
        let finished = self.expectation(description: "provider finish admitted after acceptance")
        let gate = DispatchSemaphore(value: 0)
        output.start = {
          entered.fulfill()
          if !Thread.isMainThread { gate.wait() }
          return true
        }
        controller.enqueueNativeAudio(Data([1, 0]), identity: identity, source: session, lease: lease)
        await self.fulfillment(of: [entered], timeout: 3)
        controller.hubDidFinishTurn(identity: identity, source: session)
        XCTAssertFalse(VoiceTurnCoordinator.shared.activeTurn?.providerFinished ?? true)
        player.afterPendingEnqueues { finished.fulfill() }
        gate.signal()
        await self.fulfillment(of: [finished], timeout: 3)
        XCTAssertTrue(controller.audioReceivedThisTurn)
        XCTAssertEqual(VoiceTurnCoordinator.shared.activeTurn?.providerFinished, true)
        XCTAssertEqual(
          VoiceTurnCoordinator.shared.outputSnapshot.activeLease, lease,
          "Provider completion must still wait for physical playback to drain")
      }
    }

    private func withNativeController(
      output: ControlledPCMOutput,
      body: (RealtimeHubController, RealtimeHubSession, RealtimeHubEventIdentity, VoiceOutputLease, StreamingPCMPlayer)
        async throws -> Void
    ) async throws {
      let defaults = UserDefaults.standard
      let oldOwner = defaults.object(forKey: .authUserId)
      let oldOverride = defaults.object(forKey: .automationOwnerOverride)
      defaults.set("pcm-owner-fixture", forKey: .authUserId)
      defaults.removeObject(forKey: .automationOwnerOverride)
      let coordinator = VoiceTurnCoordinator.shared
      coordinator.reset()
      defer {
        coordinator.reset()
        defaults.set(oldOwner, forKey: .authUserId)
        defaults.set(oldOverride, forKey: .automationOwnerOverride)
      }
      let controller = RealtimeHubController()
      let session = RealtimeHubSession(
        provider: .gemini, auth: .hermeticStub, instructions: "fixture", delegate: controller)
      // No session.start(): these controller tests never open a socket or read credentials.
      controller.session = session
      controller.sessionProvider = .gemini
      controller.sessionOwnerBinding = .init(
        sourceID: ObjectIdentifier(session), ownerScope: controller.currentOwnerScope)
      let sessionID = VoiceSessionID()
      controller.voiceSessionID = sessionID
      let turnID = coordinator.begin(intent: .hold)
      coordinator.publish(.selectRoute(turnID: turnID, route: .hub(sessionID: sessionID)))
      coordinator.publish(.finalize(turnID: turnID))
      let identity = RealtimeHubEventIdentity(turnID: turnID, responseID: VoiceResponseID("pcm-fixture"))
      coordinator.publish(.hubCommitAccepted(turnID: turnID, sessionID: sessionID, responseID: identity.responseID))
      let providerIdentity = try XCTUnwrap(coordinator.activeTurn?.providerEffectIdentity)
      coordinator.publish(
        .providerResponseStartedScoped(
          turnID: turnID, identity: providerIdentity,
          sessionID: sessionID, responseID: identity.responseID))
      controller.voiceResponseID = identity.responseID
      guard case .acquired(let lease) = coordinator.acquireOutput(.nativeRealtime, turnID: turnID) else {
        return XCTFail("fixture must acquire native output")
      }
      let player = StreamingPCMPlayer(makeOutput: { _, _ in output })
      controller.pcmPlayer = player
      do {
        try await body(controller, session, identity, lease, player)
      } catch {
        await withCheckedContinuation { continuation in player.stop { continuation.resume() } }
        throw error
      }
      await withCheckedContinuation { continuation in player.stop { continuation.resume() } }
      controller.session = nil
    }
  #endif
}

private final class ControlledPCMOutput: StreamingPCMAudioOutput, @unchecked Sendable {
  private let lock = NSLock()
  private var startBody: @Sendable () -> Bool = { true }
  private var starts = 0
  private var data: [Data] = []
  private var completions: [@Sendable () -> Void] = []
  private var changed: @Sendable () -> Void = {}
  private var rebuildAction: @Sendable () -> Void = {}
  var configurationChanged: @Sendable () -> Void {
    get { lock.withLock { changed } }
    set { lock.withLock { changed = newValue } }
  }
  var rebuildBody: @Sendable () -> Void {
    get { lock.withLock { rebuildAction } }
    set { lock.withLock { rebuildAction = newValue } }
  }
  var start: @Sendable () -> Bool {
    get { lock.withLock { startBody } }
    set { lock.withLock { startBody = newValue } }
  }
  var scheduledData: [Data] { lock.withLock { data } }
  var startCount: Int { lock.withLock { starts } }
  func ensureRunning() -> Bool {
    let action = lock.withLock {
      starts += 1
      return startBody
    }
    return action()
  }
  func rebuild() {
    XCTAssertFalse(Thread.isMainThread)
    rebuildBody()
  }
  func schedule(_ pcm: Data, completion: @escaping @Sendable () -> Void) -> Bool {
    XCTAssertFalse(Thread.isMainThread)
    lock.withLock {
      data.append(pcm)
      completions.append(completion)
    }
    return true
  }
  func finish(_ index: Int) { lock.withLock { completions[index] }() }
  func stop() { XCTAssertFalse(Thread.isMainThread) }
}
