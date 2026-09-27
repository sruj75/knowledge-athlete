import XCTest

@testable import Omi_Computer

@MainActor
private final class SupervisorTestHarness {
  let authority = RuntimeOwnerAuthorizationAuthority()
  var owner: RuntimeOwnerAuthorizationSnapshot
  var date = Date(timeIntervalSince1970: 1_800_000_000)
  var uptime: TimeInterval = 100
  var requests: [SupervisorEvaluationRequest] = []
  var delivered: [SupervisorGuidance] = []
  var evaluation: SupervisorService.Evaluator?
  var automaticallySchedule = false
  var memory = SupervisorMemoryContext.empty
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
    loadMemory: { _ in self.memory }, deliver: { self.delivered.append($0) },
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
  func testProductionThreeSecondSchedulerCoalescesBurstIntoOneLatestRequest() async throws {
    let h = try SupervisorTestHarness()
    h.automaticallySchedule = true
    let evaluated = expectation(description: "coalesced evaluation")
    h.evaluation = { request, _ in
      evaluated.fulfill()
      return SupervisorTestHarness.response(request, action: .wait)
    }
    h.service.observeVoice(userText: "draft", turnID: "turn", outcome: "generated")
    h.service.observeVoice(userText: "correction", turnID: "turn", outcome: "generated")
    h.service.observeVoice(userText: "final", turnID: "turn", outcome: "completed")
    XCTAssertTrue(h.requests.isEmpty)
    await fulfillment(of: [evaluated], timeout: 5)
    XCTAssertEqual(h.requests.count, 1)
    XCTAssertEqual(h.requests.first?.conversation.map(\.text), ["final"])
    h.service.endSession()
  }

  func testFreshContextEvaluatesWithoutStoredHistoryAndExpiresItsAdvice() async throws {
    let h = try SupervisorTestHarness()
    h.service.observeVoice(userText: "I am writing a report", turnID: "turn", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1)
    XCTAssertTrue(h.requests[0].memories.isEmpty)
    let guidance = try XCTUnwrap(h.delivered.first)
    XCTAssertTrue(h.service.isCurrent(guidance))
    h.date = h.date.addingTimeInterval(31)
    XCTAssertFalse(h.service.isCurrent(guidance))
  }

  func testSustainedSameContextChangesDoNotStarveSingleFlightAndLatestPendingWins() async throws {
    let h = try SupervisorTestHarness()
    let gate = SupervisorRequestGate()
    h.evaluation = { request, _ in
      await gate.hold()
      return SupervisorTestHarness.response(request)
    }
    h.service.observeVoice(userText: "first", turnID: "turn", outcome: "generated")
    let pending = Task { await h.service.evaluatePendingObservation() }
    await gate.waitForStart()
    h.service.observeVoice(userText: "corrected", turnID: "turn", outcome: "completed")
    h.service.observeVoice(userText: "latest", turnID: "turn", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1)
    gate.release()
    await pending.value
    XCTAssertEqual(h.delivered.count, 1, "same-context events must not starve the current request")
    let firstGuidance = try XCTUnwrap(h.delivered.first)
    h.evaluation = nil
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertEqual(h.requests.last?.conversation.map(\.text), ["latest"])
    XCTAssertEqual(h.delivered.count, 2)
    XCTAssertFalse(h.service.isCurrent(firstGuidance), "only the latest accepted guidance remains actionable")
    await h.service.evaluatePendingObservation()
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
    let pending = Task { await h.service.evaluatePendingObservation() }
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
    await h.service.evaluatePendingObservation()
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
    let pending = Task { await h.service.evaluatePendingObservation() }
    await gate.waitForStart()
    h.service.endSession()
    XCTAssertFalse(h.service.evaluationSharing)
    XCTAssertNotEqual(h.service.sessionID, oldSession)
    h.service.observeVoice(userText: "new session", turnID: "new", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1)
    gate.release()
    await pending.value
    XCTAssertTrue(h.delivered.isEmpty)
    h.evaluation = nil
    await h.service.evaluatePendingObservation()
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
    let pending = Task { await h.service.evaluatePendingObservation() }
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
    h.uptime = 105
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
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests[0].transcripts.map(\.text), ["before", "after"])
    XCTAssertEqual(h.requests[0].transcripts.last?.source, .mixed)
    XCTAssertEqual(segments.count, 4, "B does not mutate the recording/UI input")
  }

  func testCorrectionsReplaceAmbientTextAndUnknownClockRevokesEarlierVersion() async throws {
    let h = try SupervisorTestHarness()
    let producer = UUID()
    h.service.observeAmbient([h.segment("draft", producer: producer)], sessionID: 7, authorizationSnapshot: h.owner)
    h.service.observeAmbient([h.segment("corrected", producer: producer)], sessionID: 7, authorizationSnapshot: h.owner)
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests[0].transcripts.map(\.text), ["corrected"])
    h.service.observeAmbient(
      [h.segment("uncertain", capture: nil, producer: producer)], sessionID: 7, authorizationSnapshot: h.owner)
    await h.service.evaluatePendingObservation()
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
    await h.service.evaluatePendingObservation()
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
    await h.service.evaluatePendingObservation()
    XCTAssertTrue(h.requests[1].transcripts.isEmpty)
  }

  func testQuotaFailurePausesAndDoesNotRetryUnchangedOrImmediateNewEvents() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw APIError.httpError(statusCode: 429, detail: "Daily Gemini request limit exceeded") }
    h.service.observeVoice(userText: "first", turnID: "1", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.service.state, .paused)
    h.service.observeVoice(userText: "next", turnID: "2", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1)
    h.date = h.date.addingTimeInterval(61)
    h.service.observeVoice(userText: "after a minute", turnID: "3", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1, "daily exhaustion must not retry on the burst cooldown")
    XCTAssertEqual(h.service.state, .paused)
    XCTAssertTrue(h.delivered.isEmpty)
  }

  func testBurstQuotaRetriesOnlyFreshObservationsAfterCooldown() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { _, _ in throw APIError.httpError(statusCode: 429, detail: "Gemini request limit exceeded") }
    h.service.observeVoice(userText: "first", turnID: "1", outcome: "completed")
    await h.service.evaluatePendingObservation()
    h.evaluation = nil
    h.service.observeVoice(userText: "too soon", turnID: "2", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 1)
    h.date = h.date.addingTimeInterval(61)
    h.service.observeVoice(userText: "fresh observation", turnID: "3", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertEqual(h.requests.count, 2)
    XCTAssertEqual(h.delivered.count, 1)
  }

  func testWaitDecisionDoesNotDeliverAndDisabledStateRevokesPendingAdvice() async throws {
    let h = try SupervisorTestHarness()
    h.evaluation = { request, _ in SupervisorTestHarness.response(request, action: .wait) }
    h.service.observeVoice(userText: "first", turnID: "1", outcome: "completed")
    await h.service.evaluatePendingObservation()
    XCTAssertTrue(h.delivered.isEmpty)
    h.evaluation = nil
    h.service.observeVoice(userText: "second", turnID: "2", outcome: "completed")
    await h.service.evaluatePendingObservation()
    let guidance = h.delivered[0]
    h.service.enabled = false
    XCTAssertFalse(h.service.isCurrent(guidance))
    XCTAssertEqual(h.service.state, .disabled)
    XCTAssertFalse(h.defaults.bool(forKey: SupervisorService.enabledDefaultsKey))
  }
}
