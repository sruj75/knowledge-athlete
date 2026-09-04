import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

#if DEBUG
  // omi-release-compile: this suite drives RealtimeHubController and
  // DesktopDiagnosticsManager DEBUG-only test seams (testingWarmAfterDrain,
  // testingSessionStartAfterDrain, resetForTests); the release-mode
  // notification regression step must compile the bundle without them.

  final class RealtimeHubSessionHandoffPolicyTests: XCTestCase {
    @MainActor
    func testPhysicalReplacementGateDrainsBeforeStartingAndCoalescesDuplicates() async {
      let gate = RealtimeHubTransportReplacementGate()
      let stopEntered = expectation(description: "old transport stop entered")
      let replacementStarted = expectation(description: "replacement started")
      var releaseStop: CheckedContinuation<Void, Never>?
      var events: [String] = []

      XCTAssertTrue(
        gate.replace(
          stop: {
            events.append("stop")
            await withCheckedContinuation {
              releaseStop = $0
              stopEntered.fulfill()
            }
            events.append("drained")
          },
          start: {
            events.append("start")
            replacementStarted.fulfill()
          }))
      await fulfillment(of: [stopEntered], timeout: 1)

      XCTAssertFalse(
        gate.replace(
          stop: { XCTFail("coalesced replacement must not stop twice") },
          start: { XCTFail("coalesced replacement must not start twice") }))
      XCTAssertEqual(events, ["stop"])

      releaseStop?.resume()
      await fulfillment(of: [replacementStarted], timeout: 1)
      XCTAssertEqual(events, ["stop", "drained", "start"])
      XCTAssertFalse(gate.isPending)
    }

    @MainActor
    func testPhysicalReplacementGateCancellationStillWaitsForDrainAndNeverStarts() async {
      let gate = RealtimeHubTransportReplacementGate()
      let stopEntered = expectation(description: "stop entered")
      let gateBecameIdle = expectation(description: "gate became idle")
      var releaseStop: CheckedContinuation<Void, Never>?
      var startCount = 0

      XCTAssertTrue(
        gate.replace(
          stop: {
            await withCheckedContinuation {
              releaseStop = $0
              stopEntered.fulfill()
            }
          },
          start: { startCount += 1 }))
      await fulfillment(of: [stopEntered], timeout: 1)
      Task {
        await gate.waitUntilIdle()
        gateBecameIdle.fulfill()
      }

      gate.cancel()
      XCTAssertTrue(gate.isPending, "cancellation cannot advertise idle before physical drain")
      XCTAssertEqual(startCount, 0)
      releaseStop?.resume()
      await fulfillment(of: [gateBecameIdle], timeout: 1)
      XCTAssertFalse(gate.isPending)
      XCTAssertEqual(startCount, 0)
    }

    @MainActor
    func testCancelTurnWaitsForTransportAcknowledgementBeforeControllerRewarm() async throws {
      let controller = RealtimeHubController()
      let fixture = try await installDelayedTransport(on: controller, ownerScope: .signedOut)
      let rewarmed = expectation(description: "controller rewarmed")
      controller.testingWarmAfterDrain = { rewarmed.fulfill() }
      let coordinator = VoiceTurnCoordinator.shared
      coordinator.reset()
      let turnID = RealtimeAutomationTurnHarness.begin(on: coordinator)

      XCTAssertTrue(controller.cancelTurn(turnID: turnID))
      await Task.yield()
      XCTAssertTrue(controller.sessionReplacementGate.isPending)
      XCTAssertEqual(fixture.tracker.liveCount, 1)

      fixture.transport.acknowledgeClose()
      await fulfillment(of: [rewarmed], timeout: 1)
      XCTAssertEqual(fixture.tracker.liveCount, 0)
      XCTAssertFalse(controller.sessionReplacementGate.isPending)
      coordinator.reset()
    }

    @MainActor
    func testStaleOwnerReadinessWaitsForTransportAcknowledgementBeforeRewarm() async throws {
      let controller = RealtimeHubController()
      let staleOwner = RealtimeHubOwnerScope.authenticated("stale-\(UUID().uuidString)")
      let fixture = try await installDelayedTransport(on: controller, ownerScope: staleOwner)
      let rewarmed = expectation(description: "controller rewarmed")
      controller.testingWarmAfterDrain = { rewarmed.fulfill() }

      XCTAssertFalse(controller.isTransportReady)
      await Task.yield()
      XCTAssertTrue(controller.sessionReplacementGate.isPending)
      XCTAssertEqual(fixture.tracker.liveCount, 1)

      fixture.transport.acknowledgeClose()
      await fulfillment(of: [rewarmed], timeout: 1)
      XCTAssertEqual(fixture.tracker.liveCount, 0)
      XCTAssertNil(controller.session)
    }

    @MainActor
    func testDuplicateTransportTerminalCallbacksAndLateStaleCallbackFinishReducerOnce() async throws {
      let controller = RealtimeHubController()
      let fixture = try await installDelayedTransport(
        on: controller,
        ownerScope: controller.currentOwnerScope)
      let coordinator = VoiceTurnCoordinator.shared
      coordinator.reset()
      defer { coordinator.reset() }
      let turnID = RealtimeAutomationTurnHarness.begin(on: coordinator)
      let sessionID = try XCTUnwrap(controller.voiceSessionID)
      coordinator.publish(.selectRoute(turnID: turnID, route: .hub(sessionID: sessionID)))
      let terminalized = expectation(description: "reducer terminalized")
      var observedTerminal = false
      let observation = coordinator.observeSnapshots { model in
        guard model.turn?.id == turnID, model.turn?.phase.isTerminal == true,
          !observedTerminal
        else { return }
        observedTerminal = true
        terminalized.fulfill()
      }
      defer { observation.cancel() }

      fixture.transport.emitErrorCloseAndDuplicateError()
      await fulfillment(of: [terminalized], timeout: 1)
      await Task.yield()

      XCTAssertNil(controller.session, "the first terminal callback must fence the source immediately")
      fixture.transport.emitErrorCloseAndDuplicateError()
      await Task.yield()
      let terminals = coordinator.timelineSnapshot().filter {
        $0.turnID == turnID && $0.terminalReason != nil
      }
      XCTAssertEqual(terminals.count, 1)
      XCTAssertEqual(coordinator.model.turn?.phase, .terminal(.providerFailed))

      controller.sessionReplacementGate.cancel()
      fixture.transport.acknowledgeClose()
      await controller.sessionReplacementGate.waitUntilIdle()
    }

    func testProviderLogTagStaysUnboundUntilGeminiSessionExists() {
      XCTAssertEqual(RealtimeHubProviderLogTag.current(nil), "unbound")
      XCTAssertEqual(RealtimeHubProviderLogTag.current(.gemini), "gemini")
    }

    func testAuthenticatedSocketWithStaleContextCapturesAndBuffersInsteadOfEnteringDirectly() {
      XCTAssertEqual(
        RealtimePTTAdmissionPolicy.decide(
          requirementIsResolved: true,
          transportIsReady: true,
          bindingMatchesRequirement: false),
        .captureAndBuffer)
    }

    func testOnlyExactAuthenticatedBindingAdmitsPTTImmediately() {
      XCTAssertEqual(
        RealtimePTTAdmissionPolicy.decide(
          requirementIsResolved: true,
          transportIsReady: true,
          bindingMatchesRequirement: true),
        .immediate)
    }

    func testMatchingBindingNeverStartsMaintenanceHandoff() {
      XCTAssertEqual(
        RealtimeHubSessionHandoffPolicy.decide(
          bindingMatchesRequirement: true,
          canReplaceIdleSession: true,
          hasBufferedTurn: false),
        .keepActive)
    }

    func testStreamingContextUpdateDebouncesIdleSessionHandoff() {
      XCTAssertEqual(
        RealtimeVoiceContextRefreshPolicy.handoffDecision(
          currentSnapshotIdentity: "newer", sessionSnapshotIdentity: "older", hasBufferedTurn: false),
        .debounceIdleHandoff)
      XCTAssertEqual(
        RealtimeVoiceContextRefreshPolicy.handoffDecision(
          currentSnapshotIdentity: "same", sessionSnapshotIdentity: "same", hasBufferedTurn: false),
        .keepCurrentSession)
    }

    func testCapturedPTTBypassesIdleContextDebounce() {
      XCTAssertEqual(
        RealtimeVoiceContextRefreshPolicy.handoffDecision(
          currentSnapshotIdentity: "newer", sessionSnapshotIdentity: "older", hasBufferedTurn: true),
        .replacePreservingBufferedTurn)
    }

    func testWarmSessionWaitsForOwnerBoundVoiceContext() {
      XCTAssertFalse(RealtimeWarmSessionStartPolicy.canStart(requirementIsResolved: false))
      XCTAssertTrue(RealtimeWarmSessionStartPolicy.canStart(requirementIsResolved: true))
    }

    func testNamedDevelopmentFaultArmsOnePhysicalTurnAndRestoresAfterItsTerminal() {
      var gate = RealtimePhysicalPTTTransportFaultGate()
      let turnID = VoiceTurnID()

      XCTAssertEqual(
        gate.arm(bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence"),
        .armed)
      XCTAssertEqual(gate.diagnosticsState, "armed")
      XCTAssertTrue(gate.activateIfArmed(turnID: turnID, isPhysicalMicrophone: true))
      XCTAssertTrue(gate.blocksTransport)
      XCTAssertEqual(gate.diagnosticsState, "active")
      XCTAssertEqual(
        gate.clear(bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence"),
        .rejectedActive)
      XCTAssertFalse(gate.restoreAfterTerminal(turnID: VoiceTurnID()))
      XCTAssertTrue(gate.blocksTransport, "an unrelated turn cannot restore another turn's fault")
      XCTAssertTrue(gate.restoreAfterTerminal(turnID: turnID))
      XCTAssertFalse(gate.blocksTransport)
      XCTAssertEqual(gate.diagnosticsState, "idle")
    }

    func testPhysicalTransportFaultRejectsEveryNonNamedIdentity() {
      for bundleIdentifier in [
        "com.heyintentive.intentive",
        "com.heyintentive.intentive.beta",
        "com.heyintentive.intentive.dev",
        "com.heyintentive.intentive.preview.candidate",
        "org.example.intentive",
      ] {
        var gate = RealtimePhysicalPTTTransportFaultGate()
        XCTAssertEqual(
          gate.arm(bundleIdentifier: bundleIdentifier),
          .rejectedIdentity,
          bundleIdentifier)
        XCTAssertEqual(gate.diagnosticsState, "idle", bundleIdentifier)
        XCTAssertFalse(gate.blocksTransport, bundleIdentifier)
      }
    }

    func testArmedPhysicalTransportFaultIgnoresSyntheticManagerTurnsAndCanBeCleared() {
      var gate = RealtimePhysicalPTTTransportFaultGate()
      XCTAssertEqual(
        gate.arm(bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence"),
        .armed)
      XCTAssertFalse(gate.activateIfArmed(turnID: VoiceTurnID(), isPhysicalMicrophone: false))
      XCTAssertEqual(gate.diagnosticsState, "armed")
      XCTAssertFalse(gate.blocksTransport)
      XCTAssertEqual(
        gate.clear(bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence"),
        .cleared)
      XCTAssertEqual(gate.diagnosticsState, "idle")
    }

    @MainActor
    func testControllerConsumesPhysicalFaultAndRestoresItThroughTerminalLifecycle() {
      let controller = RealtimeHubController()
      let turnID = VoiceTurnID()

      let armed = controller.configurePhysicalPTTTransportFault(
        operation: "arm",
        bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence")
      XCTAssertEqual(armed["armed"], "true")
      XCTAssertTrue(
        controller.activatePhysicalPTTTransportFaultIfArmed(
          turnID: turnID,
          isPhysicalMicrophone: true))
      XCTAssertFalse(controller.isTransportReady)
      XCTAssertEqual(controller.automationPTTInputDiagnostics()["ptt_live_transport_fault_state"], "active")

      controller.voiceTurnDidTerminate(turnID: turnID)

      XCTAssertEqual(controller.automationPTTInputDiagnostics()["ptt_live_transport_fault_state"], "idle")
    }

    @MainActor
    func testPhysicalFaultInvalidatesPendingMintAndFencesLateSessionStart() {
      let controller = RealtimeHubController()
      let ownerScope = controller.currentOwnerScope
      let mintGeneration = try! XCTUnwrap(controller.beginMint(ownerScope: ownerScope))
      var sessionStartCount = 0
      controller.testingSessionStartAfterDrain = { _, _, _ in
        sessionStartCount += 1
        return true
      }
      let turnID = VoiceTurnID()
      XCTAssertEqual(
        controller.configurePhysicalPTTTransportFault(
          operation: "arm",
          bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence")["armed"],
        "true")

      XCTAssertTrue(
        controller.activatePhysicalPTTTransportFaultIfArmed(
          turnID: turnID,
          isPhysicalMicrophone: true))
      XCTAssertFalse(
        controller.acceptMintCompletionOrRewarm(
          generation: mintGeneration,
          ownerScope: ownerScope),
        "the token minted before fault activation must be stale")
      controller.startSession(
        provider: .gemini,
        auth: .hermeticStub,
        ownerScope: ownerScope)

      XCTAssertEqual(sessionStartCount, 0)
      XCTAssertNil(controller.session)
      controller.voiceTurnDidTerminate(turnID: turnID)
    }

    @MainActor
    func testPhysicalFaultWaitsForTransportCloseAcknowledgementBeforeRewarm() async throws {
      let controller = RealtimeHubController()
      let fixture = try await installDelayedTransport(
        on: controller,
        ownerScope: controller.currentOwnerScope)
      var warmCount = 0
      let rewarmed = expectation(description: "controller rewarmed after fault drain")
      controller.testingWarmAfterDrain = {
        warmCount += 1
        rewarmed.fulfill()
      }
      let turnID = VoiceTurnID()
      XCTAssertEqual(
        controller.configurePhysicalPTTTransportFault(
          operation: "arm",
          bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence")["armed"],
        "true")

      XCTAssertTrue(
        controller.activatePhysicalPTTTransportFaultIfArmed(
          turnID: turnID,
          isPhysicalMicrophone: true))
      await Task.yield()
      XCTAssertTrue(controller.sessionReplacementGate.isPending)
      XCTAssertEqual(fixture.tracker.liveCount, 1)

      controller.voiceTurnDidTerminate(turnID: turnID)
      XCTAssertEqual(warmCount, 0, "terminal restore cannot overlap the draining transport")
      XCTAssertTrue(controller.sessionReplacementGate.isPending)

      fixture.transport.acknowledgeClose()
      await fulfillment(of: [rewarmed], timeout: 1)
      XCTAssertEqual(fixture.tracker.liveCount, 0)
      XCTAssertFalse(controller.sessionReplacementGate.isPending)
    }

    @MainActor
    func testControllerRejectsUnknownPhysicalFaultOperationWithoutChangingState() {
      let controller = RealtimeHubController()

      let result = controller.configurePhysicalPTTTransportFault(
        operation: "toggle",
        bundleIdentifier: "com.heyintentive.intentive.dev.omi-live-evidence")

      XCTAssertEqual(result["error"], "unsupported operation; expected arm or clear")
      XCTAssertEqual(result["fault_state"], "idle")
    }

    @MainActor
    func testPhysicalTransportFaultActionUsesProductionRegistryAndRejectsTestHostIdentity() async throws {
      let registry = DesktopAutomationActionRegistry.shared
      registry.registerBuiltins()

      let descriptor = try XCTUnwrap(
        registry.descriptors().first { $0.name == "ptt_live_transport_fault" })
      XCTAssertEqual(descriptor.safety, "non_production_fault")
      XCTAssertEqual(descriptor.surfaces, ["floating_bar"])
      XCTAssertEqual(descriptor.sideEffects.count, 1)
      let performed = try await registry.perform(
        "ptt_live_transport_fault",
        params: ["operation": "arm"])
      let detail = try XCTUnwrap(performed)

      XCTAssertEqual(
        detail["error"],
        "physical PTT transport fault requires a named development bundle")
      XCTAssertEqual(detail["fault_state"], "idle")
    }

    func testIdleMaintenanceDefersWhileAnotherLogicalTurnOwnsTheSession() {
      XCTAssertEqual(
        RealtimeHubSessionHandoffPolicy.decide(
          bindingMatchesRequirement: false,
          canReplaceIdleSession: false,
          hasBufferedTurn: false),
        .deferUntilIdle)
    }

    func testCapturedTurnGetsOneTransparentRebindThenFallsBack() {
      XCTAssertEqual(
        RealtimeHubSessionHandoffPolicy.decide(
          bindingMatchesRequirement: false,
          canReplaceIdleSession: false,
          hasBufferedTurn: true,
          rebindAttempts: 0),
        .replacePreservingBufferedTurn)
      XCTAssertEqual(
        RealtimeHubSessionHandoffPolicy.decide(
          bindingMatchesRequirement: false,
          canReplaceIdleSession: false,
          hasBufferedTurn: true,
          rebindAttempts: RealtimeReconnectAudioBuffer.maximumRebindAttempts + 1),
        .fallbackToTranscription)
    }

    func testReconnectBufferRefusesASecondRebindAttempt() {
      let turnID = VoiceTurnID()
      var buffer = RealtimeReconnectAudioBuffer(
        turnID: turnID,
        responseID: VoiceResponseID("rebind-response"),
        identity: VoiceEffectIdentity(turnID: turnID, effectID: 1),
        interrupting: false)

      XCTAssertTrue(buffer.beginRebindAttempt())
      XCTAssertEqual(buffer.rebindAttempts, 1)
      XCTAssertFalse(buffer.beginRebindAttempt())
      XCTAssertEqual(buffer.rebindAttempts, 1)
    }

    func testBufferedTurnCanAdoptTheNewestRequirementBeforePhysicalReplay() {
      let turnID = VoiceTurnID()
      var buffer = RealtimeReconnectAudioBuffer(
        turnID: turnID,
        responseID: VoiceResponseID("requirement-response"),
        identity: VoiceEffectIdentity(turnID: turnID, effectID: 1),
        interrupting: false)

      XCTAssertTrue(buffer.bindRequiredContextFreshnessIdentity("cached-requirement"))
      XCTAssertTrue(buffer.replaceRequiredContextFreshnessIdentity("fresh-requirement"))
      XCTAssertEqual(buffer.requiredContextFreshnessIdentity, "fresh-requirement")
    }

    @MainActor
    private func installDelayedTransport(
      on controller: RealtimeHubController,
      ownerScope: RealtimeHubOwnerScope
    ) async throws -> (
      transport: DelayedAckRealtimeTransport,
      tracker: DelayedAckTransportTracker
    ) {
      let tracker = DelayedAckTransportTracker()
      var installedTransport: DelayedAckRealtimeTransport?
      let opened = expectation(description: "fixture transport opened")
      let session = RealtimeHubSession(
        provider: .gemini,
        auth: .hermeticStub,
        instructions: "fixture",
        rawWebSocketFactory: { _, queue in
          let transport = DelayedAckRealtimeTransport(queue: queue, tracker: tracker)
          transport.onOpened = { opened.fulfill() }
          installedTransport = transport
          return transport
        },
        delegate: controller)
      controller.session = session
      controller.voiceSessionID = VoiceSessionID()
      controller.sessionProvider = .gemini
      controller.sessionAuth = .hermeticStub
      controller.sessionOwnerBinding = RealtimeHubController.PhysicalSessionOwnerBinding(
        sourceID: ObjectIdentifier(session),
        ownerScope: ownerScope)
      controller.hubConnected = true
      session.start()
      await fulfillment(of: [opened], timeout: 1)
      return (try XCTUnwrap(installedTransport), tracker)
    }
  }

  private final class DelayedAckTransportTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var live = 0

    var liveCount: Int { lock.withLock { live } }

    func opened() {
      lock.withLock { live += 1 }
    }

    func closed() {
      lock.withLock { live -= 1 }
    }
  }

  private final class DelayedAckRealtimeTransport: RealtimeRawWebSocketTransport,
    @unchecked Sendable
  {
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var onClose: ((Int, String) -> Void)?
    var onError: ((RealtimeRawWebSocketFailure) -> Void)?
    var onOpened: (() -> Void)?

    private let queue: DispatchQueue
    private let tracker: DelayedAckTransportTracker
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(queue: DispatchQueue, tracker: DelayedAckTransportTracker) {
      self.queue = queue
      self.tracker = tracker
    }

    func connect() {
      open = true
      tracker.opened()
      onOpened?()
      onOpen?()
    }

    func sendText(_ text: String, completion: (@Sendable (Error?) -> Void)?) {
      completion?(nil)
    }

    func close() {}

    func closeAndWait() async {
      await withCheckedContinuation { continuation in
        queue.async { [weak self] in
          guard let self else {
            continuation.resume()
            return
          }
          if self.open {
            self.waiters.append(continuation)
          } else {
            continuation.resume()
          }
        }
      }
    }

    func acknowledgeClose() {
      queue.async { [weak self] in
        guard let self, self.open else { return }
        self.open = false
        self.tracker.closed()
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
          waiter.resume()
        }
      }
    }

    func emitErrorCloseAndDuplicateError() {
      queue.async { [weak self] in
        guard let self else { return }
        let failure = RealtimeRawWebSocketFailure(
          phase: .receive,
          message: "fixture transport failure")
        self.onError?(failure)
        self.onClose?(1011, "fixture remote close reason")
        self.onError?(failure)
      }
    }
  }
#endif
