import Foundation
import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

#if DEBUG
  @MainActor
  final class SupervisorPTTHandoffTests: XCTestCase {
    func testPhysicalPTTAfterSupervisorPlaybackKeepsCaptureDuringRequiredReplacement() async throws {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let coordinator = VoiceTurnCoordinator.shared
      let fixture = RuntimeOwnerAuthorityTestFixture()
      let supervisorEnabled = SupervisorService.shared.enabled
      let previousCurrent = hub.supervisorGuidanceIsCurrent
      let previousClaim = hub.claimSupervisorSpeech
      let previousStart = hub.testingSessionStartAfterDrain
      SupervisorService.shared.enabled = false
      manager.cleanup()
      addTeardownBlock { @MainActor in
        hub.testingWarmAfterDrain = {}
        hub.supervisorWarmDeadline?.cancel()
        hub.supervisorDispatchTask?.cancel()
        manager.cleanup()
        hub.voiceContextSingleFlight.cancel()
        hub.canceledTurnRewarmTask?.cancel()
        await hub.canceledTurnRewarmTask?.value
        hub.turnPreparationTask?.cancel()
        await hub.turnPreparationTask?.value
        hub.clearBargeInReplacementState()
        await hub.sessionReplacementGate.waitUntilIdle()
        let source = hub.session
        hub.teardownSession()
        await source?.stopAndWait()
        await fixture.restore()
        hub.testingWarmAfterDrain = nil
        hub.testingLocalProfileTransportAuthorized = nil
        hub.testingSessionStartAfterDrain = previousStart
        hub.supervisorGuidanceIsCurrent = previousCurrent
        hub.claimSupervisorSpeech = previousClaim
        SupervisorService.shared.enabled = supervisorEnabled
      }
      await fixture.establish(authOwnerID: "supervisor-ptt-handoff-fixture")
      let barState = FloatingControlBarState()
      manager.configureVoiceTurnCoordinator(barState: barState)
      hub.installOwnerBoundaryFixture(ownerID: "supervisor-ptt-handoff-fixture", readyForInput: true)
      hub.pendingSessionRefreshReason = nil
      hub.supervisorGuidanceIsCurrent = { _ in true }
      hub.claimSupervisorSpeech = { _ in true }
      hub.testingWarmAfterDrain = {}
      let source = try XCTUnwrap(hub.session)
      _ = await source.inputLifecycleSnapshot()
      let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
      let guidance = SupervisorGuidance(
        id: "supervisor-handoff", observationID: "handoff-observation", sessionID: "handoff-session",
        contextEpoch: 1, note: "private fixture", expiresAt: Date().addingTimeInterval(30),
        authorizationSnapshot: authorization, action: .intervene)
      let admission = await hub.submitSupervisorGuidance(guidance)
      XCTAssertEqual(admission, .accepted)
      await hub.supervisorDispatchTask?.value
      let supervisorTurn = try XCTUnwrap(coordinator.activeTurnID)
      let responseID = try XCTUnwrap(hub.voiceResponseID)
      guard case .acquired = coordinator.acquireOutput(.nativeRealtime, turnID: supervisorTurn) else {
        return XCTFail("Supervisor output must own the existing native playback lease")
      }
      hub.hubDidFinishTurn(
        identity: RealtimeHubEventIdentity(turnID: supervisorTurn, responseID: responseID), source: source)
      XCTAssertTrue(coordinator.activeTurn?.providerFinished == true)
      XCTAssertNotNil(coordinator.activeTurn?.activeLease)

      // Hold the real asynchronous history boundary. The physical receipt has
      // the same ordering: completed automatic turn, PTT capture, required fresh
      // transport, the one-second warm deadline, then setupComplete at 2.1s.
      let (snapshots, delivery) = AsyncStream.makeStream(of: KernelVoiceContextSnapshot.self)
      defer { delivery.finish() }
      hub.prefetchVoiceContextSnapshotIfNeeded {
        var iterator = snapshots.makeAsyncIterator()
        guard let value = await iterator.next() else { throw CancellationError() }
        return value
      }
      let pcm = [Int16](repeating: 6_000, count: 8_000).withUnsafeBytes { Data($0) }
      manager.testingPhysicalMicrophoneCapture = { emit in emit(pcm) }
      XCTAssertEqual(manager.beginPhysicalPushToTalkForTests()["listening"], "true")
      let replyTurn = try XCTUnwrap(coordinator.activeTurnID)
      XCTAssertNotEqual(replyTurn, supervisorTurn)
      XCTAssertEqual(coordinator.model.lastTerminal?.reason, .interruptedByBargeIn)
      XCTAssertEqual(coordinator.activeTurn?.route, .hubWarmWait)
      XCTAssertEqual(manager.ownerBoundarySnapshot.bufferedAudioBytes, pcm.count)
      XCTAssertEqual(hub.replacementAudioBuffer?.turnID, replyTurn)

      coordinator.publish(.deadlineFired(turnID: replyTurn, deadline: .hubWarm))

      XCTAssertEqual(
        coordinator.activeTurn?.route, .hubWarmWait,
        "Required replacement owns its bounded reconnect window; ordinary warm expiry must not force batch speech")
      XCTAssertEqual(coordinator.activeTurn?.phase, .recording)
      XCTAssertEqual(manager.ownerBoundarySnapshot.bufferedAudioBytes, pcm.count)

      // Resolve the external context/setup boundary deterministically. Retain
      // the controller's replacement identity and drive the actual socket
      // setupComplete callback, manager flush, and physical release.
      let continuity = hub.bargeInContinuityTask
      continuity?.cancel()
      hub.voiceContextSingleFlight.cancel()
      delivery.finish()
      await continuity?.value
      await hub.sessionReplacementGate.waitUntilIdle()
      let ready = expectation(description: "replacement admits physical reply")
      var signalled = false
      let observation = coordinator.observeSnapshots { model in
        if !signalled, model.turn?.id == replyTurn,
          case .hub = model.turn?.route, model.turn?.providerConnection == .ready
        {
          signalled = true
          ready.fulfill()
        }
      }
      defer { observation.cancel() }
      var socket: SupervisorPTTWebSocket?
      var startedSession: RealtimeHubSession?
      let replacementStarted = expectation(description: "replacement startup passes owner and drain fences")
      hub.testingSessionStartAfterDrain = { provider, auth, owner in
        hub.testingSessionStartAfterDrain = nil
        hub.startSession(
          provider: provider, auth: auth, ownerScope: owner,
          rawWebSocketFactory: { _, queue in
            let transport = SupervisorPTTWebSocket(queue: queue)
            socket = transport
            return transport
          })
        startedSession = hub.session
        replacementStarted.fulfill()
        return true
      }
      hub.startReplacementSessionForBargeIn(
        provider: .gemini, auth: .hermeticStub, ownerScope: hub.currentOwnerScope)
      await fulfillment(of: [replacementStarted], timeout: 2)
      let replacement = try XCTUnwrap(startedSession)
      XCTAssertFalse(replacement === source, "Private automatic input requires a fresh physical session")
      await fulfillment(of: [ready], timeout: 2)
      _ = await replacement.inputLifecycleSnapshot()
      XCTAssertEqual(coordinator.activeTurn?.route, .hub(sessionID: hub.voiceSessionID))
      XCTAssertEqual(manager.endPushToTalkForAutomation()["finalized"], "true")
      _ = await replacement.inputLifecycleSnapshot()
      XCTAssertEqual(coordinator.activeTurn?.phase, .awaitingResponse)
      hub.hubDidConnect(source: replacement)
      let transport = try XCTUnwrap(socket)
      let frames = await transport.frames()
      let inputs = try frames.compactMap { frame -> [String: Any]? in
        let object = try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any]
        return object?["realtimeInput"] as? [String: Any]
      }
      let audio = inputs.compactMap { input -> Data? in
        guard let audio = input["audio"] as? [String: Any], let encoded = audio["data"] as? String else { return nil }
        return Data(base64Encoded: encoded)
      }
      XCTAssertEqual(audio, [pcm], "Ready and duplicate-ready callbacks must flush the exact capture once")
      XCTAssertEqual(inputs.filter { $0["activityEnd"] != nil }.count, 1)
      XCTAssertFalse(frames.contains { $0.contains("private fixture") })
    }
  }

  private final class SupervisorPTTWebSocket: RealtimeRawWebSocketTransport, @unchecked Sendable {
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var onClose: ((Int, String) -> Void)?
    var onError: ((RealtimeRawWebSocketFailure) -> Void)?
    private let queue: DispatchQueue
    private var sent: [String] = []

    init(queue: DispatchQueue) { self.queue = queue }

    func connect() { onOpen?() }

    func sendText(_ text: String, completion: (@Sendable (Error?) -> Void)?) {
      sent.append(text)
      completion?(nil)
      if text.contains(#""setup":"#) { onMessage?(Data(#"{"setupComplete":{}}"#.utf8)) }
    }

    func close() {}

    func closeAndWait() async {
      await withCheckedContinuation { continuation in
        queue.async { continuation.resume() }
      }
    }

    func frames() async -> [String] {
      await withCheckedContinuation { continuation in
        queue.async { continuation.resume(returning: self.sent) }
      }
    }
  }
#endif
