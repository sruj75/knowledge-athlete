import Combine
import Foundation

struct SupervisorVoiceObservationAdmission: Equatable, Sendable {
  let sessionID: String
  let authorization: RuntimeOwnerAuthorizationSnapshot
}

/// One background reader. This service never writes product records or presents
/// a notification; accepted guidance crosses the existing voice owner boundary.
@MainActor
final class SupervisorService: ObservableObject {
  static let shared = SupervisorService()
  static let enabledDefaultsKey = "supervisorEnabled"

  typealias Evaluator =
    @MainActor (SupervisorEvaluationRequest, RuntimeOwnerAuthorizationSnapshot) async throws ->
    SupervisorEvaluationResponse
  typealias MemoryLoader = @MainActor (RuntimeOwnerAuthorizationSnapshot) async -> SupervisorMemoryContext
  typealias Delivery = @MainActor (SupervisorGuidance) async -> Void
  typealias DecisionRecorder =
    @MainActor (
      SupervisorEvaluationRequest, SupervisorEvaluationResponse, RuntimeOwnerAuthorizationSnapshot
    ) -> Void

  @Published var enabled: Bool {
    didSet {
      defaults.set(enabled, forKey: Self.enabledDefaultsKey)
      if !enabled { endSession() }
      state = enabled ? .idle : .disabled
    }
  }
  /// Explicit opt-in for this logical session only. Never persisted in defaults.
  @Published var evaluationSharing = false
  @Published private(set) var sessionID = UUID().uuidString.lowercased()
  @Published private(set) var contextEpoch: UInt64 = 0
  @Published private(set) var state: SupervisorState = .idle
  @Published private(set) var pendingGuidance: SupervisorGuidance?

  private let defaults: UserDefaults
  private let now: () -> Date
  private let monotonicNow: () -> TimeInterval
  private let currentOwner: () -> RuntimeOwnerAuthorizationSnapshot?
  private let ownerIsCurrent: (RuntimeOwnerAuthorizationSnapshot) -> Bool
  private let evaluate: Evaluator
  private let loadMemory: MemoryLoader
  private let deliver: Delivery
  private let decisionStarted: @MainActor (String) -> Void
  private let recordDecision: DecisionRecorder
  private let automaticallySchedule: Bool
  private var owner: RuntimeOwnerAuthorizationSnapshot?
  private var frame: CapturedFrame?
  private var frameHash: UInt64?
  private var applicationName: String?
  private var applicationWindowTitle: String?
  private var applicationWindowID: UInt32?
  private var transcripts: [SupervisorTranscriptInput] = []
  private var transcriptCaptures: [String: SupervisorCaptureInterval] = [:]
  private var conversation: [SupervisorConversationInput] = []
  private var activeVoiceIntervals: [String: TimeInterval] = [:]
  private var voiceIntervals: [SupervisorCaptureInterval] = []
  private var dirty = false
  private var changedAt = Date.distantPast
  private var scheduled: Task<Void, Never>?
  private var evaluationID: UUID?
  private var pauseUntil = Date.distantPast
  private var ownerObserver: NSObjectProtocol?

  init(
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init,
    monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    currentOwner: @escaping () -> RuntimeOwnerAuthorizationSnapshot? = {
      RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    },
    ownerIsCurrent: @escaping (RuntimeOwnerAuthorizationSnapshot) -> Bool = {
      RuntimeOwnerIdentity.isAuthorizationCurrent($0)
    },
    evaluate: @escaping Evaluator = {
      try await APIClient.shared.evaluateSupervisor(request: $0, authorizationSnapshot: $1)
    },
    loadMemory: @escaping MemoryLoader = { authorization in
      let memories =
        (try? await MemoryStorage.shared.list(
          limit: 20, authorizationSnapshot: authorization)) ?? []
      let profile = await AIUserProfileService.shared.getLatestProfile(authorizationSnapshot: authorization)
      return SupervisorMemoryContext(
        memories: memories.map { String($0.content.prefix(1_000)) },
        profile: String((profile?.profileText ?? "").prefix(8_000)))
    },
    deliver: @escaping Delivery = { guidance in
      _ = await RealtimeHubController.shared.submitSupervisorGuidance(guidance)
    },
    decisionStarted: @escaping @MainActor (String) -> Void = {
      AIEvaluationReporter.shared.captureDecisionStart(observationID: $0)
    },
    recordDecision: @escaping DecisionRecorder = {
      AIEvaluationReporter.shared.recordDecision(
        request: $0, response: $1, authorizationSnapshot: $2)
    },
    automaticallySchedule: Bool = true
  ) {
    self.defaults = defaults
    self.now = now
    self.monotonicNow = monotonicNow
    self.currentOwner = currentOwner
    self.ownerIsCurrent = ownerIsCurrent
    self.evaluate = evaluate
    self.loadMemory = loadMemory
    self.deliver = deliver
    self.decisionStarted = decisionStarted
    self.recordDecision = recordDecision
    self.automaticallySchedule = automaticallySchedule
    self.enabled =
      defaults.object(forKey: Self.enabledDefaultsKey) == nil
      ? true : defaults.bool(forKey: Self.enabledDefaultsKey)
    self.state = enabled ? .idle : .disabled
    ownerObserver = NotificationCenter.default.addObserver(
      forName: .runtimeOwnerDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.endSession() }
    }
  }

  func endSession() {
    scheduled?.cancel()
    scheduled = nil
    // A request already admitted to the transport retains the single-flight
    // slot until it completes. Its old session can never deliver a result.
    owner = nil
    dirty = false
    frame = nil
    frameHash = nil
    applicationName = nil
    applicationWindowTitle = nil
    applicationWindowID = nil
    transcripts.removeAll()
    transcriptCaptures.removeAll()
    conversation.removeAll()
    activeVoiceIntervals.removeAll()
    voiceIntervals.removeAll()
    pendingGuidance = nil
    evaluationSharing = false
    contextEpoch &+= 1
    sessionID = UUID().uuidString.lowercased()
    pauseUntil = .distantPast
    state = enabled ? .idle : .disabled
  }

  private func admit(_ supplied: RuntimeOwnerAuthorizationSnapshot?) -> Bool {
    guard enabled, let snapshot = supplied ?? currentOwner(), ownerIsCurrent(snapshot) else { return false }
    if let owner, owner != snapshot { endSession() }
    owner = snapshot
    return true
  }

  func captureVoiceObservationAdmission() -> SupervisorVoiceObservationAdmission? {
    guard admit(nil), let owner else { return nil }
    return .init(sessionID: sessionID, authorization: owner)
  }

  func observeVoice(
    userText: String? = nil, assistantText: String? = nil, turnID: String, outcome: String,
    admission: SupervisorVoiceObservationAdmission
  ) {
    // A provider callback cannot adopt a new monitoring session after capture began.
    guard admission.sessionID == sessionID, owner == admission.authorization else { return }
    observeVoice(
      userText: userText, assistantText: assistantText, turnID: turnID, outcome: outcome,
      authorizationSnapshot: admission.authorization)
  }

  /// App/window identity is known before pixels are ready. Revoke old advice
  /// at that boundary even when capture is throttled, unavailable or absent.
  func applicationContextChanged(
    appName: String?, windowTitle: String? = nil, windowID: UInt32? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard admit(authorizationSnapshot) else { return }
    let appChanged = applicationName != appName
    let changed =
      appChanged || applicationWindowTitle != windowTitle
      || (windowID != nil && applicationWindowID != windowID)
    guard changed else { return }
    applicationName = appName
    applicationWindowTitle = windowTitle
    applicationWindowID = windowID ?? (appChanged ? nil : applicationWindowID)
    frame = nil
    frameHash = nil
    markChanged(invalidateContext: true)
  }

  func observeFrame(
    _ next: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    visualHash: UInt64? = nil,
    applicationContextEpoch: UInt64? = nil
  ) {
    guard admit(authorizationSnapshot),
      applicationContextEpoch == nil || applicationContextEpoch == contextEpoch
    else { return }
    applicationContextChanged(
      appName: next.appName, windowTitle: next.windowTitle,
      authorizationSnapshot: authorizationSnapshot)
    guard !SupervisorScreenPolicy.isAppExcluded(next.appName) else {
      screenUnavailable()
      return
    }
    let visualChanged =
      visualHash.map { hash in
        frameHash.map { (hash ^ $0).nonzeroBitCount >= 8 } ?? true
      } ?? (frame == nil)
    frame = next
    if visualChanged {
      frameHash = visualHash
      markChanged()
    }
  }

  /// Privacy exclusions revoke the previous image immediately, even when the
  /// next capture tick exits before producing another permitted frame.
  func screenUnavailable() {
    guard frame != nil else { return }
    frame = nil
    frameHash = nil
    markChanged(invalidateContext: true)
  }

  func observeAmbient(
    _ segments: [TranscriptionService.BackendSegment],
    sessionID ambientSessionID: Int64,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard admit(authorizationSnapshot) else { return }
    var changed = pruneAmbient()
    for segment in segments {
      let suffix = ":\(segment.segmentId)"
      let prefix = "\(ambientSessionID):"
      guard let provenance = segment.supervisorProvenance else {
        // A correction with no trustworthy clock cannot leave its earlier text
        // behind in B's view. Local recording and transcript UI are unaffected.
        changed = removeAmbient { $0.id.hasPrefix(prefix) && $0.id.hasSuffix(suffix) } || changed
        continue
      }
      let id = "\(prefix)\(provenance.producerID.uuidString)\(suffix)"
      let capture = provenance.capture
      let text = String(segment.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
      guard capture.end >= monotonicNow() - 120, capture.end <= monotonicNow() + 1,
        !overlapsVoice(capture), !text.isEmpty
      else {
        changed = removeAmbient { $0.id == id } || changed
        continue
      }
      let input = SupervisorTranscriptInput(id: id, text: text, source: provenance.source)
      transcriptCaptures[id] = capture
      if let index = transcripts.firstIndex(where: { $0.id == id }) {
        guard transcripts[index] != input else { continue }
        transcripts[index] = input
      } else {
        transcripts.append(input)
      }
      changed = true
    }
    if transcripts.count > 24 {
      for old in transcripts.prefix(transcripts.count - 24) { transcriptCaptures[old.id] = nil }
      transcripts.removeFirst(transcripts.count - 24)
    }
    if changed { markChanged() }
  }

  @discardableResult
  private func removeAmbient(where predicate: (SupervisorTranscriptInput) -> Bool) -> Bool {
    let removed = transcripts.filter(predicate)
    for input in removed { transcriptCaptures[input.id] = nil }
    transcripts.removeAll(where: predicate)
    return !removed.isEmpty
  }

  private func pruneAmbient() -> Bool {
    let cutoff = monotonicNow() - 120
    return removeAmbient { input in
      guard let capture = transcriptCaptures[input.id] else { return true }
      return capture.end < cutoff || overlapsVoice(capture)
    }
  }

  func observeVoice(
    userText: String? = nil,
    assistantText: String? = nil,
    turnID: String,
    outcome: String,
    occurredAt: Date = Date(),
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) {
    guard admit(authorizationSnapshot) else { return }
    let terminal: String? =
      switch outcome {
      case "completed", "delivered": "completed"
      case "cancelled", "interrupted": "cancelled"
      case "failed": "failed"
      case "suppressed": "suppressed"
      default: nil
      }
    var changed = false
    for (role, content) in [("user", userText), ("assistant", assistantText)] {
      let index = conversation.firstIndex { $0.turnID == turnID && $0.role == role }
      let text = String((content ?? index.map { conversation[$0].text } ?? "").prefix(1_000))
      guard !text.isEmpty else { continue }
      let input = SupervisorConversationInput(turnID: turnID, role: role, text: text, outcome: terminal)
      if let index {
        guard conversation[index] != input else { continue }
        conversation[index] = input
      } else {
        conversation.append(input)
      }
      changed = true
    }
    if conversation.count > 16 { conversation.removeFirst(conversation.count - 16) }
    if changed { markChanged() }
  }

  func observeVoiceActivity(turnID: String, active: Bool, occurredAt: Date = Date()) {
    guard admit(nil) else { return }
    let time = monotonicNow() + occurredAt.timeIntervalSince(now())
    if active {
      if activeVoiceIntervals[turnID] == nil { activeVoiceIntervals[turnID] = time }
    } else if let start = activeVoiceIntervals.removeValue(forKey: turnID) {
      voiceIntervals.append(.init(start: start, end: max(start, time)))
      if voiceIntervals.count > 128 { voiceIntervals.removeFirst(voiceIntervals.count - 128) }
    }
  }

  private func overlapsVoice(_ capture: SupervisorCaptureInterval) -> Bool {
    voiceIntervals.contains { $0.overlaps(capture) }
      || activeVoiceIntervals.values.contains { capture.end > $0 }
  }

  private func markChanged(invalidateContext: Bool = false) {
    // Only app/window/privacy boundaries revoke an in-flight interpretation.
    // Same-context events replace the next snapshot without starving a request
    // whose response is slower than the capture or transcript cadence.
    if invalidateContext {
      contextEpoch &+= 1
      pendingGuidance = nil
    }
    changedAt = now()
    dirty = true
    if state != .paused { state = .observing }
    schedule()
  }

  private func schedule() {
    guard automaticallySchedule, enabled, dirty, scheduled == nil, evaluationID == nil,
      pauseUntil != .distantFuture
    else { return }
    let delay = max(3, pauseUntil.timeIntervalSince(now()))
    scheduled = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self else { return }
      self.scheduled = nil
      await self.evaluatePendingObservation()
    }
  }

  func isCurrent(_ guidance: SupervisorGuidance) -> Bool {
    enabled && ownerIsCurrent(guidance.authorizationSnapshot)
      && owner == guidance.authorizationSnapshot && guidance.sessionID == sessionID
      && guidance.contextEpoch == contextEpoch && guidance.expiresAt > now()
      && pendingGuidance?.id == guidance.id
      && frame.map { !SupervisorScreenPolicy.isAppExcluded($0.appName) } != false
  }

  func evaluatePendingObservation() async {
    guard enabled, dirty, evaluationID == nil, now() >= pauseUntil,
      let owner, ownerIsCurrent(owner)
    else { return }
    let token = UUID()
    evaluationID = token
    dirty = false
    state = .evaluating
    let session = sessionID
    let epoch = contextEpoch
    let expires = changedAt.addingTimeInterval(30)
    let observedFrame = frame
    _ = pruneAmbient()
    let transcriptSnapshot = transcripts
    let conversationSnapshot = conversation
    defer {
      if evaluationID == token {
        evaluationID = nil
        if state == .evaluating { state = .observing }
        schedule()
      }
    }
    let memory = await loadMemory(owner)
    guard enabled, ownerIsCurrent(owner), sessionID == session, contextEpoch == epoch,
      now() < expires, !Task.isCancelled
    else { return }
    if let observedFrame, SupervisorScreenPolicy.isAppExcluded(observedFrame.appName) {
      screenUnavailable()
      return
    }
    let screen: SupervisorScreenInput? = observedFrame.flatMap { captured in
      guard now().timeIntervalSince(captured.captureTime) <= 30 else { return nil }
      let data = SuggestionFramePreview.downscaledJPEG(from: captured.jpegData)
      guard data.count <= 2_000_000, data.starts(with: [0xFF, 0xD8, 0xFF]) else { return nil }
      return .init(
        jpegBase64: data.base64EncodedString(), appName: String(captured.appName.prefix(256)),
        windowTitle: captured.windowTitle.map { String($0.prefix(512)) },
        capturedAt: ISO8601DateFormatter().string(from: captured.captureTime))
    }
    let request = SupervisorEvaluationRequest(
      observationID: UUID().uuidString.lowercased(), sessionID: session, contextEpoch: epoch,
      screen: screen, transcripts: transcriptSnapshot, conversation: conversationSnapshot,
      memories: Array(memory.memories.prefix(20)).map { String($0.prefix(1_000)) },
      profile: String(memory.profile.prefix(8_000)), evaluationSharing: evaluationSharing)
    do {
      decisionStarted(request.observationID)
      let response = try await evaluate(request, owner)
      if let observedFrame, SupervisorScreenPolicy.isAppExcluded(observedFrame.appName) {
        screenUnavailable()
        return
      }
      guard enabled, ownerIsCurrent(owner), sessionID == session, contextEpoch == epoch,
        now() < expires, !Task.isCancelled,
        response.observationID == request.observationID,
        response.sessionID == session, response.contextEpoch == epoch
      else { return }
      recordDecision(request, response, owner)
      pendingGuidance = nil
      guard response.outcome == "completed", response.action != .wait,
        let note = response.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty
      else { return }
      var guidance = SupervisorGuidance(
        id: response.decisionID, observationID: request.observationID,
        sessionID: session, contextEpoch: epoch, note: String(note.prefix(2_000)),
        expiresAt: expires, authorizationSnapshot: owner, action: response.action)
      guidance.context = Self.voiceContext(request)
      pendingGuidance = guidance
      await deliver(guidance)
    } catch {
      guard sessionID == session, ownerIsCurrent(owner), evaluationID == token else { return }
      state = .paused
      pauseUntil = now().addingTimeInterval(60)
      if case APIError.httpError(429, let detail) = error,
        detail == "Daily Gemini request limit exceeded"
      {
        pauseUntil = .distantFuture
      }
    }
  }

  /// Current permitted observations for A's next accepted user turn. This
  /// contains no supervisor note and never starts a capture or storage query.
  func currentVoiceContext(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) -> String {
    guard enabled, let owner, ownerIsCurrent(owner),
      authorizationSnapshot == nil || authorizationSnapshot == owner
    else { return "" }
    _ = pruneAmbient()
    let screen: SupervisorScreenInput? = frame.flatMap { captured in
      guard !SupervisorScreenPolicy.isAppExcluded(captured.appName),
        now().timeIntervalSince(captured.captureTime) <= 30
      else { return nil }
      return .init(
        jpegBase64: "", appName: captured.appName,
        windowTitle: captured.windowTitle, capturedAt: "")
    }
    return Self.voiceContext(
      .init(
        observationID: "", sessionID: sessionID, contextEpoch: contextEpoch,
        screen: screen, transcripts: transcripts, conversation: [], memories: [],
        profile: "", evaluationSharing: false))
  }

  private static func voiceContext(_ request: SupervisorEvaluationRequest) -> String {
    var lines: [String] = []
    if let screen = request.screen {
      lines.append("Observed app: \(screen.appName). Window: \(screen.windowTitle ?? "unknown").")
    }
    lines += request.transcripts.suffix(4).map { "[\($0.source.rawValue)] \($0.text)" }
    return String(lines.joined(separator: "\n").prefix(4_000))
  }
}
