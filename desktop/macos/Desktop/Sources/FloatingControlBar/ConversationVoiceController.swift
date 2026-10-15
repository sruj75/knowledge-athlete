import Foundation
import VoiceTurnDomain

enum SupervisorGuidanceDeliveryResult: Equatable {
  case accepted, deferred, rejected, failed
}

/// Owns one open conversation across many user utterances, Live connections,
/// and the permanent-for-this-conversation batch fallback. VoiceTurnCoordinator
/// remains the sole owner of per-answer output leases and terminal fences.
@MainActor
final class ConversationVoiceController {
  static let shared = ConversationVoiceController()
  private struct Turn {
    let id: VoiceTurnID
    let responseID: VoiceResponseID
    var sessionID: VoiceSessionID?
    let activity: UInt64
    var revision: Int = 0
    var observationAdmission: SupervisorVoiceObservationAdmission?
    var decisionID: String?
    var attachments: [ChatAttachment] = []
    var image: ConversationImage?
    var onJournalFinalized: (@MainActor @Sendable (Bool) -> Void)?
    let journal: ConversationJournalContext
    let origin: String
    let createdAt = Date()
    var continuityID: String?
    var journalID: String { continuityID ?? id.description }
    var userText = ""
    var assistantText = ""
    var audio: Data?
    var lease: VoiceOutputLease?
    var outputAdmission = ConversationOutputAdmission()
    var outputAdmissionRequested = false
    var outputPlayed = false
    var outputRendered = false
    var outputDrained = false
    var physicalEndedAt: TimeInterval?
    var providerBound = false
    var providerFinished = false
    var journalStarted = false
    var transcriptionRepairPending = false
  }
  private let coordinator = VoiceTurnCoordinator.shared
  private let audio = ConversationDuplexAudio()
  private let detector = ConversationSpeechDetector()
  private let renderer = ConversationSpeechRenderer()
  private var diagnostics = ConversationDiagnosticLedger<RuntimeOwnerAuthorizationSnapshot>()
  private(set) var lifecycle = ConversationLifecycle() {
    didSet {
      SupervisorService.shared.updateConversation(
        id: lifecycle.id,
        state: SupervisorConversationState(rawValue: lifecycle.state.rawValue) ?? .closed)
      publishConversationPresentation()
    }
  }
  var isOpen: Bool { lifecycle.isOpen }
  var currentConversationID: String? { lifecycle.id }
  var conversationState: ConversationLifecycle.State { lifecycle.state }
  private var barState: FloatingControlBarState?
  private var context: ConversationJournalContext?
  private var prompt: ConversationPromptReceipt?
  private var history: [ConversationHistoryMessage] = []
  private var savedContext = ""
  private var current: Turn? {
    didSet {
      publishConversationPresentation()
      if let current, oldValue?.id != current.id {
        diagnostics.beginTurn(
          id: current.id.description, owner: RuntimeOwnerIdentity.captureAuthorizationSnapshot(),
          generation: lifecycle.generation)
      }
    }
  }
  private var microphoneAvailable = false { didSet { publishConversationPresentation() } }
  private var actualOutputActive = false { didSet { publishConversationPresentation() } }
  private var playbackPresentationGeneration: UInt64 = 0
  private var meterReceipt: AudioLevelMonitor.ConversationReceipt?
  private var session: ConversationLiveSession?
  private var liveReady = false
  private var sessionID = VoiceSessionID()
  private var reconnectAttempts = 0
  private var resumeHandle: String?
  private var pendingAudio = ConversationPendingAudio()
  private var pendingGuidance: SupervisorGuidance?
  private var appliedDecisionID: String?
  private var proactiveOpening: SupervisorGuidance?
  private var openingSent = false
  private var userSpeaking = false { didSet { publishConversationPresentation() } }
  private var setupTask: Task<Void, Never>?
  private var responseTask: Task<Void, Never>?
  private var transcriptionRepairTask: Task<Void, Never>?
  private var connectionDeadline: Task<Void, Never>?
  private var silenceTask: Task<Void, Never>?
  private var ownerObserver: NSObjectProtocol?
  private var finishing = false
  private var journalTail: Task<Bool, Never>?
  private let textLease = ConversationTextTurnLease()
  private var textObservationAdmission: SupervisorVoiceObservationAdmission?
  private var textAuthorization: RuntimeOwnerAuthorizationSnapshot?
  private var textConversationAuthorization: RuntimeOwnerAuthorizationSnapshot?
  private var textCloseRequested = false
  private var cancelTextRequest: (@MainActor @Sendable () -> Void)?
  private let pendingVoiceOpen = ConversationOpeningRequest()
  private var typedReply:
    (
      id: VoiceTurnID, continuation: CheckedContinuation<String?, Never>,
      delta: @MainActor @Sendable (String) -> Void
    )?
  private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
  private var provider: ChatProvider? { FloatingControlBarManager.shared.sharedFloatingProvider }

  func setup(barState: FloatingControlBarState) {
    self.barState = barState
    coordinator.configure(barState: barState)
    publishConversationPresentation()
    coordinator.setEffectHandler { [weak self] effect in self?.handle(effect) }
    if ownerObserver == nil {
      ownerObserver = NotificationCenter.default.addObserver(
        forName: .runtimeOwnerDidChange, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.close()
          self?.diagnostics.reset()
        }
      }
    }
  }

  /// Read-only acceptance metadata. This never starts capture, inference, or
  /// playback. The physical input counters include silence, not just speech.
  func diagnosticSnapshot() -> ConversationDiagnosticSnapshot? {
    guard AppBuild.isNonProduction else { return nil }
    let owner = RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    if let id = lifecycle.id {
      diagnostics.updateMetadata(
        logicalID: id, journalID: context?.conversationID,
        connectionID: session == nil ? nil : sessionID.description,
        prompt: prompt.map { .init(name: $0.name, version: $0.version, source: $0.source, sha256: $0.sha256) },
        owner: owner, generation: lifecycle.generation)
      let presentation = ConversationPresentation.resolve(
        state: lifecycle.state, microphoneOpen: microphoneAvailable, userSpeaking: userSpeaking,
        replyPending: current != nil && current?.journalStarted == false, playbackActive: actualOutputActive)
      diagnostics.updateRuntime(
        state: lifecycle.state.rawValue, route: lifecycle.route == .live ? "live" : "batch",
        microphoneAvailable: microphoneAvailable, userSpeaking: userSpeaking,
        listening: presentation.phase == .listening, rendering: actualOutputActive,
        owner: owner, generation: lifecycle.generation)
    }
    return diagnostics.snapshot(owner: owner)
  }

  func toggle() {
    if pendingVoiceOpen.cancel() { return }
    if isOpen { close() } else { open() }
  }

  func quiesce() async {
    close()
    cancelTextRequest?()
    await textLease.waitUntilReleased()
    await audio.stopAndWait()
  }

  func beginTextOnlyTurn(
    conversationID: String? = nil, turnID: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    cancel: @escaping @MainActor @Sendable () -> Void
  ) -> Bool {
    guard !isOpen, RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot),
      textLease.begin(turnID: turnID, conversationID: conversationID)
    else { return false }
    textAuthorization = authorizationSnapshot
    textConversationAuthorization = authorizationSnapshot
    textObservationAdmission = SupervisorService.shared.captureVoiceObservationAdmission()
    textCloseRequested = false
    cancelTextRequest = cancel
    SupervisorService.shared.updateConversation(id: textLease.conversationID ?? turnID, state: .connecting)
    return true
  }

  func bindTextOnlyConversation(turnID: String, conversationID: String) {
    guard textLease.bind(turnID: turnID, conversationID: conversationID) else { return }
    SupervisorService.shared.updateConversation(id: conversationID, state: .open)
  }

  func observeTextOnlyTurn(
    turnID: String, userText: String, assistantText: String, outcome: String, isFinal: Bool = false
  ) {
    guard let authorization = textAuthorization,
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorization),
      let admission = textObservationAdmission,
      let revision = textLease.nextRevision(turnID: turnID)
    else { return }
    SupervisorService.shared.observeVoice(
      userText: userText, assistantText: assistantText,
      turnID: turnID, outcome: outcome, admission: admission,
      revision: revision, isFinal: isFinal)
  }

  func finishTextOnlyTurn(turnID: String, conversationEnded: Bool = false) {
    guard textLease.finish(turnID: turnID) else { return }
    textAuthorization = nil
    textObservationAdmission = nil
    cancelTextRequest = nil
    if conversationEnded || textCloseRequested {
      if let id = textLease.conversationID { provider?.endPinnedConversation(id: id) }
      textLease.endConversation()
      textConversationAuthorization = nil
    }
    SupervisorService.shared.updateConversation(
      id: textLease.conversationID,
      state: textLease.hasConversation ? .open : .closed)
  }

  /// Cancels only the answer; the microphone and logical conversation remain open.
  func interruptReply() {
    finishCurrent(delivery: .interrupted)
  }

  func takeTextOnlyGuidance(turnID: String) -> SupervisorGuidance? {
    guard textLease.turnID == turnID,
      let authorization = textAuthorization,
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
    else { return nil }
    return takeGuidance()
  }

  var activeJournalSurface: AgentSurfaceReference? { context?.surface }

  func acceptsTypedInput(surface: AgentSurfaceReference) -> Bool {
    isOpen && context?.surface.externalRefKind == surface.externalRefKind
      && context?.surface.externalRefId == surface.externalRefId
  }

  func submitTypedMessage(
    text: String, clientTurnID: String? = nil, image: ConversationImage? = nil, attachments: [ChatAttachment] = [],
    onJournalFinalized: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
    onAccepted: @escaping @MainActor @Sendable () -> Void = {},
    onTextDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws -> String? {
    guard lifecycle.state == .open, let context, let prompt, let conversationID = lifecycle.id,
      RuntimeOwnerIdentity.isAuthorizationCurrent(context.authorizationSnapshot)
    else { throw ConversationJournalError.unavailable }
    let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12_000))
    guard !text.isEmpty else { return nil }
    finishCurrent(delivery: .interrupted)
    userSpeaking = false
    let activity = lifecycle.userBeganSpeaking(now: now)
    let id = coordinator.begin(intent: .conversation, ownerID: context.authorizationSnapshot.ownerID)
    let useLive = lifecycle.route == .live && liveReady && session != nil
    current = Turn(
      id: id, responseID: VoiceResponseID(UUID().uuidString), sessionID: useLive ? sessionID : nil,
      activity: activity, journal: context, origin: "chat", userText: text)
    current?.observationAdmission = SupervisorService.shared.captureVoiceObservationAdmission()
    current?.decisionID = appliedDecisionID
    current?.continuityID = clientTurnID
    current?.attachments = attachments
    current?.image = image
    current?.onJournalFinalized = onJournalFinalized
    if useLive {
      coordinator.publish(.selectRoute(turnID: id, route: .hub(sessionID: sessionID)))
      bindLiveResponse()
    } else {
      coordinator.publish(.selectRoute(turnID: id, route: .managedBatch))
      coordinator.publish(.transcriptionFinal(turnID: id, text: text))
      current?.providerBound = true
    }
    let generation = lifecycle.generation
    guard let turn = current, await queueJournal(turn, delivery: .notSpoken, isFinal: false).value,
      accepts(generation, owner: context.authorizationSnapshot), current?.id == id
    else {
      finishCurrent(delivery: .failed)
      throw ConversationJournalError.writeRejected
    }
    _ = current?.outputAdmission.accept()
    onAccepted()
    barState?.displayedQuery = text
    if useLive, let session {
      return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          typedReply = (id, continuation, onTextDelta)
          session.sendUserMessage(text, imageJPEGBase64: image?.jpegBase64, turnID: id.description)
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          guard self?.current?.id == id else { return }
          self?.finishCurrent(delivery: .interrupted)
        }
      }
    }
    let task = Task { [weak self] () -> String? in
      guard let self else { return nil }
      do {
        return try await self.respondDirect(
          message: text, turnID: id, generation: generation,
          prompt: prompt, conversationID: conversationID, image: image, onTextDelta: onTextDelta)
      } catch {
        guard self.current?.id == id else { return nil }
        self.finishCurrent(delivery: .failed)
        return nil
      }
    }
    responseTask = Task {
      await withTaskCancellationHandler {
        _ = await task.value
      } onCancel: {
        task.cancel()
      }
    }
    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func respondDirect(
    message: String, turnID: VoiceTurnID, generation: UInt64,
    prompt: ConversationPromptReceipt, conversationID: String, image: ConversationImage?,
    acceptedGuidance: SupervisorGuidance? = nil,
    onTextDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws -> String? {
    guard let turn = current, turn.id == turnID else { return nil }
    lifecycle.setBusy(true, now: now)
    guard await queueJournal(turn, delivery: .notSpoken, isFinal: false).value,
      current?.id == turnID, accepts(generation, owner: turn.journal.authorizationSnapshot), !Task.isCancelled
    else { throw ConversationJournalError.writeRejected }
    _ = current?.outputAdmission.accept()
    if let acceptedGuidance, !SupervisorService.shared.isAcceptedGuidanceAllowed(acceptedGuidance) {
      throw ConversationJournalError.unavailable
    }
    let guidance = acceptedGuidance ?? takeGuidance()
    current?.decisionID = guidance?.id ?? appliedDecisionID
    let request = ConversationResponseRequest(
      conversationID: conversationID, turnID: turnID.description,
      promptReference: prompt.reference, history: boundedHistory(), message: String(message.prefix(12_000)),
      context: String(
        (savedContext + "\n"
          + SupervisorService.shared.currentVoiceContext(
            authorizationSnapshot: turn.journal.authorizationSnapshot)).prefix(16_000)),
      guidance: guidance.map { String(Self.privateContext($0).prefix(2_000)) }, image: image)
    let completion = try await APIClient.shared.respondToConversation(
      request: request,
      authorizationSnapshot: turn.journal.authorizationSnapshot
    ) { [weak self] delta in
      guard let self, self.current?.id == turnID,
        self.accepts(generation, owner: turn.journal.authorizationSnapshot)
      else { return }
      self.providerStarted()
      self.current?.assistantText += delta
      self.publishPreview(onAccepted: { onTextDelta(delta) })
      self.observeCurrent(outcome: "partial")
    }
    guard current?.id == turnID, !Task.isCancelled,
      accepts(generation, owner: turn.journal.authorizationSnapshot)
    else { return nil }
    if completion.endConversation { lifecycle.requestEnd(afterActivity: turn.activity) }
    let answer = current?.assistantText ?? ""
    if answer.isEmpty {
      finishProvider()
      return answer
    }
    beginOutputIfNeeded()
    await renderer.render(
      answer, authorizationSnapshot: turn.journal.authorizationSnapshot,
      audio: { [weak self] pcm in
        guard self?.current?.id == turnID else { return }
        self?.enqueueAudio(pcm)
      },
      completed: { [weak self] successful in
        guard let self, self.current?.id == turnID else { return }
        if successful {
          self.finishProvider()
        } else {
          self.finishCurrent(delivery: .failed)
        }
      })
    return answer
  }

  func open(guidance: SupervisorGuidance? = nil) {
    if textLease.isActive {
      guard guidance == nil else { return }
      cancelTextRequest?()
      pendingVoiceOpen.schedule(
        wait: { [weak self] in
          await self?.textLease.waitUntilReleased()
        }, open: { [weak self] in self?.open() })
      return
    }
    guard !isOpen, let provider,
      let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    else { return }
    textLease.endConversation()
    textConversationAuthorization = nil
    lifecycle.open(id: UUID().uuidString, now: now)
    let generation = lifecycle.generation
    if AppBuild.isNonProduction, let id = lifecycle.id {
      diagnostics.begin(owner: authorization, generation: generation, conversationID: id)
    }
    proactiveOpening = guidance
    openingSent = false
    reconnectAttempts = 0
    resumeHandle = nil
    history = []
    savedContext = ""
    guard
      FloatingControlBarManager.shared.presentConversationOpening(
        request: guidance == nil ? .explicitUserAction : .background)
    else {
      close(dismissUI: false)
      return
    }
    let meterReceipt = AudioLevelMonitor.shared.beginConversationMeter()
    self.meterReceipt = meterReceipt
    barState?.isAILoading = true
    setupTask = Task { [weak self] in
      guard let self else { return }
      do {
        guard await AudioCaptureService.requestPermission() else {
          self.failOpening(generation: generation, message: "Microphone access is needed to talk.")
          return
        }
        guard self.accepts(generation, owner: authorization) else { return }
        let context = try await provider.snapshotConversationJournal()
        guard context.authorizationSnapshot == authorization,
          self.accepts(generation, owner: authorization)
        else { return }
        self.context = context
        self.history = context.history
        let binding = try await provider.pinnedConversation(context: context)
        guard self.accepts(generation, owner: context.authorizationSnapshot) else { return }
        self.lifecycle.bind(id: binding.id)
        self.prompt = binding.prompt
        self.savedContext = await provider.conversationContextText(authorizationSnapshot: context.authorizationSnapshot)
        guard self.accepts(generation, owner: context.authorizationSnapshot) else { return }
        guard await self.detector.start() else {
          self.failOpening(
            generation: generation, message: "Speech detection is unavailable. Please reopen the conversation.")
          return
        }
        guard self.accepts(generation, owner: context.authorizationSnapshot) else { return }
        try await self.audio.start(
          input: { [weak self] data in
            DispatchQueue.main.async { self?.receiveMicrophone(data, generation: generation) }
          },
          microphoneLevel: { [weak self] level in
            guard let self, self.accepts(generation, owner: authorization) else { return }
            AudioLevelMonitor.shared.updateConversationMicrophoneLevel(level, receipt: meterReceipt)
          },
          playbackLevel: { [weak self] level in
            guard let self, self.accepts(generation, owner: authorization) else { return }
            AudioLevelMonitor.shared.updateConversationPlaybackLevel(level, receipt: meterReceipt)
          },
          failure: { [weak self] in
            Task { @MainActor in
              guard let self, self.lifecycle.generation == generation else { return }
              self.failOpening(
                generation: generation, message: "The audio device changed. Reopen the conversation to reconnect it.")
            }
          })
        guard self.accepts(generation, owner: context.authorizationSnapshot) else {
          self.audio.stop()
          return
        }
        self.microphoneAvailable = true
        self.startSilenceClock(generation: generation)
        await self.connect(generation: generation)
      } catch {
        self.failOpening(generation: generation, message: "Could not start the conversation. Please try again.")
      }
    }
  }

  func close(dismissUI: Bool = true) {
    pendingVoiceOpen.cancel()
    guard lifecycle.state != .closed else {
      textCloseRequested = true
      cancelTextRequest?()
      if !textLease.isActive {
        if let id = textLease.conversationID { provider?.endPinnedConversation(id: id) }
        textLease.endConversation()
        textConversationAuthorization = nil
        SupervisorService.shared.updateConversation(id: nil, state: .closed)
      }
      return
    }
    finishCurrent(delivery: .interrupted)
    textLease.endConversation()
    textConversationAuthorization = nil
    if let context {
      provider?.endPinnedConversation(context: context)
    } else if let id = lifecycle.id {
      provider?.endPinnedConversation(id: id)
    }
    _ = diagnosticSnapshot()
    diagnostics.close(owner: RuntimeOwnerIdentity.captureAuthorizationSnapshot(), generation: lifecycle.generation)
    lifecycle.close()
    setupTask?.cancel()
    responseTask?.cancel()
    connectionDeadline?.cancel()
    silenceTask?.cancel()
    renderer.cancel()
    session?.stop()
    session = nil
    liveReady = false
    audio.stop()
    detector.stop()
    pendingAudio.reset()
    pendingGuidance = nil
    appliedDecisionID = nil
    proactiveOpening = nil
    prompt = nil
    context = nil
    history.removeAll()
    savedContext = ""
    userSpeaking = false
    barState?.isAILoading = false
    microphoneAvailable = false
    actualOutputActive = false
    if let meterReceipt { AudioLevelMonitor.shared.endConversationMeter(receipt: meterReceipt) }
    meterReceipt = nil
    if dismissUI { FloatingControlBarManager.shared.window?.closeAIConversation() }
  }

  func submitSupervisorGuidance(_ guidance: SupervisorGuidance) async -> SupervisorGuidanceDeliveryResult {
    guard SupervisorService.shared.isCurrent(guidance) else { return .rejected }
    if guidance.action == .wait { return .accepted }
    if textLease.hasConversation {
      guard textConversationAuthorization == guidance.authorizationSnapshot else { return .rejected }
      pendingGuidance = guidance
      return .deferred
    }
    if isOpen {
      guard context?.authorizationSnapshot == guidance.authorizationSnapshot else { return .rejected }
      pendingGuidance = guidance
      await deliverGuidanceIfIdle()
      return pendingGuidance == nil ? .accepted : .deferred
    }
    guard guidance.action == .intervene else {
      pendingGuidance = guidance
      return .deferred
    }
    guard NotificationService.shared.claimSupervisorSpeech(authorizationSnapshot: guidance.authorizationSnapshot) else {
      return .rejected
    }
    open(guidance: guidance)
    return isOpen ? .accepted : .failed
  }

  private func accepts(_ generation: UInt64, owner: RuntimeOwnerAuthorizationSnapshot) -> Bool {
    isOpen && lifecycle.generation == generation && RuntimeOwnerIdentity.isAuthorizationCurrent(owner)
  }

  private func connect(generation: UInt64) async {
    guard let context, let prompt, let id = lifecycle.id,
      accepts(generation, owner: context.authorizationSnapshot)
    else { return }
    do {
      let credential = try await APIClient.shared.mintConversationLiveSession(
        conversationID: id, prompt: prompt, authorizationSnapshot: context.authorizationSnapshot)
      guard accepts(generation, owner: context.authorizationSnapshot), lifecycle.route == .live, !Task.isCancelled
      else { return }
      sessionID = VoiceSessionID()
      let connection = ConversationLiveSession(
        token: credential.token, instructions: prompt.text, resumeHandle: resumeHandle
      ) { [weak self] source, event in self?.receive(event, from: source, generation: generation) }
      session = connection
      _ = diagnosticSnapshot()
      liveReady = false
      connection.start()
      connectionDeadline?.cancel()
      connectionDeadline = Task { [weak self, weak connection] in
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled, let self, let connection, self.session === connection,
          !self.liveReady
        else { return }
        self.liveFailed(connection, generation: generation)
      }
    } catch {
      guard accepts(generation, owner: context.authorizationSnapshot), lifecycle.route == .live, !Task.isCancelled
      else { return }
      await recover(generation: generation)
    }
  }

  private func recover(generation: UInt64) async {
    guard isOpen, lifecycle.generation == generation else { return }
    if reconnectAttempts < 1 {
      reconnectAttempts += 1
      lifecycle.reconnect(now: now)
      await connect(generation: generation)
    } else {
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "realtime_hub", from: "gemini_live",
        to: "managed_conversation_batch", reason: "other", outcome: .degraded)
      lifecycle.useFallback(now: now)
      barState?.isAILoading = false
      if let current, current.origin == "chat", !current.userText.isEmpty,
        current.assistantText.isEmpty, !current.outputPlayed
      {
        beginTypedFallback(turn: current)
      } else if let current, let pcm = current.audio, current.assistantText.isEmpty, !current.outputPlayed {
        beginBatchResponse(pcm, turnID: current.id)
      } else if let current, userSpeaking, current.assistantText.isEmpty {
        self.current?.sessionID = nil
        self.current?.providerBound = false
        coordinator.publish(.selectRoute(turnID: current.id, route: .managedBatch))
      } else if current != nil {
        finishCurrent(delivery: .failed)
      }
      // Do not replay an opening that may already have reached Live.
      if openingSent { proactiveOpening = nil } else if current == nil { startProactiveOpeningIfNeeded() }
      updateListening()
    }
  }

  private func liveFailed(_ source: ConversationLiveSession, generation: UInt64) {
    guard session === source, lifecycle.generation == generation else { return }
    source.stop()
    session = nil
    liveReady = false
    connectionDeadline?.cancel()
    // An unanswered in-flight utterance has local PCM available for STT. A
    // socket replay would be ambiguous; move that same utterance to fallback.
    if current != nil, current?.assistantText.isEmpty == true, current?.outputPlayed == false {
      reconnectAttempts = 1
    }
    if current?.assistantText.isEmpty == false || current?.outputPlayed == true {
      finishCurrent(delivery: .failed)
    }
    setupTask = Task { [weak self] in await self?.recover(generation: generation) }
  }

  private func receiveMicrophone(_ data: Data, generation: UInt64) {
    guard let context, accepts(generation, owner: context.authorizationSnapshot) else { return }
    // This private entrypoint is fed only by the duplex engine's processed tap.
    // Synthetic presentation previews never enter this path.
    diagnostics.recordProcessedPCM(
      byteCount: data.count, owner: context.authorizationSnapshot, generation: generation)
    if lifecycle.route == .live {
      if liveReady {
        session?.sendAudio(data)
      } else if !pendingAudio.append(data) {
        // The segmenter still owns the complete bounded utterance. Do not send
        // a truncated Live prefix when token minting or connection setup stalls.
        session?.stop()
        session = nil
        setupTask?.cancel()
        connectionDeadline?.cancel()
        reconnectAttempts = 1
        lifecycle.useFallback(now: now)
        DesktopDiagnosticsManager.shared.recordFallback(
          area: "realtime_hub", from: "gemini_live", to: "managed_conversation_batch",
          reason: "other", outcome: .degraded)
        if let turn = current, let pcm = turn.audio, !userSpeaking {
          beginBatchResponse(pcm, turnID: turn.id)
        }
        if current == nil { startProactiveOpeningIfNeeded() }
        updateListening()
      }
    }
    detector.consume(data) { [weak self] events in
      DispatchQueue.main.async {
        guard let self, self.accepts(generation, owner: context.authorizationSnapshot) else { return }
        for event in events {
          switch event {
          case .began: self.userBeganSpeaking()
          case .ended(let pcm): self.userStoppedSpeaking(pcm)
          }
        }
      }
    }
  }

  private func userBeganSpeaking() {
    guard isOpen, !userSpeaking, let context else { return }
    userSpeaking = true
    let interruptedNativeAnswer = current?.sessionID != nil && current?.journalStarted == false
    finishCurrent(delivery: .interrupted)
    renderer.cancel()
    responseTask?.cancel()
    stopPlayback()
    let activity = lifecycle.userBeganSpeaking(now: now)
    let id = coordinator.begin(intent: .conversation, ownerID: context.authorizationSnapshot.ownerID)
    guard coordinator.activeTurnID == id else {
      close()
      return
    }
    current = Turn(
      id: id, responseID: VoiceResponseID(UUID().uuidString),
      sessionID: lifecycle.route == .live ? sessionID : nil, activity: activity,
      journal: context, origin: "voice")
    current?.observationAdmission = SupervisorService.shared.captureVoiceObservationAdmission()
    current?.decisionID = appliedDecisionID
    current?.transcriptionRepairPending = interruptedNativeAnswer && lifecycle.route == .live
    coordinator.publish(
      .selectRoute(
        turnID: id,
        route: lifecycle.route == .live ? .hub(sessionID: sessionID) : .managedBatch))
    if liveReady { session?.beginUserTurn(id.description) }
    barState?.displayedQuery = ""
    barState?.setLocalAnswerOverride(nil)
    barState?.isAILoading = false
  }

  private func userStoppedSpeaking(_ pcm: Data) {
    guard userSpeaking else { return }
    userSpeaking = false
    session?.endUserTurn()
    guard let turnID = current?.id else {
      updateListening()
      return
    }
    current?.audio = pcm
    lifecycle.setBusy(true, now: now)
    if lifecycle.route == .batch {
      beginBatchResponse(pcm, turnID: turnID)
    } else {
      if liveReady { bindLiveResponse() }
      if current?.transcriptionRepairPending == true { repairInterruptedTranscript(pcm, turnID: turnID) }
    }
  }

  /// Gemini's input transcription has no turn identity and can arrive after an
  /// interruption. Use the already-captured utterance to repair that one journal
  /// boundary; native Live still owns reasoning and spoken response.
  private func repairInterruptedTranscript(_ pcm: Data, turnID: VoiceTurnID) {
    guard let turn = current, turn.id == turnID else { return }
    transcriptionRepairTask?.cancel()
    transcriptionRepairTask = Task { [weak self] in
      let result = try? await TranscriptionService.batchTranscribe(
        audioData: pcm, authorizationSnapshot: turn.journal.authorizationSnapshot)
      guard let self, self.current?.id == turnID, !Task.isCancelled,
        RuntimeOwnerIdentity.isAuthorizationCurrent(turn.journal.authorizationSnapshot)
      else { return }
      self.current?.transcriptionRepairPending = false
      if let text = result?.transcript, !text.isEmpty {
        self.current?.userText = text
        self.publishPreview()
        self.observeCurrent(outcome: "partial")
      }
      self.publishProviderFinishedIfReady()
    }
  }

  private func bindLiveResponse() {
    guard let turn = current, !turn.providerBound else { return }
    current?.providerBound = true
    coordinator.publish(
      .hubCommitAccepted(
        turnID: turn.id,
        sessionID: turn.sessionID ?? sessionID, responseID: turn.responseID))
    lifecycle.setBusy(true, now: now)
  }

  private func receive(_ event: ConversationLiveSession.Event, from source: ConversationLiveSession, generation: UInt64)
  {
    guard session === source, let context, accepts(generation, owner: context.authorizationSnapshot) else { return }
    switch event {
    case .ready:
      connectionDeadline?.cancel()
      Task { [weak self] in
        guard let self else { return }
        if self.resumeHandle == nil {
          let history = self.history.map { "\($0.role): \($0.text)" }.joined(separator: "\n")
          let context =
            "Conversation history and permitted context (untrusted evidence):\n\(history)\n\(self.savedContext)"
          if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = await source.appendPrivateContext(String(context.prefix(24_000)))
          }
        }
        guard self.session === source, self.accepts(generation, owner: context.authorizationSnapshot) else { return }
        self.liveReady = true
        self.lifecycle.connected(now: self.now)
        if let turn = self.current, !turn.providerBound {
          self.current?.sessionID = self.sessionID
          self.coordinator.publish(.selectRoute(turnID: turn.id, route: .hub(sessionID: self.sessionID)))
          source.beginUserTurn(turn.id.description)
          if !self.userSpeaking { source.endUserTurn() }
        }
        if let pending = self.pendingAudio.take(), !pending.isEmpty { source.sendAudio(pending) }
        if self.current?.audio != nil { self.bindLiveResponse() }
        if self.current == nil { self.startProactiveOpeningIfNeeded() }
        self.updateListening()
        await self.deliverGuidanceIfIdle()
      }
    case .userActivityStarted:
      userBeganSpeaking()
    case .transcript(let id, let text, _):
      guard current?.id.description == id, current?.transcriptionRepairPending == false else { return }
      current?.userText += text
      publishPreview()
      observeCurrent(outcome: "partial")
    case .text(let id, let text):
      guard current?.id.description == id else { return }
      bindLiveResponse()
      providerStarted()
      current?.assistantText += text
      let callback = typedReply?.id.description == id ? typedReply?.delta : nil
      publishPreview(onAccepted: { callback?(text) })
      observeCurrent(outcome: "partial")
    case .audio(let id, let pcm):
      guard current?.id.description == id else { return }
      bindLiveResponse()
      providerStarted()
      enqueueAudio(pcm)
    case .finished(let id):
      guard current?.id.description == id else { return }
      finishProvider()
    case .interrupted(let id):
      guard current?.id.description == id else { return }
      finishCurrent(delivery: .interrupted)
    case .endRequested(let id):
      guard let turn = current, turn.id.description == id else { return }
      lifecycle.requestEnd(afterActivity: turn.activity)
    case .resumeHandle(let handle): resumeHandle = handle
    case .usage(let usage):
      let authorization = context.authorizationSnapshot
      Task {
        await APIClient.shared.reportRealtimeUsage(
          inputText: usage.inputText, inputAudio: usage.inputAudio,
          inputCached: usage.inputCached, outputText: usage.outputText, outputAudio: usage.outputAudio,
          thinking: usage.thinking, authorizationSnapshot: authorization)
      }
    case .goAway: liveFailed(source, generation: generation)
    case .failed: liveFailed(source, generation: generation)
    }
  }

  private func startProactiveOpeningIfNeeded() {
    guard !openingSent, let guidance = proactiveOpening, let context,
      SupervisorService.shared.isAcceptedGuidanceAllowed(guidance),
      context.authorizationSnapshot == guidance.authorizationSnapshot
    else { return }
    if lifecycle.route == .live, !liveReady { return }
    openingSent = true
    proactiveOpening = nil
    let id = coordinator.begin(intent: .conversation, ownerID: context.authorizationSnapshot.ownerID)
    current = Turn(
      id: id, responseID: VoiceResponseID(UUID().uuidString),
      sessionID: lifecycle.route == .live ? sessionID : nil,
      activity: lifecycle.userActivity, journal: context, origin: "supervisor")
    current?.observationAdmission = SupervisorService.shared.captureVoiceObservationAdmission()
    current?.decisionID = guidance.id
    if lifecycle.route == .live, let session {
      coordinator.publish(.selectRoute(turnID: id, route: .hub(sessionID: sessionID)))
      bindLiveResponse()
      session.initiate(Self.privateContext(guidance), turnID: id.description)
    } else if let prompt, let conversationID = lifecycle.id {
      coordinator.publish(.selectRoute(turnID: id, route: .managedBatch))
      coordinator.publish(.transcriptionFinal(turnID: id, text: ""))
      current?.providerBound = true
      let generation = lifecycle.generation
      responseTask = Task { [weak self] in
        guard let self else { return }
        do {
          _ = try await self.respondDirect(
            message: "Begin the conversation using the supervisor note.",
            turnID: id, generation: generation, prompt: prompt, conversationID: conversationID,
            image: nil, acceptedGuidance: guidance, onTextDelta: { _ in })
        } catch {
          guard self.current?.id == id else { return }
          self.finishCurrent(delivery: .failed)
        }
      }
    }
  }

  private func beginTypedFallback(turn: Turn) {
    guard let prompt, let conversationID = lifecycle.id else {
      finishCurrent(delivery: .failed)
      return
    }
    current?.sessionID = nil
    current?.providerBound = true
    coordinator.publish(.selectRoute(turnID: turn.id, route: .managedBatch))
    coordinator.publish(.transcriptionFinal(turnID: turn.id, text: turn.userText))
    let generation = lifecycle.generation
    let delta = typedReply?.delta
    responseTask = Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await self.respondDirect(
          message: turn.userText, turnID: turn.id, generation: generation,
          prompt: prompt, conversationID: conversationID, image: turn.image,
          onTextDelta: { delta?($0) })
      } catch {
        guard self.current?.id == turn.id else { return }
        self.finishCurrent(delivery: .failed)
      }
    }
  }

  private func beginBatchResponse(_ pcm: Data, turnID: VoiceTurnID) {
    guard let turn = current, turn.id == turnID, let prompt, let id = lifecycle.id else { return }
    let generation = lifecycle.generation
    coordinator.publish(.selectRoute(turnID: turnID, route: .managedBatch))
    current?.providerBound = false
    current?.sessionID = nil
    current?.transcriptionRepairPending = false
    coordinator.publish(.transcriptionStarted(turnID: turnID))
    lifecycle.setBusy(true, now: now)
    responseTask?.cancel()
    responseTask = Task { [weak self] in
      guard let self else { return }
      do {
        let transcription = try await TranscriptionService.batchTranscribe(
          audioData: pcm, authorizationSnapshot: turn.journal.authorizationSnapshot)
        guard self.current?.id == turnID, self.accepts(generation, owner: turn.journal.authorizationSnapshot),
          !Task.isCancelled
        else { return }
        let text = transcription.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
          self.finishCurrent(delivery: .notSpoken)
          return
        }
        self.current?.userText = text
        self.current?.providerBound = true
        self.coordinator.publish(.transcriptionFinal(turnID: turnID, text: text))
        self.publishPreview()
        self.observeCurrent(outcome: "partial")
        _ = try await self.respondDirect(
          message: text, turnID: turnID, generation: generation, prompt: prompt,
          conversationID: id, image: nil, onTextDelta: { _ in })
      } catch {
        guard self.current?.id == turnID, !Task.isCancelled else { return }
        self.finishCurrent(delivery: .failed)
      }
    }
  }

  private func providerStarted() {
    guard let turn = current, let identity = coordinator.activeTurn?.providerEffectIdentity else { return }
    coordinator.publish(
      .providerResponseStartedScoped(
        turnID: turn.id, identity: identity,
        sessionID: turn.sessionID,
        responseID: turn.sessionID == nil ? nil : turn.responseID))
    barState?.isAILoading = false
  }

  private func beginOutputIfNeeded() {
    guard var turn = current, turn.lease == nil else { return }
    let lane: VoiceOutputLane = turn.sessionID == nil ? .selectedVoiceFallback : .nativeRealtime
    guard case .acquired(let lease) = coordinator.acquireOutput(lane, turnID: turn.id) else { return }
    turn.lease = lease
    current = turn
    let turnID = turn.id
    playbackPresentationGeneration &+= 1
    let playbackGeneration = playbackPresentationGeneration
    audio.beginPlayback(
      started: { [weak self] in
        DispatchQueue.main.async {
          guard let self, self.playbackPresentationGeneration == playbackGeneration,
            self.current?.id == turnID, self.current?.lease == lease
          else { return }
          self.current?.outputRendered = true
          self.actualOutputActive = true
        }
      },
      progress: { [weak self] in
        DispatchQueue.main.async {
          guard let self, self.playbackPresentationGeneration == playbackGeneration,
            self.current?.id == turnID, self.current?.lease == lease
          else { return }
          self.current?.outputPlayed = true
          _ = self.coordinator.noteOutputProgress(lease)
        }
      },
      drained: { [weak self] in
        DispatchQueue.main.async {
          guard let self, self.playbackPresentationGeneration == playbackGeneration,
            self.current?.id == turnID, self.current?.lease == lease
          else { return }
          self.clearPlaybackPresentation()
          self.current?.lease = nil
          self.current?.physicalEndedAt = self.now
          self.current?.outputDrained = true
          _ = self.coordinator.releaseOutput(lease)
        }
      })
  }

  private func enqueueAudio(_ pcm: Data) {
    beginOutputIfNeeded()
    guard let turn = current, turn.lease != nil else { return }
    switch current?.outputAdmission.append(pcm) {
    case .ready(let data):
      if let lease = current?.lease { _ = coordinator.noteOutputProgress(lease) }
      audio.enqueue(data)
    case .held:
      ensureOutputAdmission(turnID: turn.id)
    case .rejected:
      failOutputAdmission(turnID: turn.id)
    case nil: break
    }
  }

  private func ensureOutputAdmission(turnID: VoiceTurnID) {
    guard let turn = current, turn.id == turnID, !turn.outputAdmissionRequested else { return }
    current?.outputAdmissionRequested = true
    let write = queueJournal(turn, delivery: .notSpoken, isFinal: false)
    Task { [weak self] in
      let accepted = await write.value
      guard let self, self.current?.id == turnID,
        RuntimeOwnerIdentity.isAuthorizationCurrent(turn.journal.authorizationSnapshot)
      else { return }
      guard accepted, let held = self.current?.outputAdmission.accept() else {
        self.failOutputAdmission(turnID: turnID)
        return
      }
      if !held.isEmpty { self.audio.enqueue(held) }
      if self.current?.providerFinished == true { self.audio.sealPlayback() }
    }
  }

  private func failOutputAdmission(turnID: VoiceTurnID) {
    guard current?.id == turnID else { return }
    current?.outputAdmission.reject()
    finishCurrent(delivery: .failed)
    barState?.replaceLocalAnswerText("Could not save this reply. Please try again.")
    barState?.present(.mainResponse)
  }

  private func finishProvider() {
    guard let turn = current, !turn.providerFinished else { return }
    current?.providerFinished = true
    if turn.lease == nil { current?.physicalEndedAt = now }
    publishProviderFinishedIfReady()
    if current?.lease != nil, current?.outputAdmission.isAccepted == true { audio.sealPlayback() }
    if typedReply?.id == turn.id {
      let pending = journalTail
      Task { [weak self] in
        _ = await pending?.value
        guard let self, self.typedReply?.id == turn.id else { return }
        self.typedReply?.continuation.resume(returning: turn.assistantText)
        self.typedReply = nil
      }
    }
  }

  private func publishProviderFinishedIfReady() {
    guard let turn = current, turn.providerFinished, !turn.transcriptionRepairPending,
      coordinator.activeTurn?.providerFinished == false,
      let identity = coordinator.activeTurn?.providerEffectIdentity
    else { return }
    coordinator.publish(
      .providerTurnFinishedScoped(
        turnID: turn.id, identity: identity,
        sessionID: turn.sessionID, responseID: turn.sessionID == nil ? nil : turn.responseID))
  }

  private func handle(_ effect: VoiceTurnEffect) {
    switch effect {
    case .stopPlayback:
      stopPlayback()
      renderer.cancel()
    case .finalizeJournal(let id, let identity):
      guard current?.id == id else { return }
      persistCurrent(
        delivery: current?.outputPlayed == true ? .completed : .notSpoken,
        acceptance: identity)
    case .terminal(let terminal):
      guard current?.id == terminal.turnID, !finishing else { return }
      if terminal.reason == .success {
        current = nil
        if lifecycle.shouldEndAfterPlayback { close() } else { updateListening() }
      } else {
        finishCurrent(delivery: terminal.reason == .interruptedByBargeIn ? .interrupted : .failed)
      }
    default: break
    }
  }

  private func persistCurrent(delivery: ConversationDeliveryOutcome, acceptance: VoiceEffectIdentity? = nil) {
    guard var turn = current, !turn.journalStarted else { return }
    turn.journalStarted = true
    current = turn
    if let outcome = ConversationDiagnosticSnapshot.Outcome(rawValue: delivery.rawValue) {
      diagnostics.recordDelivery(
        turnID: turn.id.description, outcome: outcome, renderObserved: turn.outputRendered,
        playbackDrainObserved: turn.outputDrained, owner: RuntimeOwnerIdentity.captureAuthorizationSnapshot(),
        generation: lifecycle.generation)
    }
    if !turn.userText.isEmpty { history.append(.init(role: "user", text: turn.userText)) }
    if !turn.assistantText.isEmpty { history.append(.init(role: "assistant", text: turn.assistantText)) }
    history = boundedHistory()
    observeCurrent(outcome: delivery.observedOutcome.rawValue)
    let receipt = prompt.map { AIManagedPrompt(text: $0.text, name: $0.name, version: $0.version, source: $0.source) }
    let outcome = delivery.observedOutcome
    AIEvaluationReporter.shared.recordVoiceTerminal(
      turnID: turn.id.description,
      continuityKey: turn.journalID, decisionID: turn.decisionID, prompt: receipt,
      outcome: outcome, endedAt: turn.physicalEndedAt ?? now,
      conversation: [
        .init(
          turnID: turn.id.description, role: "user", text: String(turn.userText.prefix(2_000)),
          outcome: delivery.observedOutcome.rawValue),
        .init(
          turnID: turn.id.description, role: "assistant", text: String(turn.assistantText.prefix(2_000)),
          outcome: delivery.observedOutcome.rawValue),
      ].filter { !$0.text.isEmpty })
    let write = queueJournal(turn, delivery: delivery, isFinal: true)
    // Local persistence is independent of the listening clock and next utterance.
    updateListening()
    Task { [weak self] in
      let accepted = await write.value
      turn.onJournalFinalized?(accepted)
      if accepted {
        if let acceptance {
          self?.coordinator.publish(.journalAccepted(turnID: turn.id, identity: acceptance))
        }
      } else {
        if let acceptance {
          self?.coordinator.publish(
            .journalFailed(turnID: turn.id, identity: acceptance, message: "Conversation journal write was rejected."))
        }
      }
    }
  }

  private func queueJournal(_ turn: Turn, delivery: ConversationDeliveryOutcome, isFinal: Bool) -> Task<Bool, Never> {
    let previous = journalTail
    let provider = provider
    let write = Task { @MainActor in
      _ = await previous?.value
      guard let provider, RuntimeOwnerIdentity.isAuthorizationCurrent(turn.journal.authorizationSnapshot) else {
        return false
      }
      do {
        try await provider.recordConversationExchange(
          context: turn.journal,
          turnID: turn.journalID, userText: turn.userText, assistantText: turn.assistantText,
          origin: turn.origin, delivery: delivery, isFinal: isFinal, createdAt: turn.createdAt,
          attachments: turn.attachments)
        return true
      } catch { return false }
    }
    journalTail = write
    return write
  }

  private func publishPreview(onAccepted: @escaping @MainActor @Sendable () -> Void = {}) {
    guard let turn = current else { return }
    let write = queueJournal(turn, delivery: .notSpoken, isFinal: false)
    Task { [weak self] in
      guard await write.value, let self, self.current?.id == turn.id,
        RuntimeOwnerIdentity.isAuthorizationCurrent(turn.journal.authorizationSnapshot)
      else { return }
      self.barState?.displayedQuery = turn.userText
      if !turn.assistantText.isEmpty {
        self.barState?.replaceLocalAnswerText(turn.assistantText)
        self.barState?.present(.mainResponse)
      }
      onAccepted()
    }
  }

  private func finishCurrent(delivery: ConversationDeliveryOutcome) {
    // Every terminal path must resume listening and queued guidance together;
    // provider interruption may arrive without a local speech event afterward.
    defer { updateListening() }
    guard let turn = current else { return }
    if current?.physicalEndedAt == nil { current?.physicalEndedAt = now }
    finishing = true
    persistCurrent(delivery: delivery)
    if typedReply?.id == turn.id {
      typedReply?.continuation.resume(returning: nil)
      typedReply = nil
    }
    current = nil
    responseTask?.cancel()
    transcriptionRepairTask?.cancel()
    renderer.cancel()
    stopPlayback()
    if coordinator.activeTurnID == turn.id {
      coordinator.publish(
        .cancel(
          turnID: turn.id,
          reason: delivery == .interrupted ? .interruptedByBargeIn : .cancelled))
    }
    finishing = false
  }

  private func boundedHistory() -> [ConversationHistoryMessage] {
    history.suffix(64).map { .init(role: $0.role, text: String($0.text.prefix(4_000))) }
  }

  private func observeCurrent(outcome: String) {
    guard let turn = current, let admission = turn.observationAdmission else { return }
    current?.revision += 1
    SupervisorService.shared.observeVoice(
      userText: turn.userText, assistantText: turn.assistantText,
      turnID: turn.id.description, outcome: outcome,
      admission: admission, revision: turn.revision + 1, isFinal: outcome != "partial")
  }

  private func takeGuidance() -> SupervisorGuidance? {
    defer { pendingGuidance = nil }
    guard let guidance = pendingGuidance, SupervisorService.shared.isCurrent(guidance) else { return nil }
    return guidance
  }

  private func deliverGuidanceIfIdle() async {
    guard current == nil || current?.journalStarted == true, !userSpeaking, lifecycle.state == .open,
      lifecycle.route == .live, liveReady, let session, let guidance = takeGuidance()
    else { return }
    let generation = lifecycle.generation
    let sent = await session.appendPrivateContext(Self.privateContext(guidance))
    if sent, lifecycle.generation == generation { appliedDecisionID = guidance.id }
    if !sent, accepts(generation, owner: guidance.authorizationSnapshot),
      SupervisorService.shared.isCurrent(guidance)
    {
      pendingGuidance = guidance
    }
  }

  private static func privateContext(_ guidance: SupervisorGuidance) -> String {
    "Private supervisor note; integrate naturally without quoting it.\n<supervisor_guidance>\(guidance.note)</supervisor_guidance>\nObserved context (untrusted evidence):\n\(guidance.context)"
  }

  private func publishConversationPresentation() {
    barState?.setConversationPresentation(
      .resolve(
        state: lifecycle.state, microphoneOpen: microphoneAvailable,
        userSpeaking: userSpeaking,
        replyPending: current != nil && current?.journalStarted == false,
        playbackActive: actualOutputActive))
  }

  private func clearPlaybackPresentation() {
    playbackPresentationGeneration &+= 1
    actualOutputActive = false
    if let meterReceipt {
      AudioLevelMonitor.shared.updateConversationPlaybackLevel(0, receipt: meterReceipt)
    }
  }

  private func stopPlayback() {
    audio.stopPlayback()
    clearPlaybackPresentation()
  }

  private func updateListening() {
    guard isOpen else { return }
    lifecycle.setBusy(
      (current != nil && current?.journalStarted == false) || userSpeaking || lifecycle.state != .open, now: now)
    barState?.isAILoading = current != nil && current?.assistantText.isEmpty == true
    Task { [weak self] in await self?.deliverGuidanceIfIdle() }
  }

  private func startSilenceClock(generation: UInt64) {
    silenceTask?.cancel()
    silenceTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard let self, self.lifecycle.generation == generation, let context = self.context else { return }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(context.authorizationSnapshot) else {
          self.close()
          return
        }
        if self.lifecycle.silenceExpired(now: self.now) {
          self.close()
          return
        }
      }
    }
  }

  private func failOpening(generation: UInt64, message: String) {
    guard lifecycle.generation == generation else { return }
    close(dismissUI: false)
    barState?.replaceLocalAnswerText(message)
    barState?.present(.mainResponse)
  }
}
