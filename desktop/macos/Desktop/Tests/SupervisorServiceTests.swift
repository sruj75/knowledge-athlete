import XCTest

@testable import Omi_Computer

@MainActor
private final class SupervisorTestHarness {
  let authority = RuntimeOwnerAuthorizationAuthority()
  var owner: RuntimeOwnerAuthorizationSnapshot
  var date = Date(timeIntervalSince1970: 1_800_000_000) {
    didSet { uptime += date.timeIntervalSince(oldValue) }
  }
  var uptime: TimeInterval = 100
  var requests: [SupervisorEvaluationRequest] = []
  var delivered: [SupervisorGuidance] = []
  var evaluation: SupervisorService.Evaluator?
  var automaticallySchedule = false
  var memory = SupervisorMemoryContext.empty
  var memoryLoader: SupervisorService.MemoryLoader?
  let defaults: UserDefaults

  init() throws {
    defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString), "Isolated defaults suite must exist")
    owner = try XCTUnwrap(
      authority.capture(ownerID: "supervisor-test", expectedOwnerID: nil), "Test owner must authorize")
  }

  lazy var service = SupervisorService(
    defaults: defaults, now: { self.date }, monotonicNow: { self.uptime },
    currentOwner: { self.owner },
    ownerIsCurrent: { self.authority.isCurrent($0, ownerID: "supervisor-test") },
    evaluate: { request, owner in
      self.requests.append(request)
      if let evaluation = self.evaluation { return try await evaluation(request, owner) }
      return Self.response(request)
    },
    loadMemory: { owner in
      if let memoryLoader = self.memoryLoader { return await memoryLoader(owner) }
      return self.memory
    }, deliver: { self.delivered.append($0) },
    decisionStarted: { _ in }, recordDecision: { _, _, _ in },
    automaticallySchedule: automaticallySchedule)

  static func response(_ request: SupervisorEvaluationRequest, action: SupervisorAction = .guideNextTurn)
    -> SupervisorEvaluationResponse
  {
    .init(
      decisionID: UUID().uuidString, observationID: request.observationID,
      sessionID: request.sessionID, contextEpoch: request.contextEpoch,
      action: action, note: action == .wait ? nil : "Ask about the present work.",
      prompt: .init(text: "", name: "supervisor", version: "1", source: "fallback"),
      outcome: "completed")
  }

  func evaluate() async {
    date = date.addingTimeInterval(1)
    await service.evaluatePendingObservation()
  }

  func segment(
    _ text: String, id: String = "segment", source: SupervisorTranscriptSource = .microphone,
    capture: SupervisorCaptureInterval? = .init(start: 98, end: 99), producer: UUID
  ) -> TranscriptionService.BackendSegment {
    .init(
      segmentId: id, speakerId: 0, text: text, isUser: true, start: 0, end: 1,
      supervisorProvenance: capture.map {
        .init(producerID: producer, source: source, capture: $0)
      })
  }
}

@MainActor
private final class SupervisorRequestGate {
  private var started = false
  private var startWaiter: CheckedContinuation<Void, Never>?
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func hold() async {
    started = true
    startWaiter?.resume()
    startWaiter = nil
    await withCheckedContinuation { releaseWaiter = $0 }
  }

  func waitForStart() async {
    if started { return }
    await withCheckedContinuation { startWaiter = $0 }
  }

  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

@MainActor
final class SupervisorServiceTests: XCTestCase {
  func testDiagnosticResetRejectsLateEvaluatorCompletionAndHidesRevokedOwner() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request, action: .wait)
    }
    h.service.observeVoice(userText: "old account content", turnID: "turn", outcome: "completed")
    let task = Task { await h.evaluate() }
    await gate.waitForStart()
    let previousSession = h.service.diagnosticSnapshot().sessionID
    h.service.endSession()
    let reset = h.service.diagnosticSnapshot()
    XCTAssertNotEqual(reset.sessionID, previousSession)
    XCTAssertEqual(reset.metrics.admitted, 0)
    let resetExport = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reset)) as? [String: Any])
    XCTAssertNil(
      resetExport["contentRevision"], "activity revision from the retired session is not diagnostic metadata")
    XCTAssertEqual(reset.currentWork, .none)
    XCTAssertTrue(reset.evaluationSlotOccupied, "old work still holds the single-flight slot")
    gate.release()
    await task.value
    XCTAssertEqual(h.service.diagnosticSnapshot().metrics.evaluatorReturns, 0)
    XCTAssertEqual(h.service.diagnosticSnapshot().metrics.evaluatorRoundTrip.count, 0)
    h.service.observeVoice(userText: "new session", turnID: "new", outcome: "completed")
    h.authority.beginTransition()
    let revoked = h.service.diagnosticSnapshot()
    XCTAssertNil(revoked.sessionID)
    XCTAssertFalse(revoked.ownerAuthorized)
    XCTAssertEqual(revoked.metrics.admitted, 0)
    XCTAssertFalse(revoked.pendingChangedObservation)
  }

  func testDiagnosticReadShowsCaptureAgeAndStalenessWithoutStartingWorkOrExportingContent() throws {
    let h = try SupervisorTestHarness()
    h.service.observeFrame(
      CapturedFrame(
        jpegData: Data(), appName: "Private editor", windowTitle: "Private title", frameNumber: 1, captureTime: h.date),
      authorizationSnapshot: h.owner, capturedUptime: h.uptime)
    h.service.observeWebcam(
      jpegData: Data([0xFF, 0xD8, 0xFF]), capturedAt: h.date, capturedUptime: h.uptime,
      visualHash: 0, observationSessionID: h.service.sessionID, authorizationSnapshot: h.owner)
    h.uptime += 6
    let snapshot = h.service.diagnosticSnapshot()
    XCTAssertEqual(snapshot.inputs.screen.status, "available")
    XCTAssertEqual(snapshot.inputs.screen.ageMs, 6_000)
    XCTAssertEqual(snapshot.inputs.webcam.status, "stale")
    XCTAssertEqual(snapshot.inputs.webcam.ageMs, 6_000)
    XCTAssertTrue(h.requests.isEmpty)
    XCTAssertEqual(snapshot.metrics.admitted, 0)
    let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    XCTAssertFalse(encoded.contains("Private"))
    XCTAssertFalse(encoded.contains("supervisor-test"))
    h.uptime += 25
    XCTAssertEqual(h.service.diagnosticSnapshot().inputs.screen.status, "stale")
    h.service.webcamUnavailable(.denied)
    XCTAssertEqual(h.service.diagnosticSnapshot().inputs.webcam.status, "denied")
    XCTAssertNil(h.service.diagnosticSnapshot().inputs.webcam.ageMs)
    h.service.setSuspended(true)
    XCTAssertEqual(h.service.diagnosticSnapshot().inputs.screen.status, "suspended")
    XCTAssertNil(h.service.diagnosticSnapshot().inputs.screen.ageMs)
  }

  func testDiagnosticQuotaStateSurvivesLockAndCountsOnlyActualAttemptedWork() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw SupervisorRequestError.rateLimited(reason: "daily_quota", retryAfterSeconds: 90) }
    h.service.observeVoice(userText: "work", turnID: "turn", outcome: "completed")
    await h.evaluate()
    let paused = h.service.diagnosticSnapshot()
    XCTAssertEqual(paused.retryReason, .dailyQuota)
    XCTAssertEqual(paused.retryRemainingMs, 90_000)
    XCTAssertEqual(paused.metrics.evaluatorStarts, 1)
    XCTAssertEqual(paused.metrics.evaluatorFailures, 1)
    h.service.setSuspended(true)
    h.service.setSuspended(false)
    h.uptime += 10
    h.service.observeVoice(userText: "after unlock", turnID: "next", outcome: "completed")
    await h.evaluate()
    let after = h.service.diagnosticSnapshot()
    XCTAssertEqual(after.retryReason, .dailyQuota)
    XCTAssertEqual(after.retryRemainingMs, 79_000)
    XCTAssertEqual(after.metrics.admitted, 0)
    XCTAssertEqual(after.metrics.skipped["retry_pause"], 1)
    XCTAssertEqual(h.requests.count, 1)
  }

  func testDiagnosticsDistinguishPreparationFromEvaluatorAndMeasureExactBoundaries() async throws {
    let h = try SupervisorTestHarness()
    let memory = SupervisorRequestGate()
    let provider = SupervisorRequestGate()
    h.memoryLoader = { _ in
      await memory.hold()
      return .empty
    }
    h.evaluation = { request, _ in
      await provider.hold()
      return SupervisorTestHarness.response(request, action: .wait)
    }
    h.service.observeVoice(userText: "private transcript", turnID: "turn", outcome: "completed")
    let task = Task { await h.evaluate() }
    await memory.waitForStart()
    let preparing = h.service.diagnosticSnapshot()
    XCTAssertEqual(preparing.metrics.admitted, 1)
    XCTAssertEqual(preparing.metrics.evaluatorStarts, 0)
    XCTAssertEqual(preparing.currentWork, .preparing)
    XCTAssertTrue(preparing.evaluationSlotOccupied)
    h.uptime += 2
    memory.release()
    await provider.waitForStart()
    XCTAssertEqual(h.service.diagnosticSnapshot().currentWork, .evaluating)
    h.uptime += 4
    provider.release()
    await task.value
    let completed = h.service.diagnosticSnapshot()
    XCTAssertEqual(completed.metrics.evaluatorReturns, 1)
    XCTAssertEqual(completed.metrics.queue.lastMs, 1_000)
    XCTAssertEqual(completed.metrics.evaluatorRoundTrip.lastMs, 4_000)
    XCTAssertEqual(completed.metrics.admissionToCompletion.lastMs, 6_000)
    XCTAssertEqual(completed.metrics.observationToCompletion.lastMs, 7_000)
    XCTAssertFalse(completed.evaluationSlotOccupied)
    XCTAssertFalse(String(decoding: try JSONEncoder().encode(completed), as: UTF8.self).contains("private transcript"))
  }

  func testQuietContextIsReconsideredWithANewGuidanceLifetime() async throws {
    let h = try SupervisorTestHarness()
    h.service.observeVoice(userText: "I am reading this document", turnID: "turn", outcome: "completed")
    await h.evaluate()
    let first = try XCTUnwrap(h.delivered.first)
    h.date = h.date.addingTimeInterval(31)
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2, "quiet observation is reconsidered after thirty seconds")
    XCTAssertEqual(
      h.requests.last?.observedAt, ISO8601DateFormatter().string(from: h.date),
      "the request distinguishes admission time from the original content timestamp")
    let latest = try XCTUnwrap(h.delivered.last)
    XCTAssertNotEqual(latest.id, first.id)
    XCTAssertTrue(
      h.service.isCurrent(latest), "guidance lifetime begins with this admission, not the old content change")
  }

  func testChangesCoalesceFromTheFirstEventAndShareOneBudget() async throws {
    let h = try SupervisorTestHarness()
    h.service.observeVoice(userText: "draft", turnID: "turn", outcome: "generated")
    await h.service.evaluatePendingObservation()
    XCTAssertTrue(h.requests.isEmpty)
    h.date = h.date.addingTimeInterval(0.6)
    h.service.observeVoice(userText: "latest", turnID: "turn", outcome: "generated")
    h.date = h.date.addingTimeInterval(0.4)
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.first?.conversation.map(\.text), ["latest"])
    for text in ["two", "three", "four"] {
      h.service.observeVoice(userText: text, turnID: "turn", outcome: "generated")
      await h.evaluate()
    }
    XCTAssertEqual(h.requests.count, 3, "the burst has only three tokens")
    h.date = h.date.addingTimeInterval(2)
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 4)
    XCTAssertEqual(h.requests.last?.conversation.first?.text, "four")
  }

  func testFreshContextEvaluatesWithoutStoredHistoryAndExpiresItsAdvice() async throws {
    let h = try SupervisorTestHarness()
    h.service.observeVoice(userText: "I am writing a report", turnID: "turn", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
    XCTAssertTrue(h.requests[0].memories.isEmpty)
    let guidance = try XCTUnwrap(h.delivered.first)
    XCTAssertTrue(h.service.isCurrent(guidance))
    h.date = h.date.addingTimeInterval(31)
    XCTAssertFalse(h.service.isCurrent(guidance))
  }

  func testAcceptedGuidanceSurvivesOpeningConversationButNotRevocation() async throws {
    let h = try SupervisorTestHarness()
    h.service.observeVoice(userText: "Help me begin", turnID: "turn", outcome: "completed")
    await h.evaluate()
    let accepted = try XCTUnwrap(h.delivered.first)
    XCTAssertTrue(h.service.isCurrent(accepted))
    h.service.updateConversation(id: "opened-by-guidance", state: .connecting)
    XCTAssertFalse(h.service.isCurrent(accepted), "the original pending admission is consumed")
    XCTAssertTrue(h.service.isAcceptedGuidanceAllowed(accepted))
    h.service.setSuspended(true)
    XCTAssertFalse(h.service.isAcceptedGuidanceAllowed(accepted))
    h.service.setSuspended(false)
    XCTAssertFalse(h.service.isAcceptedGuidanceAllowed(accepted), "unlock cannot revive the old session")
  }

  func testAcceptedGuidanceIsRevokedWhenApplicationChangesDuringConversationWarmup() async throws {
    let h = try SupervisorTestHarness()
    h.service.applicationContextChanged(appName: "Editor", authorizationSnapshot: h.owner)
    h.service.observeVoice(userText: "Help with this", turnID: "turn", outcome: "completed")
    await h.evaluate()
    let accepted = try XCTUnwrap(h.delivered.first)
    h.service.updateConversation(id: "opening", state: .connecting)
    XCTAssertTrue(h.service.isAcceptedGuidanceAllowed(accepted))
    h.service.applicationContextChanged(appName: "Browser", authorizationSnapshot: h.owner)
    XCTAssertFalse(h.service.isAcceptedGuidanceAllowed(accepted))
  }

  func testMeaningfulScreenChangeRevokesQueuedGuidanceButQuietRefreshPreservesIt() async throws {
    let h = try SupervisorTestHarness()
    let frame = CapturedFrame(
      jpegData: Data(), appName: "Editor", windowTitle: "Document", frameNumber: 1, captureTime: h.date)
    h.service.observeFrame(frame, authorizationSnapshot: h.owner, visualHash: 0)
    await h.evaluate()
    let guidance = try XCTUnwrap(h.delivered.first)
    h.service.observeFrame(frame, authorizationSnapshot: h.owner, visualHash: 0)
    XCTAssertTrue(h.service.isCurrent(guidance), "a fresh unchanged frame preserves queued guidance")
    h.service.observeFrame(frame, authorizationSnapshot: h.owner, visualHash: 255)
    XCTAssertFalse(h.service.isCurrent(guidance))
    XCTAssertFalse(h.service.isAcceptedGuidanceAllowed(guidance))
  }

  func testScreenChangeSuppressesInFlightStaleDeliveryWithoutPostponingNextAdmission() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request)
    }
    let frame = CapturedFrame(
      jpegData: Data(), appName: "Editor", windowTitle: "Document", frameNumber: 1, captureTime: h.date)
    h.service.observeFrame(frame, authorizationSnapshot: h.owner, visualHash: 0)
    let pending = Task { await h.evaluate() }
    await gate.waitForStart()
    h.service.observeFrame(frame, authorizationSnapshot: h.owner, visualHash: 255)
    gate.release()
    await pending.value
    XCTAssertTrue(h.delivered.isEmpty)
    h.evaluation = nil
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertEqual(h.delivered.count, 1)
  }

  func testPartialRevisionsReplaceTextAndInterruptedPlaybackStaysDistinct() async throws {
    let h = try SupervisorTestHarness()
    h.service.updateConversation(id: "conversation", state: .open)
    h.service.observeVoice(userText: "part", turnID: "turn", outcome: "generated", revision: 1, isFinal: false)
    h.service.observeVoice(
      userText: "partial revised", turnID: "turn", outcome: "generated", revision: 2, isFinal: false)
    h.service.observeVoice(userText: "obsolete", turnID: "turn", outcome: "generated", revision: 1, isFinal: false)
    await h.evaluate()
    XCTAssertEqual(h.requests.last?.activeConversation?.id, "conversation")
    XCTAssertEqual(h.requests.last?.conversation.first?.text, "partial revised")
    XCTAssertEqual(h.requests.last?.conversation.first?.final, false)
    h.service.observeVoice(assistantText: "unfinished answer", turnID: "turn", outcome: "interrupted")
    await h.evaluate()
    XCTAssertEqual(h.requests.last?.conversation.last?.outcome, "interrupted")
  }

  func testSuspensionRejectsOldFramesAndGuidanceWhileOtherInputCanResume() async throws {
    let h = try SupervisorTestHarness()
    let admission = try XCTUnwrap(h.service.captureVoiceObservationAdmission())
    h.service.observeVoice(userText: "before lock", turnID: "old", outcome: "completed")
    await h.evaluate()
    let old = try XCTUnwrap(h.delivered.first)
    h.service.setSuspended(true)
    h.service.observeVoice(userText: "while locked", turnID: "new", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
    XCTAssertFalse(h.service.isCurrent(old))
    XCTAssertEqual(h.service.state, .suspended)
    h.service.setSuspended(false)
    h.service.observeVoice(userText: "late", turnID: "old", outcome: "completed", admission: admission)
    h.service.observeVoice(userText: "after unlock", turnID: "new", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.last?.conversation.map(\.text), ["after unlock"])
  }

  func testQuotaResetRetriesLatestContextWithoutRequiringAnotherEvent() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw SupervisorRequestError.rateLimited(reason: "burst_quota", retryAfterSeconds: 60) }
    h.service.observeVoice(userText: "current work", turnID: "turn", outcome: "completed")
    await h.evaluate()
    XCTAssertNotNil(h.service.retryAt)
    h.evaluation = nil
    h.date = h.date.addingTimeInterval(59)
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1)
    h.date = h.date.addingTimeInterval(1)
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertNil(h.service.retryAt)
  }

  func testKnownQuotaPauseSurvivesLockAndMonitoringToggle() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw SupervisorRequestError.rateLimited(reason: "daily_quota", retryAfterSeconds: 3_600) }
    h.service.observeVoice(userText: "work", turnID: "turn", outcome: "completed")
    await h.evaluate()
    h.service.setSuspended(true)
    h.service.setSuspended(false)
    h.service.enabled = false
    h.service.enabled = true
    h.service.observeVoice(userText: "work after unlock", turnID: "next", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1, "session resets must not bypass a known owner quota pause")
    XCTAssertNotNil(h.service.retryAt)
  }

  func testEightHoursOfQuietContextUsesOneHeartbeatEveryThirtySeconds() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { request, _ in SupervisorTestHarness.response(request, action: .wait) }
    h.service.observeVoice(userText: "reading", turnID: "turn", outcome: "completed")
    await h.evaluate()
    for _ in 1..<960 {
      h.date = h.date.addingTimeInterval(30)
      await h.service.evaluatePendingObservation()
    }
    XCTAssertEqual(h.requests.count, 960)
    XCTAssertEqual(h.service.metrics.admitted, 960)
    XCTAssertEqual(h.service.metrics.budgetDeferrals, 0)
  }

  func testDuplicateSettledTranscriptsDoNotConsumeAnotherEventBudget() async throws {
    let h = try SupervisorTestHarness()
    h.service.observeVoice(userText: "unchanged", turnID: "turn", outcome: "completed")
    await h.evaluate()
    h.service.observeVoice(userText: "unchanged", turnID: "turn", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
  }

  func testQuietWebcamRefreshUsesLatestImageWithoutForcingAnotherDecision() async throws {
    let h = try SupervisorTestHarness()
    let first = Data([0xFF, 0xD8, 0xFF, 1])
    let latest = Data([0xFF, 0xD8, 0xFF, 2])
    h.service.observeWebcam(
      jpegData: first, capturedAt: h.date, capturedUptime: h.uptime,
      visualHash: 0, observationSessionID: h.service.sessionID, authorizationSnapshot: h.owner)
    await h.evaluate()
    let revision = h.requests[0].contentRevision
    h.date = h.date.addingTimeInterval(29)
    h.service.observeWebcam(
      jpegData: latest, capturedAt: h.date, capturedUptime: h.uptime,
      visualHash: 0, observationSessionID: h.service.sessionID, authorizationSnapshot: h.owner)
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertEqual(h.requests.last?.contentRevision, revision)
    XCTAssertEqual(h.requests.last?.webcam?.jpegBase64, latest.base64EncodedString())
    XCTAssertEqual(h.requests.last?.inputStatus.webcam.ageMs, 1_000)
    h.date = h.date.addingTimeInterval(30)
    await h.service.evaluatePendingObservation()
    XCTAssertNil(h.requests.last?.webcam)
    XCTAssertEqual(h.requests.last?.inputStatus.webcam.status, .stale)
  }

  func testOversizedAndOldSessionWebcamFramesNeverBecomeProviderInput() async throws {
    let h = try SupervisorTestHarness()
    let oldSession = h.service.sessionID
    h.service.endSession()
    h.service.observeWebcam(
      jpegData: Data([0xFF, 0xD8, 0xFF]), capturedAt: h.date, capturedUptime: h.uptime,
      visualHash: 0, observationSessionID: oldSession, authorizationSnapshot: h.owner)
    h.service.observeWebcam(
      jpegData: Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 0, count: 256_000),
      capturedAt: h.date, capturedUptime: h.uptime, visualHash: 0,
      observationSessionID: h.service.sessionID, authorizationSnapshot: h.owner)
    h.service.observeVoice(userText: "other inputs still work", turnID: "turn", outcome: "completed")
    await h.evaluate()
    XCTAssertNil(h.requests.last?.webcam)
    XCTAssertEqual(h.requests.last?.conversation.first?.text, "other inputs still work")
  }

  func testEightHourAdaptiveProfilesRespectSharedBudgetAndSuspension() async throws {
    var report: [String: Int] = [:]
    for profile in ["changed", "bursty", "suspended"] {
      let h = try SupervisorTestHarness()
      h.evaluation = { request, _ in SupervisorTestHarness.response(request, action: .wait) }
      for second in 0..<28_800 {
        if profile == "suspended" { h.service.setSuspended(second >= 3_600) }
        if profile != "bursty" || second % 60 < 10 {
          h.service.observeVoice(
            userText: "revision \(second)", turnID: "turn", outcome: "generated",
            revision: second, isFinal: false)
        }
        await h.evaluate()
      }
      report[profile] = h.requests.count
      XCTAssertLessThanOrEqual(h.requests.count, 5_763, "three initial tokens plus one per five seconds")
      if profile == "changed" { XCTAssertGreaterThan(h.requests.count, 5_750) }
      if profile == "bursty" {
        XCTAssertGreaterThan(h.requests.count, 960)
        XCTAssertLessThan(h.requests.count, 4_000)
      }
      if profile == "suspended" {
        XCTAssertLessThanOrEqual(h.requests.count, 723)
        XCTAssertEqual(h.service.state, .suspended)
      }
    }
    print("Supervisor offline eight-hour request counts (fake clock, zero provider latency): \(report)")
  }

  func testSustainedSameContextChangesDoNotStarveSingleFlightAndLatestPendingWins() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request)
    }
    h.service.observeVoice(userText: "first", turnID: "turn", outcome: "generated")
    let pending = Task { await h.evaluate() }
    await gate.waitForStart()
    h.service.observeVoice(userText: "corrected", turnID: "turn", outcome: "completed")
    h.service.observeVoice(userText: "latest", turnID: "turn", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
    gate.release()
    await pending.value
    XCTAssertEqual(h.delivered.count, 1, "same-context events must not starve the current request")
    let firstGuidance = try XCTUnwrap(h.delivered.first)
    h.evaluation = nil
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertEqual(h.requests.last?.conversation.map(\.text), ["latest"])
    XCTAssertEqual(h.delivered.count, 2)
    XCTAssertFalse(h.service.isCurrent(firstGuidance), "only the latest accepted guidance remains actionable")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2, "unchanged observations never poll the model")
  }

  func testAppIdentityChangeRejectsInFlightGuidanceBeforeAnotherFrameArrives() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request)
    }
    h.service.observeFrame(
      .init(jpegData: Data(), appName: "Editor", windowTitle: "Document", frameNumber: 1, captureTime: h.date),
      authorizationSnapshot: h.owner, visualHash: 0)
    let pending = Task { await h.evaluate() }
    await gate.waitForStart()
    h.service.applicationContextChanged(
      appName: "Browser", windowTitle: "New task", windowID: 2,
      authorizationSnapshot: h.owner)
    gate.release()
    await pending.value
    XCTAssertTrue(h.delivered.isEmpty)
  }

  func testQueuedGuidanceRevokesOnWindowIdentityWithoutAnyCapturedFrame() async throws {
    let h = try SupervisorTestHarness()
    h.service.applicationContextChanged(
      appName: "Editor", windowTitle: "Document", windowID: 1, authorizationSnapshot: h.owner)
    h.service.observeVoice(userText: "Help with this document", turnID: "turn", outcome: "completed")
    await h.evaluate()
    let guidance = try XCTUnwrap(h.delivered.first)
    XCTAssertTrue(h.service.isCurrent(guidance))
    h.service.applicationContextChanged(
      appName: "Editor", windowTitle: "Document", windowID: 2, authorizationSnapshot: h.owner)
    XCTAssertFalse(h.service.isCurrent(guidance), "next PTT must not consume advice for the previous window")
    let epoch = h.service.contextEpoch
    h.service.applicationContextChanged(
      appName: "Editor", windowTitle: "Document", windowID: 2, authorizationSnapshot: h.owner)
    XCTAssertEqual(h.service.contextEpoch, epoch, "a missing image must not make unchanged identity look new")
  }

  func testLateCaptureCannotRestoreTheDepartedApplicationContext() throws {
    let h = try SupervisorTestHarness()
    h.service.applicationContextChanged(appName: "Editor", authorizationSnapshot: h.owner)
    let departedEpoch = h.service.contextEpoch
    h.service.applicationContextChanged(appName: "Browser", authorizationSnapshot: h.owner)
    let currentEpoch = h.service.contextEpoch
    h.service.observeFrame(
      .init(jpegData: Data(), appName: "Editor", frameNumber: 1, captureTime: h.date),
      authorizationSnapshot: h.owner, visualHash: 0, applicationContextEpoch: departedEpoch)
    XCTAssertEqual(h.service.contextEpoch, currentEpoch)
    XCTAssertEqual(h.service.currentVoiceContext(), "")
  }

  func testSessionResetRevokesAdviceAndSharingWithoutOverlappingOldRequest() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request)
    }
    h.service.evaluationSharing = true
    let oldSession = h.service.sessionID
    h.service.observeVoice(userText: "old session", turnID: "old", outcome: "completed")
    let pending = Task { await h.evaluate() }
    await gate.waitForStart()
    h.service.endSession()
    XCTAssertFalse(h.service.evaluationSharing)
    XCTAssertNotEqual(h.service.sessionID, oldSession)
    h.service.observeVoice(userText: "new session", turnID: "new", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
    gate.release()
    await pending.value
    XCTAssertTrue(h.delivered.isEmpty)
    h.evaluation = nil
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertFalse(h.requests[1].evaluationSharing)
    XCTAssertEqual(h.requests[1].conversation.map(\.text), ["new session"])
  }

  func testSameUIDNewAuthorizationRevokesInFlightResponse() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request)
    }
    h.service.observeVoice(userText: "old owner generation", turnID: "old", outcome: "completed")
    let pending = Task { await h.evaluate() }
    await gate.waitForStart()
    h.authority.beginTransition()
    h.authority.endTransition(ownerID: "supervisor-test")
    h.owner = try XCTUnwrap(h.authority.capture(ownerID: "supervisor-test", expectedOwnerID: nil))
    gate.release()
    await pending.value
    XCTAssertTrue(h.delivered.isEmpty)
  }

  func testDelayedAmbientAudioOverlappingPTTOrPlaybackIsExcludedOnlyFromSupervisor() async throws {
    let h = try SupervisorTestHarness()
    let producer = UUID()
    h.service.observeVoiceActivity(turnID: "spoken", active: true, occurredAt: h.date)
    h.date = h.date.addingTimeInterval(5)
    h.service.observeVoiceActivity(turnID: "spoken", active: false, occurredAt: h.date)
    h.uptime = 110
    let segments = [
      h.segment("before", capture: .init(start: 98, end: 99), producer: producer),
      h.segment("echo", id: "echo", capture: .init(start: 103, end: 106), producer: producer),
      h.segment("unknown", id: "unknown", capture: nil, producer: producer),
      h.segment("after", id: "after", source: .mixed, capture: .init(start: 107, end: 109), producer: producer),
    ]
    h.service.observeAmbient(segments, sessionID: 1, authorizationSnapshot: h.owner)
    await h.evaluate()
    XCTAssertEqual(h.requests[0].transcripts.map(\.text), ["before", "after"])
    XCTAssertEqual(h.requests[0].transcripts.last?.source, .mixed)
    XCTAssertEqual(segments.count, 4, "B does not mutate the recording/UI input")
  }

  func testCorrectionsReplaceAmbientTextAndUnknownClockRevokesEarlierVersion() async throws {
    let h = try SupervisorTestHarness()
    let producer = UUID()
    h.service.observeAmbient([h.segment("draft", producer: producer)], sessionID: 7, authorizationSnapshot: h.owner)
    h.service.observeAmbient([h.segment("corrected", producer: producer)], sessionID: 7, authorizationSnapshot: h.owner)
    await h.evaluate()
    XCTAssertEqual(h.requests[0].transcripts.map(\.text), ["corrected"])
    h.service.observeAmbient(
      [h.segment("uncertain", capture: nil, producer: producer)], sessionID: 7, authorizationSnapshot: h.owner)
    await h.evaluate()
    XCTAssertTrue(h.requests[1].transcripts.isEmpty)
  }

  func testBoundedInputsAndOldAmbientExpiry() async throws {
    let h = try SupervisorTestHarness()
    let producer = UUID()
    h.memory = .init(
      memories: Array(repeating: String(repeating: "m", count: 1_100), count: 25),
      profile: String(repeating: "p", count: 9_000))
    for index in 0..<30 {
      h.service.observeAmbient(
        [h.segment(String(repeating: "a", count: 1_100), id: "\(index)", producer: producer)], sessionID: 1,
        authorizationSnapshot: h.owner)
      h.service.observeVoice(
        userText: String(repeating: "u", count: 1_100), assistantText: "answer", turnID: "\(index)",
        outcome: "delivered")
    }
    await h.evaluate()
    let request = h.requests[0]
    XCTAssertEqual(request.transcripts.count, 24)
    XCTAssertEqual(request.transcripts.first?.text.count, 1_000)
    XCTAssertEqual(request.conversation.count, 16)
    XCTAssertEqual(request.conversation.first?.text.count, 1_000)
    XCTAssertEqual(request.conversation.last?.outcome, "completed")
    XCTAssertEqual(request.memories.count, 20)
    XCTAssertEqual(request.memories.first?.count, 1_000)
    XCTAssertEqual(request.profile.count, 8_000)
    h.uptime = 230
    h.service.observeVoice(userText: "new observation", turnID: "new", outcome: "completed")
    await h.evaluate()
    XCTAssertTrue(h.requests[1].transcripts.isEmpty)
  }

  func testQuotaFailurePausesAndDoesNotRetryUnchangedOrImmediateNewEvents() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw SupervisorRequestError.rateLimited(reason: "daily_quota", retryAfterSeconds: 86_400)
    }
    h.service.observeVoice(userText: "first", turnID: "1", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.service.state, .paused)
    h.service.observeVoice(userText: "next", turnID: "2", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
    h.date = h.date.addingTimeInterval(61)
    h.service.observeVoice(userText: "after a minute", turnID: "3", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1, "daily exhaustion must not retry on the burst cooldown")
    XCTAssertEqual(h.service.state, .paused)
    XCTAssertTrue(h.delivered.isEmpty)
  }

  func testBurstQuotaRetriesOnlyFreshObservationsAfterCooldown() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw SupervisorRequestError.rateLimited(reason: "burst_quota", retryAfterSeconds: 60) }
    h.service.observeVoice(userText: "first", turnID: "1", outcome: "completed")
    await h.evaluate()
    h.evaluation = nil
    h.service.observeVoice(userText: "too soon", turnID: "2", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 1)
    h.date = h.date.addingTimeInterval(61)
    h.service.observeVoice(userText: "fresh observation", turnID: "3", outcome: "completed")
    await h.evaluate()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertEqual(h.delivered.count, 1)
  }

  func testWaitDecisionDoesNotDeliverAndDisabledStateRevokesPendingAdvice() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { request, _ in SupervisorTestHarness.response(request, action: .wait) }
    h.service.observeVoice(userText: "first", turnID: "1", outcome: "completed")
    await h.evaluate()
    XCTAssertTrue(h.delivered.isEmpty)
    h.evaluation = nil
    h.service.observeVoice(userText: "second", turnID: "2", outcome: "completed")
    await h.evaluate()
    let guidance = h.delivered[0]
    h.service.enabled = false
    XCTAssertFalse(h.service.isCurrent(guidance))
    XCTAssertEqual(h.service.state, .disabled)
    XCTAssertFalse(h.defaults.bool(forKey: SupervisorService.enabledDefaultsKey))
  }
}
