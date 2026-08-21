import FluidAudio
import XCTest

@testable import Omi_Computer

private actor FairUseAutomationEvidenceReaderStub: FairUseEvidenceReading {
  private(set) var reads = 0

  func fairUseEvidence(
    now: Date,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [FairUseConversationEvidence] {
    reads += 1
    return []
  }
}

private actor FairUseAutomationSubmitterStub: FairUseReviewSubmitting {
  private(set) var submissions = 0

  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt {
    submissions += 1
    return FairUseClassificationReceipt(
      reviewId: reviewId, accepted: true, idempotent: false, action: "none", stage: "none", caseRef: "")
  }
}

private actor FairUseReadinessGate {
  private var entered = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func wait() async {
    entered = true
    let waiters = entryWaiters
    entryWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { entryWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor FairUseDeliveryProbe {
  private var delivered = false

  func record() {
    delivered = true
  }

  func wasDelivered() -> Bool {
    delivered
  }
}

@MainActor
final class FairUseAutomationBridgeTests: XCTestCase {
  func testProbeExercisesExpiredAdmissionWithoutBackendSubmission() async throws {
    let reader = FairUseAutomationEvidenceReaderStub()
    let submitter = FairUseAutomationSubmitterStub()
    let coordinator = FairUseReviewCoordinator(
      storage: reader,
      submitter: submitter,
      captureAuthorization: { nil },
      now: { Date(timeIntervalSince1970: 1_800_000_000) })

    let result = await FairUseAutomationProbe.rejectedExpiredAdmission(coordinator: coordinator)

    XCTAssertEqual(result["status"], "expired_rejected")
    XCTAssertEqual(result["backend_submission_attempted"], "false")
    XCTAssertEqual(result["content_fields_exposed"], "false")
    let reads = await reader.reads
    let submissions = await submitter.submissions
    XCTAssertEqual(reads, 0)
    XCTAssertEqual(submissions, 0)
  }

  func testHandoffActionExercisesRealAppStateConversationCoordinator() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    XCTAssertTrue(AppState.current === appState)
    let result = await appState.automationExerciseFairUseManagedCloudHandoff(
      isNonProduction: true)

    XCTAssertEqual(result["outcome"], "continued_locally")
    XCTAssertEqual(result["active_mode"], "local")
    XCTAssertEqual(result["same_session"], "true")
    XCTAssertEqual(result["same_conversation"], "true")
    XCTAssertEqual(result["cleanup_stopped"], "true")
    XCTAssertEqual(result["content_fields_exposed"], "false")

    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testFailedLocalReadinessTruthfullyStopsTheRealAppStateSession() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-failed-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    appState.sttSession.activeMode = .cloud

    let outcome = await appState.handleFairUseManagedCloudExhausted(
      FairUseManagedCloudExhaustion(
        resetsAt: "2026-08-22T00:00:00Z",
        caseRef: "FU-A1B2C3D4E5F6"),
      automationReadiness: false)

    XCTAssertEqual(outcome, .stoppedUnavailable)
    XCTAssertFalse(appState.isTranscribing)
    await appState.transcriptionStopTask?.value
    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testStaleHandoffCompletionCannotMutateAReplacementRecording() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-generation-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let firstStart = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(firstStart["error"])
    let firstSessionID = appState.currentSessionId
    appState.sttSession.activeMode = .cloud
    let gate = FairUseReadinessGate()

    let staleHandoff = Task { @MainActor in
      await appState.handleFairUseManagedCloudExhausted(
        FairUseManagedCloudExhaustion(
          resetsAt: "2026-08-22T00:00:00Z",
          caseRef: "FU-A1B2C3D4E5F6"),
        automationReadiness: true,
        automationReadinessWaiter: { await gate.wait() })
    }
    await gate.waitUntilEntered()
    let firstStop = await appState.automationStopCaptureTestSession(isNonProduction: true)
    XCTAssertEqual(firstStop["stopped"], "true")
    let replacementStart = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(replacementStart["error"])
    let replacementSessionID = appState.currentSessionId
    XCTAssertNotEqual(replacementSessionID, firstSessionID)
    XCTAssertEqual(appState.sttSession.activeMode, .local)

    await gate.release()
    let staleOutcome = await staleHandoff.value
    XCTAssertEqual(staleOutcome, .ignored)
    XCTAssertTrue(appState.isTranscribing)
    XCTAssertEqual(appState.currentSessionId, replacementSessionID)
    XCTAssertEqual(appState.sttSession.activeMode, .local)
    XCTAssertFalse(appState.sttSession.fallbackInProgress)

    _ = await appState.automationStopCaptureTestSession(isNonProduction: true)
    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testRevokedExactOwnerAuthorizationCannotCompleteHandoffForSameUID() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-revoked-authorization-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    appState.sttSession.activeMode = .cloud
    let gate = FairUseReadinessGate()

    let revokedHandoff = Task { @MainActor in
      await appState.handleFairUseManagedCloudExhausted(
        FairUseManagedCloudExhaustion(
          resetsAt: "2026-08-22T00:00:00Z",
          caseRef: "FU-A1B2C3D4E5F6"),
        automationReadiness: true,
        automationReadinessWaiter: { await gate.wait() })
    }
    await gate.waitUntilEntered()
    // Re-establishing the same UID rotates the owner generation. The session ID
    // is unchanged, so only the captured capability can reject this completion.
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    await gate.release()

    let revokedOutcome = await revokedHandoff.value
    XCTAssertEqual(revokedOutcome, .ignored)
    XCTAssertTrue(appState.sttSession.fallbackInProgress)
    XCTAssertEqual(appState.transcriptionServiceError, "Switching to on-device transcription…")

    _ = await appState.automationStopCaptureTestSession(isNonProduction: true)
    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testAlreadyRevokedAuthorizationPublishesNoHandoffState() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-already-revoked-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    appState.sttSession.activeMode = .cloud
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)

    let outcome = await appState.handleFairUseManagedCloudExhausted(
      FairUseManagedCloudExhaustion(
        resetsAt: "2026-08-22T00:00:00Z",
        caseRef: "FU-A1B2C3D4E5F6"),
      automationReadiness: true)

    XCTAssertEqual(outcome, .ignored)
    XCTAssertFalse(appState.sttSession.fallbackInProgress)
    XCTAssertNil(appState.transcriptionServiceError)

    _ = await appState.automationStopCaptureTestSession(isNonProduction: true)
    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testPostReadinessLocalServiceFailureIsGenerationBoundAndTruthfullyStops() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-local-failure-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    let sessionID = try XCTUnwrap(appState.currentSessionId)
    let recordingGeneration = appState.recordingGeneration
    let authorization = try XCTUnwrap(appState.currentSessionAuthorization)
    appState.sttSession.activeMode = .cloud
    appState.sttSession.beginManagedRestrictionHandoff()
    appState.sttSession.completeManagedRestrictionHandoff()
    let exhaustion = FairUseManagedCloudExhaustion(
      resetsAt: "2026-08-22T00:00:00Z",
      caseRef: "FU-A1B2C3D4E5F6")

    appState.handleFairUseLocalServiceUnavailable(
      exhaustion,
      expectedSessionId: sessionID + 1,
      expectedRecordingGeneration: recordingGeneration,
      authorization: authorization,
      failureReason: .bufferExhausted)
    XCTAssertTrue(appState.isTranscribing)
    XCTAssertEqual(appState.sttSession.activeMode, .local)

    appState.handleFairUseLocalServiceUnavailable(
      exhaustion,
      expectedSessionId: sessionID,
      expectedRecordingGeneration: recordingGeneration,
      authorization: authorization,
      failureReason: .bufferExhausted,
      presentAlert: false)
    await appState.transcriptionStopTask?.value

    XCTAssertFalse(appState.isTranscribing)
    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testFailureDuringReadinessStopsAndFlushesTheUnaffectedLocalTail() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "fair-use-automation-readiness-failure-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    let sessionID = try XCTUnwrap(appState.currentSessionId)
    let generation = appState.recordingGeneration
    let authorization = try XCTUnwrap(appState.currentSessionAuthorization)
    appState.sttSession.activeMode = .cloud
    appState.sttSession.beginManagedRestrictionHandoff()
    var delivered: [TranscriptionService.BackendSegment] = []
    let unaffectedService = LocalTranscriptionService(
      isUser: false,
      modelLoader: { _ in AsrManager() },
      windowTranscriber: { _, _ in
        ASRResult(
          text: "retained local tail",
          confidence: 1,
          duration: 0.1,
          processingTime: 0.01)
      })
    unaffectedService.start(onSegments: { delivered.append(contentsOf: $0) })
    let serviceReady = await unaffectedService.waitUntilReady()
    XCTAssertTrue(serviceReady)
    unaffectedService.appendAudio(Data(repeating: 0x7f, count: 64))
    appState.localSystemService = unaffectedService
    let cloudTailGate = FairUseReadinessGate()
    let cloudTail = FairUseDeliveryProbe()
    appState.segmentDeliveryQueue.submit {
      await cloudTailGate.wait()
      await cloudTail.record()
    }

    appState.handleFairUseLocalServiceUnavailable(
      FairUseManagedCloudExhaustion(
        resetsAt: "2026-08-22T00:00:00Z",
        caseRef: "FU-A1B2C3D4E5F6"),
      expectedSessionId: sessionID,
      expectedRecordingGeneration: generation,
      authorization: authorization,
      failureReason: .bufferExhausted,
      presentAlert: false)
    await cloudTailGate.waitUntilEntered()
    let deliveredBeforeRelease = await cloudTail.wasDelivered()
    XCTAssertFalse(deliveredBeforeRelease)
    await cloudTailGate.release()
    await appState.transcriptionStopTask?.value

    XCTAssertFalse(appState.isTranscribing)
    XCTAssertEqual(delivered.map(\.text), ["retained local tail"])
    let deliveredAfterStop = await cloudTail.wasDelivered()
    XCTAssertTrue(deliveredAfterStop)

    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testOrdinaryLocalFailureAwaitsExactTailFlushAndRecordsTypedFallback() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "local-failure-fallback-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    let tailGate = FairUseReadinessGate()
    var delivered: [TranscriptionService.BackendSegment] = []
    let delayedService = LocalTranscriptionService(
      isUser: false,
      modelLoader: { _ in AsrManager() },
      windowTranscriber: { _, _ in
        await tailGate.wait()
        return ASRResult(
          text: "delayed retained tail",
          confidence: 1,
          duration: 0.1,
          processingTime: 0.01)
      })
    delayedService.start(onSegments: { delivered.append(contentsOf: $0) })
    let delayedServiceReady = await delayedService.waitUntilReady()
    XCTAssertTrue(delayedServiceReady)
    delayedService.appendAudio(Data(repeating: 0x7f, count: 64))
    appState.localSystemService = delayedService
    DesktopDiagnosticsManager.shared.resetForTests()
    var restartCalled = false

    appState.handleLocalSTTFailure(.bufferExhausted) {
      restartCalled = true
    }
    let restartTask = try XCTUnwrap(appState.localSTTFallbackRestartTask)
    await tailGate.waitUntilEntered()

    XCTAssertFalse(restartCalled)
    let fallback = try XCTUnwrap(
      DesktopDiagnosticsManager.shared.currentSnapshotsForSentry().last {
        $0["event"] as? String == "fallback_triggered"
      })
    XCTAssertEqual(fallback["area"] as? String, "local_stt")
    XCTAssertEqual(fallback["from"] as? String, "local")
    XCTAssertEqual(fallback["to"] as? String, "cloud")
    XCTAssertEqual(fallback["reason"] as? String, "buffer_exhausted")
    XCTAssertEqual(fallback["outcome"] as? String, "degraded")

    await tailGate.release()
    await restartTask.value

    XCTAssertTrue(restartCalled)
    XCTAssertEqual(delivered.map(\.text), ["delayed retained tail"])
    XCTAssertFalse(appState.sttSession.fallbackInProgress)

    DesktopDiagnosticsManager.shared.resetForTests()
    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testOrdinaryLocalFailureCannotRestartAfterSameUIDReauthentication() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "local-failure-owner-fence")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    let tailGate = FairUseReadinessGate()
    let delayedService = LocalTranscriptionService(
      isUser: false,
      modelLoader: { _ in AsrManager() },
      windowTranscriber: { _, _ in
        await tailGate.wait()
        return ASRResult(
          text: "revoked owner tail",
          confidence: 1,
          duration: 0.1,
          processingTime: 0.01)
      })
    delayedService.start(onSegments: { _ in })
    let delayedServiceReady = await delayedService.waitUntilReady()
    XCTAssertTrue(delayedServiceReady)
    delayedService.appendAudio(Data(repeating: 0x7f, count: 64))
    appState.localSystemService = delayedService
    var restartCalled = false

    appState.handleLocalSTTFailure(.inference) {
      restartCalled = true
    }
    let restartTask = try XCTUnwrap(appState.localSTTFallbackRestartTask)
    await tailGate.waitUntilEntered()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    await tailGate.release()
    await restartTask.value

    XCTAssertFalse(restartCalled)
    XCTAssertFalse(appState.sttSession.fallbackInProgress)

    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testExplicitStopCancelsOrdinaryLocalFallbackRestartDuringTailFlush() async throws {
    let storageFixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "local-failure-user-stop")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: storageFixture.testUserId)
    let appState = AppState()
    let start = await appState.automationStartCaptureTestSession(isNonProduction: true)
    XCTAssertNil(start["error"])
    let tailGate = FairUseReadinessGate()
    let delayedService = LocalTranscriptionService(
      isUser: false,
      modelLoader: { _ in AsrManager() },
      windowTranscriber: { _, _ in
        await tailGate.wait()
        return ASRResult(
          text: "user stopped tail",
          confidence: 1,
          duration: 0.1,
          processingTime: 0.01)
      })
    delayedService.start(onSegments: { _ in })
    let delayedServiceReady = await delayedService.waitUntilReady()
    XCTAssertTrue(delayedServiceReady)
    delayedService.appendAudio(Data(repeating: 0x7f, count: 64))
    appState.localSystemService = delayedService
    var restartCalled = false

    appState.handleLocalSTTFailure(.inference) {
      restartCalled = true
    }
    let restartTask = try XCTUnwrap(appState.localSTTFallbackRestartTask)
    await tailGate.waitUntilEntered()
    appState.stopTranscription()
    await tailGate.release()
    await restartTask.value

    XCTAssertFalse(restartCalled)
    XCTAssertFalse(appState.sttSession.fallbackInProgress)

    AppState.current = nil
    await ownerFixture.restore()
    await RewindStorageTestIsolation.tearDown(userDir: storageFixture.userDir)
  }

  func testProbeDescriptorDeclaresBoundedNonProductionBehavior() throws {
    let registry = DesktopAutomationActionRegistry.shared
    registry.registerBuiltins()
    let descriptor = try XCTUnwrap(
      registry.descriptors().first { $0.name == "fair_use_local_enforcement_probe" })

    XCTAssertEqual(descriptor.params, ["phase"])
    XCTAssertEqual(descriptor.category, "coordinator")
    XCTAssertEqual(descriptor.safety, "non_production_probe")
    XCTAssertEqual(
      descriptor.sideEffects,
      [
        "may read bounded owner-local conversation metadata",
        "creates then finalizes one empty owner-local harness conversation",
      ])
  }
}
