import XCTest

@testable import Omi_Computer
@testable import VoiceTurnDomain

private actor OwnerBoundaryExternalRunProbe {
  private var entered = false
  private var released = false
  private var closed = false
  private var observedOwnerID: String?
  private var observedStatus: ExternalSurfaceRunTerminalStatus?
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func terminalize(
    binding: ExternalSurfaceRunBinding,
    status: ExternalSurfaceRunTerminalStatus,
    capability: RuntimeOwnerTransitionCleanupCapability?
  ) async throws {
    guard let capability,
      RuntimeOwnerIdentity.authorizesTransitionCleanup(
        capability,
        previousOwnerID: binding.ownerID)
    else {
      throw ExternalSurfaceAuthorityError(code: "test_cleanup_capability_rejected")
    }
    observedOwnerID = binding.ownerID
    observedStatus = status
    entered = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if !released {
      await withCheckedContinuation { continuation in
        releaseWaiters.append(continuation)
      }
    }
    guard
      RuntimeOwnerIdentity.authorizesTransitionCleanup(
        capability,
        previousOwnerID: binding.ownerID)
    else {
      throw ExternalSurfaceAuthorityError(code: "test_cleanup_capability_expired")
    }
    closed = true
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { continuation in
      enteredWaiters.append(continuation)
    }
  }

  func release() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func snapshot() -> (closed: Bool, ownerID: String?, status: ExternalSurfaceRunTerminalStatus?) {
    (closed, observedOwnerID, observedStatus)
  }
}

private actor PTTLanguageIdentifierLoadProbe {
  private var attempts = 0

  func recordAttempt() {
    attempts += 1
  }

  func attemptCount() -> Int {
    attempts
  }
}

final class PushToTalkStateMachineTests: XCTestCase {
  func testRecordingProjectionComesDirectlyFromAuthoritativePhase() {
    XCTAssertTrue(VoiceTurnPhase.recording.isRecording)
    XCTAssertTrue(VoiceTurnPhase.pendingLockDecision.isRecording)
    XCTAssertTrue(VoiceTurnPhase.lockedRecording.isRecording)
    XCTAssertFalse(VoiceTurnPhase.finalizing.isRecording)
    XCTAssertTrue(VoiceTurnPhase.terminal(.success).isTerminal)
  }

  func testCaptureStartAfterFinalizationProducesStopEffect() {
    let reducer = VoiceTurnReducer()
    let turnID = VoiceTurnID()
    var model = reducer.reduce(.idle, .start(turnID: turnID, ownerID: nil, intent: .hold)).model
    model = reducer.reduce(model, .finalize(turnID: turnID)).model
    let captureID = VoiceCaptureID(42)

    let result = reducer.reduce(
      model,
      .captureStarted(turnID: turnID, captureID: captureID))

    XCTAssertEqual(result.model.turn?.phase, .finalizing)
    XCTAssertTrue(result.effects.contains(.stopCapture(turnID: turnID, captureID: captureID)))
  }

  func testCancelFromRecordingStopsCaptureAndTerminatesOnce() {
    let reducer = VoiceTurnReducer()
    let turnID = VoiceTurnID()
    let captureID = VoiceCaptureID(9)
    var model = reducer.reduce(.idle, .start(turnID: turnID, ownerID: nil, intent: .hold)).model
    model = reducer.reduce(model, .captureStarted(turnID: turnID, captureID: captureID)).model

    let cancelled = reducer.reduce(model, .cancel(turnID: turnID, reason: .cancelled))

    XCTAssertEqual(cancelled.model.turn?.phase, .terminal(.cancelled))
    XCTAssertTrue(cancelled.effects.contains(.stopCapture(turnID: turnID, captureID: captureID)))
    XCTAssertEqual(
      cancelled.effects.filter { effect in
        if case .terminal = effect { return true }
        return false
      }.count, 1)
  }

  func testUnconfiguredVoiceLanguagesDoNotLoadTheLocalSpeechModel() async {
    let probe = PTTLanguageIdentifierLoadProbe()
    let identifier = PTTLanguageIdentifier(managerLoader: {
      await probe.recordAttempt()
      return nil
    })

    let verdict = await identifier.identify(
      pcm16k: Data(repeating: 0, count: 12_800),
      candidates: [])
    let attempts = await probe.attemptCount()

    XCTAssertNil(verdict.languageCode)
    XCTAssertNil(verdict.transcript)
    XCTAssertEqual(attempts, 0, "default-config PTT must stay local-model inert")
  }

  // The owner-boundary suite drives DEBUG-only seams (ownerBoundarySnapshot,
  // RealtimeHubOwnerBoundarySnapshot); the release-mode CI test compile must skip it.
  #if DEBUG
    @MainActor
    func testOwnerBoundaryEffectHandlerInstallDoesNotStartListening() {
      let manager = PushToTalkManager.shared
      manager.cleanup()
      defer { manager.cleanup() }

      manager.installOwnerBoundaryEffectHandlerFixture()

      XCTAssertNil(VoiceTurnCoordinator.shared.activeTurn)
      XCTAssertNil(manager.ownerBoundarySnapshot.activeTurnID)
      XCTAssertFalse(manager.ownerBoundarySnapshot.hasCaptureDriver)
      XCTAssertFalse(manager.ownerBoundarySnapshot.captureStartInFlight)
    }

    @MainActor
    func testOwnerTransitionTerminatesActiveNonHubCaptureBeforeOwnerBBecomesVisible() async {
      let manager = PushToTalkManager.shared
      let defaults = ownerBoundaryDefaults("non-hub")
      manager.cleanup()
      await transitionOwner(defaults: defaults, to: "owner-a")

      manager.installOwnerBoundaryEffectHandlerFixture()
      let turnID = VoiceTurnCoordinator.shared.begin(intent: .hold, ownerID: "owner-a")
      VoiceTurnCoordinator.shared.publish(
        .selectRoute(turnID: turnID, route: .managedBatch))
      let captureID = VoiceCaptureID(manager.ownerBoundarySnapshot.captureGeneration)
      VoiceTurnCoordinator.shared.publish(
        .captureStarted(turnID: turnID, captureID: captureID))
      let generationBeforeTransition = manager.ownerBoundarySnapshot.captureGeneration

      await transitionOwner(defaults: defaults, to: "owner-b")

      XCTAssertEqual(defaults.string(forKey: .authUserId), "owner-b")
      XCTAssertEqual(VoiceTurnCoordinator.shared.model.lastTerminal?.turnID, turnID)
      XCTAssertEqual(VoiceTurnCoordinator.shared.model.lastTerminal?.reason, .ownerChanged)
      let snapshot = manager.ownerBoundarySnapshot
      XCTAssertNil(snapshot.activeTurnID)
      XCTAssertFalse(snapshot.hasCaptureDriver)
      XCTAssertFalse(snapshot.captureStartInFlight)
      XCTAssertFalse(snapshot.hasTranscriptionDriver)
      XCTAssertGreaterThan(snapshot.captureGeneration, generationBeforeTransition)

      manager.cleanup()
      defaults.removePersistentDomain(forName: ownerBoundarySuiteName("non-hub"))
    }

    @MainActor
    func testOwnerTransitionClosesWarmHubAndPurgesOwnerAContext() async {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let defaults = ownerBoundaryDefaults("warm-hub")
      manager.cleanup()
      await transitionOwner(defaults: defaults, to: "owner-a")
      hub.installOwnerBoundaryFixture(ownerID: "owner-a")

      XCTAssertEqual(
        hub.ownerBoundarySnapshot,
        RealtimeHubOwnerBoundarySnapshot(
          hasPhysicalSession: true,
          physicalOwnerID: "owner-a",
          prefetchedOwnerID: "owner-a",
          prefetchedContextIsEmpty: false,
          hasPendingOwnerWork: true,
          hubConnected: true,
          turnAudioByteCount: 16))

      await transitionOwner(defaults: defaults, to: "owner-b")

      XCTAssertEqual(defaults.string(forKey: .authUserId), "owner-b")
      assertHubOwnerBoundaryIsEmpty(hub.ownerBoundarySnapshot)
      defaults.removePersistentDomain(forName: ownerBoundarySuiteName("warm-hub"))
    }

    @MainActor
    func testOwnerTransitionTerminatesActiveHubAndDrainsItsPhysicalSession() async {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let defaults = ownerBoundaryDefaults("active-hub")
      manager.cleanup()
      await transitionOwner(defaults: defaults, to: "owner-a")

      manager.installOwnerBoundaryEffectHandlerFixture()
      hub.installOwnerBoundaryFixture(ownerID: "owner-a")
      let turnID = VoiceTurnCoordinator.shared.begin(intent: .hold, ownerID: "owner-a")
      VoiceTurnCoordinator.shared.publish(
        .selectRoute(turnID: turnID, route: .hub(sessionID: nil)))
      let captureID = VoiceCaptureID(manager.ownerBoundarySnapshot.captureGeneration)
      VoiceTurnCoordinator.shared.publish(
        .captureStarted(turnID: turnID, captureID: captureID))

      await transitionOwner(defaults: defaults, to: "owner-b")

      XCTAssertEqual(defaults.string(forKey: .authUserId), "owner-b")
      XCTAssertEqual(VoiceTurnCoordinator.shared.model.lastTerminal?.turnID, turnID)
      XCTAssertEqual(VoiceTurnCoordinator.shared.model.lastTerminal?.reason, .ownerChanged)
      assertHubOwnerBoundaryIsEmpty(hub.ownerBoundarySnapshot)

      manager.cleanup()
      defaults.removePersistentDomain(forName: ownerBoundarySuiteName("active-hub"))
    }

    @MainActor
    func testOwnerTransitionAwaitsExternalVoiceRunTerminalizationBeforeOwnerBAdmission() async {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let defaults = ownerBoundaryDefaults("active-external-run")
      let probe = OwnerBoundaryExternalRunProbe()
      manager.cleanup()
      await transitionOwner(defaults: defaults, to: "owner-a")

      manager.installOwnerBoundaryEffectHandlerFixture()
      hub.installOwnerBoundaryFixture(ownerID: "owner-a")
      let turnID = VoiceTurnCoordinator.shared.begin(intent: .hold, ownerID: "owner-a")
      VoiceTurnCoordinator.shared.publish(
        .selectRoute(turnID: turnID, route: .hub(sessionID: nil)))
      VoiceTurnCoordinator.shared.publish(
        .captureStarted(
          turnID: turnID,
          captureID: VoiceCaptureID(manager.ownerBoundarySnapshot.captureGeneration)))
      hub.installOwnerBoundaryExternalRunFixture(
        ownerID: "owner-a",
        turnID: turnID
      ) { binding, status, _, capability in
        try await probe.terminalize(
          binding: binding,
          status: status,
          capability: capability)
      }

      let transition = Task { @MainActor in
        await transitionOwner(defaults: defaults, to: "owner-b")
      }
      await probe.waitUntilEntered()

      XCTAssertEqual(defaults.string(forKey: .authUserId), "owner-a")
      XCTAssertNil(
        RuntimeOwnerIdentity.currentOwnerId(
          defaults: defaults,
          allowAutomationOverride: false))
      let suspendedTerminal = await probe.snapshot()
      XCTAssertFalse(suspendedTerminal.closed)

      await probe.release()
      await transition.value

      let terminal = await probe.snapshot()
      XCTAssertTrue(terminal.closed)
      XCTAssertEqual(terminal.ownerID, "owner-a")
      XCTAssertEqual(terminal.status, .cancelled)
      XCTAssertEqual(defaults.string(forKey: .authUserId), "owner-b")
      XCTAssertEqual(VoiceTurnCoordinator.shared.model.lastTerminal?.reason, .ownerChanged)
      assertHubOwnerBoundaryIsEmpty(hub.ownerBoundarySnapshot)

      manager.cleanup()
      defaults.removePersistentDomain(forName: ownerBoundarySuiteName("active-external-run"))
    }

    @MainActor
    func testUnresolvedExternalVoiceRunStaysTrackedUntilOwnerWideRevocation() async {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let defaults = ownerBoundaryDefaults("unresolved-external-run")
      manager.cleanup()
      await transitionOwner(defaults: defaults, to: "owner-a")

      manager.installOwnerBoundaryEffectHandlerFixture()
      let turnID = VoiceTurnCoordinator.shared.begin(intent: .hold, ownerID: "owner-a")
      hub.installOwnerBoundaryUnresolvedExternalRunFixture(
        ownerID: "owner-a",
        turnID: turnID)

      VoiceTurnCoordinator.shared.publish(.cancel(turnID: turnID, reason: .cancelled))
      await hub.settleOwnerBoundaryExternalRunTerminalizations()

      XCTAssertTrue(
        hub.ownerBoundarySnapshot.hasPendingOwnerWork,
        "an unknown binding must remain tracked until owner-wide runtime revocation")

      await transitionOwner(defaults: defaults, to: "owner-b")

      XCTAssertEqual(defaults.string(forKey: .authUserId), "owner-b")
      assertHubOwnerBoundaryIsEmpty(hub.ownerBoundarySnapshot)

      manager.cleanup()
      defaults.removePersistentDomain(forName: ownerBoundarySuiteName("unresolved-external-run"))
    }

  #endif
}

/// The isolated-suite runner launches each XCTestCase in its own process.
/// Keep real PTT lifecycle starts out of the owner-boundary suite so their
/// process-global transport and storage work cannot delay the next fixture.
final class PushToTalkHeadlessAutomationTests: XCTestCase {
  @MainActor
  func testHeadlessAutomationRunsRealLifecycleWithoutMicrophonePermission() async {
    let manager = PushToTalkManager.shared
    let previousAuthOwner = UserDefaults.standard.string(forKey: .authUserId)
    let previousAutomationOwner = UserDefaults.standard.object(forKey: .automationOwnerOverride)
    manager.cleanup()
    UserDefaults.standard.removeObject(forKey: .automationOwnerOverride)
    addTeardownBlock { @MainActor in
      manager.cleanup()
      await transitionOwner(defaults: .standard, to: previousAuthOwner)
      if let previousAutomationOwner {
        UserDefaults.standard.set(previousAutomationOwner, forKey: .automationOwnerOverride)
      } else {
        UserDefaults.standard.removeObject(forKey: .automationOwnerOverride)
      }
    }
    await transitionOwner(defaults: .standard, to: "ptt-headless-owner")

    let started = manager.beginPushToTalkForAutomation()
    XCTAssertEqual(started["listening"], "true")
    XCTAssertEqual(VoiceTurnCoordinator.shared.activeTurn?.phase, .recording)

    let stopped = manager.endPushToTalkForAutomation()
    XCTAssertEqual(stopped["finalized"], "true")
    XCTAssertEqual(VoiceTurnCoordinator.shared.model.turn?.phase, .terminal(.tooShort))
    XCTAssertEqual(VoiceTurnCoordinator.shared.model.turn?.projection.hint, "Hold longer to record")
    XCTAssertEqual(VoiceTurnCoordinator.shared.model.staleEventCount, 0)
    XCTAssertEqual(VoiceTurnCoordinator.shared.model.invalidTransitionCount, 0)
  }
}

#if DEBUG
  final class PushToTalkRealtimeFallbackTests: XCTestCase {
    @MainActor
    func testLiveFailureWhileHoldingKeepsPreAndPostFailureAudioInOneBuffer() async throws {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let previousAuthOwner = UserDefaults.standard.string(forKey: .authUserId)
      manager.cleanup()
      addTeardownBlock { @MainActor in
        manager.cleanup()
        await transitionOwner(defaults: .standard, to: previousAuthOwner)
        XCTAssertFalse(
          hub.ownerBoundarySnapshot.hasPendingOwnerWork,
          "a hermetic PTT test must drain singleton transport work before returning")
      }
      await transitionOwner(defaults: .standard, to: "ptt-live-fallback-owner")
      hub.installOwnerBoundaryFixture(ownerID: "ptt-live-fallback-owner")
      hub.pendingSessionRefreshReason = nil

      XCTAssertEqual(manager.beginRealtimePushToTalkForAutomation()["listening"], "true")
      XCTAssertTrue(manager.injectRealtimePTTAutomationAudio(Data(repeating: 1, count: 3_200)))
      let turnID = try XCTUnwrap(VoiceTurnCoordinator.shared.activeTurnID)

      // The reducer's provider-failure transition selects this same route; its
      // reducer coverage proves capture is not stopped until release.
      VoiceTurnCoordinator.shared.publish(.selectRoute(turnID: turnID, route: .managedBatch))
      XCTAssertTrue(manager.injectRealtimePTTAutomationAudio(Data(repeating: 2, count: 3_200)))
      XCTAssertEqual(manager.ownerBoundarySnapshot.bufferedAudioBytes, 6_400)
      XCTAssertEqual(VoiceTurnCoordinator.shared.activeTurn?.phase, .recording)
    }
  }

  final class PushToTalkRealtimeCommitTests: XCTestCase {
    @MainActor
    func testAcceptedHubCommitKeepsFullPCMAvailableForPostReleaseRecovery() async throws {
      let manager = PushToTalkManager.shared
      let hub = RealtimeHubController.shared
      let previousAuthOwner = UserDefaults.standard.string(forKey: .authUserId)
      manager.cleanup()
      addTeardownBlock { @MainActor in
        hub.testingLocalProfileTransportAuthorized = nil
        manager.cleanup()
        await transitionOwner(defaults: .standard, to: previousAuthOwner)
        XCTAssertFalse(
          hub.ownerBoundarySnapshot.hasPendingOwnerWork,
          "a hermetic PTT test must drain singleton transport work before returning")
      }
      await transitionOwner(defaults: .standard, to: "ptt-post-release-fallback-owner")
      hub.installOwnerBoundaryFixture(ownerID: "ptt-post-release-fallback-owner", readyForInput: true)
      hub.pendingSessionRefreshReason = nil

      var samples: [Int16] = []
      samples.reserveCapacity(6_400)
      for index in 0..<6_400 {
        samples.append((index / 50).isMultiple(of: 2) ? 6_000 : -6_000)
      }
      let voicedPCM = samples.withUnsafeBytes { Data($0) }

      XCTAssertEqual(manager.beginRealtimePushToTalkForAutomation()["listening"], "true")
      XCTAssertTrue(manager.injectRealtimePTTAutomationAudio(voicedPCM))
      XCTAssertEqual(manager.endPushToTalkForAutomation()["finalized"], "true")
      XCTAssertEqual(VoiceTurnCoordinator.shared.activeTurn?.phase, .awaitingResponse)
      XCTAssertEqual(
        manager.ownerBoundarySnapshot.bufferedAudioBytes,
        voicedPCM.count,
        "the accepted Live commit must retain the full PCM until terminal cleanup so a later socket failure can batch-transcribe it"
      )
    }
  }
#endif

@MainActor
private func transitionOwner(defaults: UserDefaults, to ownerID: String?) async {
  // `UserDefaults` is non-Sendable and cannot cross from the main actor into
  // the nonisolated `performEffectiveOwnerTransition` boundary under Swift 6.
  let boxed = OwnerDefaultsBox(value: defaults)
  do {
    try await runOwnerTransition(boxed: boxed, ownerID: ownerID)
  } catch {
    XCTFail("owner transition failed: \(error)")
  }
}

private func runOwnerTransition(boxed: OwnerDefaultsBox, ownerID: String?) async throws {
  try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
    defaults: boxed.value,
    allowAutomationOverride: false,
    plannedNextOwner: { _, _ in ownerID },
    retargetLocalStorage: { _, _ in },
    prepareLocalStorageTransition: { _, _ in },
    ownerDidChange: {}
  ) { defaults in
    if let ownerID {
      defaults.set(ownerID, forKey: .authUserId)
    } else {
      defaults.removeObject(forKey: .authUserId)
    }
  }
}

private func ownerBoundaryDefaults(_ suffix: String) -> UserDefaults {
  let name = ownerBoundarySuiteName(suffix)
  guard let defaults = UserDefaults(suiteName: name) else {
    preconditionFailure("UserDefaults suite unavailable: \(name)")
  }
  defaults.removePersistentDomain(forName: name)
  return defaults
}

private func ownerBoundarySuiteName(_ suffix: String) -> String {
  "PushToTalkStateMachineTests.owner-boundary.\(suffix)"
}

#if DEBUG
  @MainActor
  private func assertHubOwnerBoundaryIsEmpty(
    _ snapshot: RealtimeHubOwnerBoundarySnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertFalse(snapshot.hasPhysicalSession, file: file, line: line)
    XCTAssertNil(snapshot.physicalOwnerID, file: file, line: line)
    XCTAssertNil(snapshot.prefetchedOwnerID, file: file, line: line)
    XCTAssertTrue(snapshot.prefetchedContextIsEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.hasPendingOwnerWork, file: file, line: line)
    XCTAssertFalse(snapshot.hubConnected, file: file, line: line)
    XCTAssertEqual(snapshot.turnAudioByteCount, 0, file: file, line: line)
  }
#endif

/// Sendable carrier for a non-Sendable `UserDefaults` so it can cross the
/// nonisolated owner-transition boundary under Swift 6 strict concurrency.
private struct OwnerDefaultsBox: @unchecked Sendable {
  let value: UserDefaults
}
