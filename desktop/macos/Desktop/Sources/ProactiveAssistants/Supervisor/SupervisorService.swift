import AVFoundation
import AppKit
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
  static let shared: SupervisorService = {
    let service = SupervisorService(audioAvailability: {
      AppState.current?.supervisorAudioAvailability ?? (.unavailable, .unavailable)
    })
    service.installSystemObservers()
    service.availabilityChanged = { SupervisorWebcamService.shared.setMonitoringAllowed($0) }
    Task { @MainActor [weak service] in
      guard let service else { return }
      service.availabilityChanged(service.isObservationAllowed)
    }
    return service
  }()
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
      state = restingState
      availabilityChanged(isObservationAllowed)
    }
  }
  /// Explicit opt-in for this logical session only. Never persisted in defaults.
  @Published var evaluationSharing = false
  @Published private(set) var sessionID = UUID().uuidString.lowercased()
  @Published private(set) var contextEpoch: UInt64 = 0
  private var relevantObservationEpoch: UInt64 = 0
  @Published private(set) var state: SupervisorState = .idle
  @Published private(set) var pendingGuidance: SupervisorGuidance?
  @Published private(set) var metrics = SupervisorObservationMetrics()
  @Published private(set) var retryAt: Date?
  var isSystemAvailable: Bool { !suspended }
  var isObservationAllowed: Bool { enabled && !suspended }

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
  private let audioAvailability: @MainActor () -> (SupervisorInputAvailability, SupervisorInputAvailability)
  private var owner: RuntimeOwnerAuthorizationSnapshot?
  private var frame: CapturedFrame?
  private var frameHash: UInt64?
  private var frameCapturedUptime: TimeInterval?
  private var webcam: (data: Data, capturedAt: Date, uptime: TimeInterval)?
  private var webcamHash: UInt64?
  private var inputStatuses = SupervisorInputStatuses()
  private var activeConversation: SupervisorActiveConversation?
  private var contentRevision: UInt64 = 0
  private var applicationName: String?
  private var applicationWindowTitle: String?
  private var applicationWindowID: UInt32?
  private var transcripts: [SupervisorTranscriptInput] = []
  private var transcriptCaptures: [String: SupervisorCaptureInterval] = [:]
  private var conversation: [SupervisorConversationInput] = []
  private var activeVoiceIntervals: [String: TimeInterval] = [:]
  private var voiceIntervals: [SupervisorCaptureInterval] = []
  private var dirty = false
  private var firstPendingAt: TimeInterval?
  private var lastAdmissionAt: TimeInterval?
  private var budgetTokens: Double = 3
  private var budgetRefilledAt: TimeInterval
  private var scheduled: Task<Void, Never>?
  private var evaluationID: UUID?
  private var pauseUntil: TimeInterval = 0
  private var pauseOwner: RuntimeOwnerAuthorizationSnapshot?
  private var diagnosticRetryReason: SupervisorDiagnosticSnapshot.RetryReason?
  private var ownerObserver: NSObjectProtocol?
  private var systemObservers: [NSObjectProtocol] = []
  private var sleeping = false
  private var locked = false
  private var suspended = false
  private var availabilityChanged: @MainActor (Bool) -> Void = { _ in }

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
      _ = await ConversationVoiceController.shared.submitSupervisorGuidance(guidance)
    },
    decisionStarted: @escaping @MainActor (String) -> Void = {
      AIEvaluationReporter.shared.captureDecisionStart(observationID: $0)
    },
    recordDecision: @escaping DecisionRecorder = {
      AIEvaluationReporter.shared.recordDecision(
        request: $0, response: $1, authorizationSnapshot: $2)
    },
    automaticallySchedule: Bool = true,
    audioAvailability: @escaping @MainActor () -> (SupervisorInputAvailability, SupervisorInputAvailability) = {
      (.unavailable, .unavailable)
    }
  ) {
    self.defaults = defaults
    self.now = now
    self.monotonicNow = monotonicNow
    self.budgetRefilledAt = monotonicNow()
    self.currentOwner = currentOwner
    self.ownerIsCurrent = ownerIsCurrent
    self.evaluate = evaluate
    self.loadMemory = loadMemory
    self.deliver = deliver
    self.decisionStarted = decisionStarted
    self.recordDecision = recordDecision
    self.automaticallySchedule = automaticallySchedule
    self.audioAvailability = audioAvailability
    self.enabled =
      defaults.object(forKey: Self.enabledDefaultsKey) == nil
      ? true : defaults.bool(forKey: Self.enabledDefaultsKey)
    self.state = enabled ? .idle : .disabled
    ownerObserver = NotificationCenter.default.addObserver(
      forName: .runtimeOwnerDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.availabilityChanged(false)
        self?.endSession()
        if let self { self.availabilityChanged(self.isObservationAllowed) }
      }
    }
  }

  func endSession() {
    scheduled?.cancel()
    scheduled = nil
    // A request already admitted to the transport retains the single-flight
    // slot until it completes. Its old session can never deliver a result.
    owner = nil
    dirty = false
    lastAdmissionAt = nil
    firstPendingAt = nil
    frame = nil
    frameHash = nil
    frameCapturedUptime = nil
    webcam = nil
    webcamHash = nil
    activeConversation = nil
    inputStatuses = SupervisorInputStatuses()
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
    relevantObservationEpoch &+= 1
    sessionID = UUID().uuidString.lowercased()
    metrics = SupervisorObservationMetrics()
    // Locking, sleep, and toggling monitoring cannot erase a server pause for
    // the same authorized owner. Owner-generation changes do clear it.
    clearRevokedPause()
    state = restingState
  }

  private func installSystemObservers() {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    locked =
      session?["CGSSessionScreenIsLocked"] as? Bool == true
      || session?[kCGSessionOnConsoleKey as String] as? Bool == false
    setSuspended(locked)
    let events: [(NotificationCenter, Notification.Name, Bool, Bool)] = [
      (NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification, true, true),
      (.default, .systemDidWake, true, false),
      (.default, .screenDidLock, false, true),
      (.default, .screenDidUnlock, false, false),
    ]
    for (center, name, isSleep, value) in events {
      systemObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self else { return }
            if isSleep { self.sleeping = value } else { self.locked = value }
            self.setSuspended(self.sleeping || self.locked)
          }
        })
    }
    for name in [Notification.Name.ambientAudioCaptureSettingsDidChange, .transcriptionSettingsDidChange] {
      systemObservers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self, self.owner != nil, self.isObservationAllowed else { return }
            self.markChanged(invalidateContext: true, invalidateObservationContext: true)
          }
        })
    }
  }

  func setSuspended(_ value: Bool) {
    guard suspended != value else { return }
    suspended = value
    if value { endSession() }
    state = restingState
    availabilityChanged(isObservationAllowed)
  }

  private var restingState: SupervisorState {
    if !enabled { return .disabled }
    if suspended { return .suspended }
    return monotonicNow() < pauseUntil ? .paused : .idle
  }

  private func clearRevokedPause() {
    guard let pauseOwner, currentOwner() == pauseOwner, ownerIsCurrent(pauseOwner) else {
      pauseOwner = nil
      pauseUntil = 0
      retryAt = nil
      diagnosticRetryReason = nil
      return
    }
  }

  private func admit(_ supplied: RuntimeOwnerAuthorizationSnapshot?) -> Bool {
    guard isObservationAllowed, let snapshot = supplied ?? currentOwner(), ownerIsCurrent(snapshot) else {
      return false
    }
    if let owner, owner != snapshot { endSession() }
    clearRevokedPause()
    owner = snapshot
    return true
  }

  func captureVoiceObservationAdmission() -> SupervisorVoiceObservationAdmission? {
    guard admit(nil), let owner else { return nil }
    return .init(sessionID: sessionID, authorization: owner)
  }

  func observeVoice(
    userText: String? = nil, assistantText: String? = nil, turnID: String, outcome: String,
    admission: SupervisorVoiceObservationAdmission, revision: Int? = nil, isFinal: Bool = true
  ) {
    // A provider callback cannot adopt a new monitoring session after capture began.
    guard admission.sessionID == sessionID, owner == admission.authorization else { return }
    observeVoice(
      userText: userText, assistantText: assistantText, turnID: turnID, outcome: outcome,
      authorizationSnapshot: admission.authorization, revision: revision, isFinal: isFinal)
  }

  func updateConversation(id: String?, state: SupervisorConversationState) {
    guard admit(nil) else { return }
    let next = id.map { SupervisorActiveConversation(id: String($0.prefix(128)), state: state) }
    guard next != activeConversation else { return }
    let invalidates = activeConversation?.id != next?.id || state == .closed
    activeConversation = next
    markChanged(invalidateContext: invalidates)
  }

  func observeWebcam(
    jpegData: Data, capturedAt: Date, capturedUptime: TimeInterval, visualHash: UInt64?,
    observationSessionID: String, authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard observationSessionID == sessionID, admit(authorizationSnapshot),
      jpegData.count <= 256_000, jpegData.starts(with: [0xFF, 0xD8, 0xFF]),
      capturedUptime <= monotonicNow(), monotonicNow() - capturedUptime <= 5
    else { return }
    let changed =
      webcam == nil || visualHash.map { hash in webcamHash.map { (hash ^ $0).nonzeroBitCount >= 8 } ?? true } == true
    webcam = (jpegData, capturedAt, capturedUptime)
    inputStatuses.webcam.status = .available
    if changed {
      webcamHash = visualHash
      markChanged()
    }
  }

  func webcamUnavailable(_ availability: SupervisorInputAvailability) {
    guard webcam != nil || inputStatuses.webcam.status != availability else { return }
    webcam = nil
    webcamHash = nil
    inputStatuses.webcam = .init(status: availability)
    guard admit(nil) else { return }
    markChanged(invalidateContext: true, invalidateObservationContext: true)
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
    frameCapturedUptime = nil
    markChanged(invalidateContext: true, invalidateObservationContext: true)
  }

  func observeFrame(
    _ next: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    visualHash: UInt64? = nil,
    applicationContextEpoch: UInt64? = nil,
    capturedUptime: TimeInterval? = nil
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
    frameCapturedUptime = capturedUptime ?? (monotonicNow() - max(0, now().timeIntervalSince(next.captureTime)))
    inputStatuses.screen.status = .available
    if visualChanged {
      frameHash = visualHash
      markChanged(invalidateObservationContext: true)
    }
  }

  /// Privacy exclusions revoke the previous image immediately, even when the
  /// next capture tick exits before producing another permitted frame.
  func screenUnavailable(_ availability: SupervisorInputAvailability = .unavailable) {
    guard frame != nil || inputStatuses.screen.status != availability else { return }
    frame = nil
    frameHash = nil
    frameCapturedUptime = nil
    inputStatuses.screen = .init(status: availability)
    guard admit(nil) else { return }
    markChanged(invalidateContext: true, invalidateObservationContext: true)
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
      var input = SupervisorTranscriptInput(id: id, text: text, source: provenance.source)
      transcriptCaptures[id] = capture
      if let index = transcripts.firstIndex(where: { $0.id == id }) {
        guard transcripts[index].text != text || transcripts[index].source != input.source else { continue }
        input.revision = transcripts[index].revision + 1
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
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    revision: Int? = nil, isFinal: Bool = true
  ) {
    guard admit(authorizationSnapshot) else { return }
    let terminal: String? =
      switch outcome {
      case "completed", "delivered": "completed"
      case "cancelled": "cancelled"
      case "interrupted": "interrupted"
      case "failed": "failed"
      case "suppressed": "suppressed"
      default: nil
      }
    var changed = false
    for (role, content) in [("user", userText), ("assistant", assistantText)] {
      let index = conversation.firstIndex { $0.turnID == turnID && $0.role == role }
      let text = String((content ?? index.map { conversation[$0].text } ?? "").prefix(1_000))
      guard !text.isEmpty else { continue }
      var input = SupervisorConversationInput(turnID: turnID, role: role, text: text, outcome: terminal)
      input.final = isFinal
      input.revision = max(0, revision ?? index.map { conversation[$0].revision + 1 } ?? 0)
      if let index {
        let previous = conversation[index]
        if previous.text == input.text, previous.outcome == input.outcome,
          previous.final == input.final, revision == nil || revision == previous.revision
        {
          continue
        }
        guard !(previous.final && !input.final),
          input.revision >= conversation[index].revision,
          input.revision != conversation[index].revision || input.text == conversation[index].text
        else { continue }
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

  private func markChanged(invalidateContext: Bool = false, invalidateObservationContext: Bool = false) {
    // Dispatch keeps its first-event deadline even when new observations arrive.
    // App/window/privacy and meaningful screen changes independently revoke old
    // interpretations; opening A changes only the logical conversation epoch.
    if invalidateContext {
      contextEpoch &+= 1
      pendingGuidance = nil
    }
    if invalidateObservationContext {
      relevantObservationEpoch &+= 1
      pendingGuidance = nil
    }
    contentRevision &+= 1
    if dirty {
      metrics.replacedPending += 1
    } else {
      firstPendingAt = monotonicNow()
      scheduled?.cancel()
      scheduled = nil
    }
    dirty = true
    if state != .paused { state = .observing }
    schedule()
  }

  private func schedule() {
    guard automaticallySchedule, isObservationAllowed, let due = nextEvaluationAt,
      scheduled == nil, evaluationID == nil
    else { return }
    refillBudget()
    let budgetReady = budgetTokens >= 1 ? monotonicNow() : monotonicNow() + (1 - budgetTokens) * 5
    if budgetReady > max(monotonicNow(), max(due, pauseUntil)) { metrics.budgetDeferrals += 1 }
    let delay = max(0, max(due, max(pauseUntil, budgetReady)) - monotonicNow())
    scheduled = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self else { return }
      self.scheduled = nil
      await self.evaluatePendingObservation()
    }
  }

  private var nextEvaluationAt: TimeInterval? {
    let event = firstPendingAt.map { $0 + 1 }
    let heartbeat = lastAdmissionAt.map { $0 + 30 }
    switch (event, heartbeat) {
    case (let event?, let heartbeat?): return min(event, heartbeat)
    case (let event?, nil): return event
    case (nil, let heartbeat?): return heartbeat
    case (nil, nil): return nil
    }
  }

  private func refillBudget() {
    let time = monotonicNow()
    budgetTokens = min(3, budgetTokens + max(0, time - budgetRefilledAt) / 5)
    budgetRefilledAt = time
  }

  /// Opening A changes the observation context and consumes the pending note.
  /// After that admission, relevant observation changes, consent, owner, session,
  /// TTL, and input exclusion can revoke delivery; pending-note identity does not.
  func isAcceptedGuidanceAllowed(_ guidance: SupervisorGuidance) -> Bool {
    isObservationAllowed && ownerIsCurrent(guidance.authorizationSnapshot)
      && owner == guidance.authorizationSnapshot && guidance.sessionID == sessionID
      && guidance.relevantObservationEpoch == relevantObservationEpoch
      && guidance.expiresAt > now()
      && applicationName.map { !RewindSettings.shared.isAppExcluded($0) } != false
      && frame.map { !SupervisorScreenPolicy.isAppExcluded($0.appName) } != false
  }

  func isCurrent(_ guidance: SupervisorGuidance) -> Bool {
    isAcceptedGuidanceAllowed(guidance)
      && guidance.contextEpoch == contextEpoch && pendingGuidance?.id == guidance.id
  }

  /// Reads existing state only: never adopts an owner, refreshes capture, starts
  /// timers or loads content. A revoked owner's counters are not exportable.
  func diagnosticSnapshot() -> SupervisorDiagnosticSnapshot {
    let time = monotonicNow()
    let authorized = owner.map { ownerIsCurrent($0) && currentOwner() == $0 } ?? false
    let exposesSession = owner == nil || authorized
    var snapshot = SupervisorDiagnosticSnapshot()
    snapshot.sessionID = exposesSession ? sessionID : nil
    snapshot.sampledUptimeMs = Int(max(0, time) * 1_000)
    snapshot.monitoringEnabled = enabled
    snapshot.suspended = suspended
    snapshot.ownerAuthorized = authorized
    snapshot.state = state.rawValue
    snapshot.evaluationSlotOccupied = evaluationID != nil
    guard exposesSession else { return snapshot }
    snapshot.metrics = metrics
    snapshot.currentWork = metrics.currentWork
    snapshot.pendingChangedObservation = dirty
    snapshot.nextDueInMs = nextEvaluationAt.map { Int(max(0, $0 - time) * 1_000) }
    snapshot.budgetTokens = min(3, budgetTokens + max(0, time - budgetRefilledAt) / 5)
    if let pauseOwner, currentOwner() == pauseOwner, ownerIsCurrent(pauseOwner) {
      snapshot.retryReason = diagnosticRetryReason
      snapshot.retryRemainingMs = Int(max(0, pauseUntil - time) * 1_000)
    }
    guard authorized, isObservationAllowed else {
      let status = suspended ? "suspended" : enabled ? "unavailable" : "disabled"
      snapshot.inputs = .init(
        screen: .init(status: status), webcam: .init(status: status),
        microphone: .init(status: status), system: .init(status: status))
      return snapshot
    }
    func imageStatus(_ status: SupervisorInputAvailability, capturedAt: TimeInterval?, freshness: TimeInterval)
      -> SupervisorDiagnosticSnapshot.Input
    {
      guard let capturedAt else { return .init(status: status == .available ? "unavailable" : status.rawValue) }
      let age = max(0, time - capturedAt)
      return .init(status: age <= freshness ? status.rawValue : "stale", ageMs: Int(min(86_400_000, age * 1_000)))
    }
    snapshot.inputs.screen = imageStatus(inputStatuses.screen.status, capturedAt: frameCapturedUptime, freshness: 30)
    snapshot.inputs.webcam = imageStatus(inputStatuses.webcam.status, capturedAt: webcam?.uptime, freshness: 5)
    let audio = audioAvailability()
    snapshot.inputs.microphone = .init(status: audio.0.rawValue)
    snapshot.inputs.system = .init(status: audio.1.rawValue)
    return snapshot
  }

  func evaluatePendingObservation() async {
    guard enabled else {
      metrics.skip(.disabled)
      return
    }
    guard !suspended else {
      metrics.skip(.suspended)
      return
    }
    guard let due = nextEvaluationAt else {
      metrics.skip(.noPending)
      return
    }
    guard monotonicNow() >= due else {
      metrics.skip(.notDue)
      return
    }
    guard evaluationID == nil else {
      metrics.skip(.inFlight)
      return
    }
    guard monotonicNow() >= pauseUntil else {
      metrics.skip(.retryPause)
      return
    }
    guard let owner else {
      metrics.skip(.noOwner)
      return
    }
    guard ownerIsCurrent(owner) else { return }
    refillBudget()
    guard budgetTokens >= 1 else {
      metrics.budgetDeferrals += 1
      metrics.skip(.budget)
      schedule()
      return
    }
    budgetTokens -= 1
    let token = UUID()
    evaluationID = token
    dirty = false
    let admittedAt = now()
    let admittedUptime = monotonicNow()
    let diagnosticReceipt = metrics.admit(queuedAt: firstPendingAt ?? due, at: admittedUptime)
    firstPendingAt = nil
    lastAdmissionAt = admittedUptime
    state = .evaluating
    pauseOwner = nil
    pauseUntil = 0
    retryAt = nil
    diagnosticRetryReason = nil
    let session = sessionID
    let epoch = contextEpoch
    let observationEpoch = relevantObservationEpoch
    let expires = admittedAt.addingTimeInterval(30)
    let observedFrame = frame
    let observedFrameUptime = frameCapturedUptime
    let observedWebcam = webcam
    let observedRevision = contentRevision
    let observedConversation = activeConversation
    var statuses = inputStatuses
    _ = pruneAmbient()
    let transcriptSnapshot = transcripts
    let conversationSnapshot = conversation
    defer {
      if sessionID == session, ownerIsCurrent(owner) {
        metrics.finish(diagnosticReceipt, at: monotonicNow(), outcome: .discardedBeforeEvaluation)
      }
      if evaluationID == token {
        evaluationID = nil
        if state == .evaluating { state = .observing }
        schedule()
      }
    }
    let memory = await loadMemory(owner)
    guard isObservationAllowed, ownerIsCurrent(owner), sessionID == session, contextEpoch == epoch,
      relevantObservationEpoch == observationEpoch,
      now() < expires, !Task.isCancelled
    else {
      if sessionID == session, ownerIsCurrent(owner) { metrics.skip(.invalidatedObservation) }
      return
    }
    if let observedFrame, SupervisorScreenPolicy.isAppExcluded(observedFrame.appName) {
      metrics.skip(.excludedInput)
      screenUnavailable()
      return
    }
    let screen: SupervisorScreenInput? = observedFrame.flatMap { captured in
      let age = max(0, monotonicNow() - (observedFrameUptime ?? admittedUptime))
      statuses.screen = .init(
        status: age <= 30 ? .available : .stale,
        capturedAt: ISO8601DateFormatter().string(from: captured.captureTime), ageMs: min(86_400_000, Int(age * 1_000)))
      guard age <= 30 else { return nil }
      let data = SuggestionFramePreview.downscaledJPEG(from: captured.jpegData)
      guard data.count <= 2_000_000, data.starts(with: [0xFF, 0xD8, 0xFF]) else { return nil }
      return .init(
        jpegBase64: data.base64EncodedString(), appName: String(captured.appName.prefix(256)),
        windowTitle: captured.windowTitle.map { String($0.prefix(512)) },
        capturedAt: ISO8601DateFormatter().string(from: captured.captureTime))
    }
    let webcamInput: SupervisorWebcamInput? = observedWebcam.flatMap { captured in
      let age = max(0, monotonicNow() - captured.uptime)
      statuses.webcam = .init(
        status: age <= 5 ? .available : .stale,
        capturedAt: ISO8601DateFormatter().string(from: captured.capturedAt), ageMs: min(86_400_000, Int(age * 1_000)))
      guard age <= 5 else { return nil }
      return .init(
        jpegBase64: captured.data.base64EncodedString(),
        capturedAt: ISO8601DateFormatter().string(from: captured.capturedAt))
    }
    (statuses.microphone.status, statuses.system.status) = audioAvailability()
    let request = SupervisorEvaluationRequest(
      observationID: UUID().uuidString.lowercased(), sessionID: session, contextEpoch: epoch,
      screen: screen, transcripts: transcriptSnapshot, conversation: conversationSnapshot,
      memories: Array(memory.memories.prefix(20)).map { String($0.prefix(1_000)) },
      profile: String(memory.profile.prefix(8_000)), evaluationSharing: evaluationSharing,
      observedAt: ISO8601DateFormatter().string(from: admittedAt), contentRevision: observedRevision,
      webcam: webcamInput, inputStatus: statuses, activeConversation: observedConversation)
    do {
      decisionStarted(request.observationID)
      metrics.startEvaluator(diagnosticReceipt, at: monotonicNow())
      let response = try await evaluate(request, owner)
      if sessionID == session, ownerIsCurrent(owner) {
        metrics.finish(diagnosticReceipt, at: monotonicNow(), outcome: .returned)
      }
      if let observedFrame, SupervisorScreenPolicy.isAppExcluded(observedFrame.appName) {
        if sessionID == session, ownerIsCurrent(owner) { metrics.skip(.excludedInput) }
        screenUnavailable()
        return
      }
      guard isObservationAllowed, ownerIsCurrent(owner), sessionID == session, contextEpoch == epoch,
        relevantObservationEpoch == observationEpoch,
        now() < expires, !Task.isCancelled,
        response.observationID == request.observationID,
        response.sessionID == session, response.contextEpoch == epoch
      else {
        if sessionID == session, ownerIsCurrent(owner) { metrics.skip(.rejectedResponse) }
        return
      }
      recordDecision(request, response, owner)
      pendingGuidance = nil
      guard response.outcome == "completed", response.action != .wait,
        let note = response.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty
      else { return }
      var guidance = SupervisorGuidance(
        id: response.decisionID, observationID: request.observationID,
        sessionID: session, contextEpoch: epoch, note: String(note.prefix(2_000)),
        expiresAt: expires, authorizationSnapshot: owner, action: response.action)
      guidance.relevantObservationEpoch = observationEpoch
      guidance.context = Self.voiceContext(request)
      pendingGuidance = guidance
      await deliver(guidance)
    } catch {
      guard sessionID == session, ownerIsCurrent(owner), evaluationID == token else { return }
      metrics.finish(diagnosticReceipt, at: monotonicNow(), outcome: error is CancellationError ? .cancelled : .failed)
      state = .paused
      var retrySeconds: TimeInterval = 60
      diagnosticRetryReason = .evaluatorFailure
      if case SupervisorRequestError.rateLimited(let reason, let seconds) = error {
        retrySeconds = TimeInterval(max(1, seconds))
        diagnosticRetryReason =
          reason == "daily_quota" ? .dailyQuota : reason == "burst_quota" ? .burstQuota : .evaluatorFailure
      }
      pauseOwner = owner
      pauseUntil = monotonicNow() + retrySeconds
      retryAt = now().addingTimeInterval(retrySeconds)
    }
  }

  /// Current permitted observations for A's next accepted user turn. This
  /// contains no supervisor note and never starts a capture or storage query.
  func currentVoiceContext(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) -> String {
    guard isObservationAllowed, let owner, ownerIsCurrent(owner),
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
