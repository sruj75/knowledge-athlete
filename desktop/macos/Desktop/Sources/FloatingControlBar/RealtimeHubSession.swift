import Foundation
import VoiceTurnDomain

// MARK: - Realtime Hub Session
//
// One persistent WebSocket to Gemini Live, opened with a server-minted
// ephemeral token. The model is the hub: it does
// in-session STT + reasoning + routing (via tool calls) and speaks the answer.
//
//   • Gemini  — wss://generativelanguage.googleapis.com/ws/…BidiGenerateContent
//               Live model, response modality AUDIO + function calling.
//               Native spoken audio out (PCM) + output transcription.
//               Transport: Network.framework WebSocket with ALPN pinned to
//               http/1.1 — Gemini's endpoint upgrades URLSession's WS to HTTP/2
//               and resets it (the documented reason the legacy path needed a
//               relay); pinning ALPN avoids the upgrade.
//
// Normalized events: transcript_in / audio_out / text_out / tool_call / turn.done.

/// How the client authenticates to the realtime provider. Production accepts only
/// short-lived managed credentials. DEBUG builds also expose an explicit hermetic
/// mode for local transport tests; it never reports provider usage.
enum HubAuth {
  case managedEphemeral(String)
  #if DEBUG
    case hermeticStub
  #endif

  var value: String {
    switch self {
    case .managedEphemeral(let token): return token
    #if DEBUG
      case .hermeticStub: return "omi-hermetic-realtime-stub"
    #endif
    }
  }

  var reportsUsage: Bool {
    switch self {
    case .managedEphemeral: return true
    #if DEBUG
      case .hermeticStub: return false
    #endif
    }
  }
}

#if DEBUG
  struct RealtimeHubInputLifecycleSnapshot: Equatable {
    let isOpen: Bool
    let activityOpen: Bool
    let pendingTextInputCount: Int
    let pendingAudioChunkCount: Int
    let pendingVideoFrameCount: Int
    let pendingCommit: Bool
    let responseIdentityCount: Int
    let inputIdentityCount: Int
    let testingResponseCreateCount: Int
    let testingLastResponseToolChoice: String?
    let testingLastResponseInstruction: String?
  }
#endif

final class RealtimeHubSession: NSObject, @unchecked Sendable {
  private let provider: RealtimeHubProvider
  private let auth: HubAuth
  private let instructions: String
  /// Opaque cache-plan fields only; never raw conversation material.
  private let contextPlanID: String
  private let stableCacheIdentity: String
  private let dynamicContextIdentity: String
  private let contextCacheReplaced: Bool
  private weak var delegate: RealtimeHubSessionDelegate?

  var requiredInputSampleRate: Int { 16000 }
  // All socket + state access is serialized here (audio arrives on the capture
  // thread; receives on the URLSession/NW queue). Delegate calls hop to main.
  let q = DispatchQueue(label: "omi.realtime-hub.session")

  // Gemini's Live endpoint uses the existing hand-rolled RFC 6455 client.
  var rawWS: RealtimeRawWebSocketTransport?
  private let rawWebSocketFactory: (URL, DispatchQueue) -> RealtimeRawWebSocketTransport

  private var isOpen = false
  private var terminated = false
  #if DEBUG
    // The hermetic local-profile harness intentionally has no network socket. Its
    // explicit readiness seam is a successful local transport boundary, not a
    // disconnected production session.
    private var acceptsTestingTransport = false
    private var testingResponseCreateCount = 0
    private var testingLastResponseToolChoice: String?
    private var testingLastResponseInstruction: String?
    /// When set, the testing transport reports this error from `send`, so a
    /// confirmed-delivery caller can be tested against a failed provider send.
    private var testingForcedSendError: Error?

    func setTestingForcedSendError(_ error: Error?) {
      q.async { [weak self] in self?.testingForcedSendError = error }
    }
  #endif
  private var activeEventIdentity: RealtimeHubEventIdentity?
  private var completedGeminiEventIdentity: RealtimeHubEventIdentity?
  private var pendingAudio: [Data] = []
  /// Screen frames awaiting an open socket (base64, mime) — flushed into the turn in
  /// markReady. A cold first turn would otherwise drop the frame before connect.
  private var pendingVideo: [(b64: String, mime: String)] = []
  /// Headless-test text awaiting a provider-acceptable input window.
  private var pendingTextInputs: [(text: String, logLabel: String)] = []
  private var pendingCommit = false
  /// Gemini manual-VAD: each PTT turn must be bracketed activityStart…activityEnd.
  /// On a WARM session that brackets per turn — sending it once at connect made
  /// turns 2+ arrive with no speech window (Gemini then greets generically).
  private var activityOpen = false
  private var pendingActivityStart = false
  /// Gemini: a committed turn is awaiting its spoken reply. Gates BOTH audio
  /// playback and turn completion to the CURRENT turn, so an interrupted/abandoned
  /// turn's trailing audio + bookkeeping `turnComplete` can't leak into the next
  /// one. Set on activityEnd (commit); cleared on this turn's `turnComplete`, on a
  /// server `interrupted`, or when a new turn interrupts (beginInputTurn interrupting).
  private var geminiResponsePending = false
  private var pendingGeminiToolCallIds = Set<String>()
  /// A provider may close the function-call cycle without producing a user-facing
  /// response. One explicit internal continuation is permitted for that exact voice
  /// turn; further retries would create an unbounded tool/turn loop.
  private var postToolContinuationAttempted = false
  private var geminiSyntheticToolCallCounter = 0

  // Per-turn token usage for managed billing — client-reported. Reset at commit
  // and reported at finishTurn. Gemini sends cumulative usageMetadata (we keep the latest).
  private var usageInText = 0
  private var usageInAudio = 0
  private var usageInImage = 0
  private var usageInCached = 0
  private var usageOutText = 0
  private var usageOutAudio = 0
  /// Evidence is local-only. This opaque descriptor lets the local log correlate the
  /// attachment with Gemini's later per-modality usage without logging pixels or app text.
  private var activeScreenEvidence: RealtimeScreenEvidenceDescriptor?

  /// Log prefix that names the provider + model on every line, so it's always
  /// clear which model produced which event.
  private var tag: String { "RealtimeHub[gemini:\(provider.modelID)]" }

  init(
    provider: RealtimeHubProvider,
    auth: HubAuth,
    instructions: String,
    contextPlanID: String = "",
    stableCacheIdentity: String = "",
    dynamicContextIdentity: String = "",
    contextCacheReplaced: Bool = false,
    rawWebSocketFactory: @escaping (URL, DispatchQueue) -> RealtimeRawWebSocketTransport = {
      RawWebSocket(url: $0, queue: $1)
    },
    delegate: RealtimeHubSessionDelegate
  ) {
    self.provider = provider
    self.auth = auth
    self.instructions = instructions
    self.contextPlanID = contextPlanID
    self.stableCacheIdentity = stableCacheIdentity
    self.dynamicContextIdentity = dynamicContextIdentity
    self.contextCacheReplaced = contextCacheReplaced
    self.rawWebSocketFactory = rawWebSocketFactory
    self.delegate = delegate
    super.init()
  }

  // MARK: Lifecycle

  func start() {
    q.async { [weak self] in self?._start() }
  }

  private func _start() {
    guard !terminated else { return }
    guard let request = makeRequest(), let url = request.url else {
      notifyError(
        RealtimeHubTransportFailure(
          kind: .configuration,
          message: "Could not build \(provider.displayName) request URL",
          systemDomain: nil,
          systemCode: nil))
      return
    }
    log("RealtimeHub: connecting \(provider.displayName) → \(url.host ?? "?")")
    let ws = rawWebSocketFactory(url, q)
    rawWS = ws
    ws.onOpen = { [weak self] in
      guard let self, !self.terminated else { return }
      log("RealtimeHub: raw WS open (Gemini Live)")
      self.sendSessionSetup()
    }
    ws.onMessage = { [weak self] data in self?.handleMessage(data) }
    ws.onClose = { [weak self] code, reason in
      self?.notifyError(.providerClose(code: code, reason: reason))
    }
    ws.onError = { [weak self] failure in
      self?.notifyError(.rawWebSocket(failure))
    }
    ws.connect()
  }

  /// Stop delivering events to the delegate. Used when the controller intentionally
  /// drops this socket (barge-in / cancel reconnect) so its teardown close/error
  /// can't reach the controller and tear down the replacement session.
  func detach() {
    q.async { [weak self] in self?.delegate = nil }
  }

  func stop() {
    q.async { [weak self] in
      self?.beginStopOnQueue()
    }
  }

  func beginStopOnQueue() {
    beginTransportTerminationOnQueue()
    isOpen = false
    pendingAudio.removeAll()
    pendingVideo.removeAll()
    pendingTextInputs.removeAll()
    pendingCommit = false
    activityOpen = false
    pendingActivityStart = false
    geminiResponsePending = false
    postToolContinuationAttempted = false
    activeEventIdentity = nil
    completedGeminiEventIdentity = nil
  }

  private func beginTransportTerminationOnQueue() {
    rawWS?.close()
    isOpen = false
  }

  private func notifyError(_ failure: RealtimeHubTransportFailure) {
    guard !terminated else { return }
    terminated = true
    // The session owns the physical transport. Retire it before publishing the
    // terminal callback so controller recovery can never overlap a replacement
    // with a still-live socket.
    // Preserve buffered logical input until the controller has captured any
    // reconnect obligation. Only the physical transport terminates here.
    beginTransportTerminationOnQueue()
    let d = delegate
    Task { @MainActor in d?.hubDidError(failure, source: self) }
  }

  // MARK: Public stream API

  /// Gemini barge-in replaces the physical session at the controller boundary.
  func cancelActiveResponse() {
    // No same-session cancellation wire exists for Gemini Live.
  }

  /// Feed mic PCM16 mono at `requiredInputSampleRate` (caller resamples).
  func sendAudio(_ pcm: Data) {
    q.async { [weak self] in
      guard let self else { return }
      guard self.isOpen, self.activityOpen else {
        self.pendingAudio.append(pcm)
        return
      }
      self.appendAudioFrame(pcm)
    }
  }

  #if DEBUG
    func inputLifecycleSnapshot() async -> RealtimeHubInputLifecycleSnapshot {
      await withCheckedContinuation { continuation in
        q.async {
          continuation.resume(
            returning: RealtimeHubInputLifecycleSnapshot(
              isOpen: self.isOpen,
              activityOpen: self.activityOpen,
              pendingTextInputCount: self.pendingTextInputs.count,
              pendingAudioChunkCount: self.pendingAudio.count,
              pendingVideoFrameCount: self.pendingVideo.count,
              pendingCommit: self.pendingCommit,
              responseIdentityCount: 0,
              inputIdentityCount: 0,
              testingResponseCreateCount: self.testingResponseCreateCount,
              testingLastResponseToolChoice: self.testingLastResponseToolChoice,
              testingLastResponseInstruction: self.testingLastResponseInstruction))
        }
      }
    }

    func markReadyForTesting() {
      q.async { [weak self] in
        self?.acceptsTestingTransport = true
        self?.markReady()
      }
    }

  #endif

  /// Send one image as a video frame INSIDE the current open activity window (Gemini).
  /// Manual-VAD requires media to ride a user turn bracketed by activityStart…activityEnd;
  /// a frame sent here becomes part of the user's speech turn, so the model has the screen
  /// when it answers. This is the ONLY image delivery this model accepts — a separate
  /// image-only turn (after the speech turn closed) is rejected with close 1007.
  func sendVideoFrame(_ image: Data, mime: String, allowClosedActivityWindow: Bool = false) {
    let b64 = image.base64EncodedString()
    q.async { [weak self] in
      guard let self else { return }
      // Buffer until the socket is open AND a turn is active, then flush in markReady.
      // A cold first turn dumps audio + this frame before connect (~300ms); without
      // buffering the frame is dropped and the model answers blind.
      guard self.isOpen, self.activityOpen || allowClosedActivityWindow else {
        self.pendingVideo.append((b64, mime))
        log("\(self.tag): screen frame buffered until open (\(image.count) bytes)")
        return
      }
      let phase = self.activityOpen ? "in-turn" : "after-activity-end"
      log("\(self.tag): screen frame sent \(phase) (\(image.count) bytes)")
      self.send(json: ["realtimeInput": ["video": ["data": b64, "mimeType": mime]]])
    }
  }

  /// TEST SEAM (ptt_test_turn only, bridge is non-prod-only): inject the probe text as
  /// realtime user input so the model answers the forced transcript instead of the
  /// fixture audio — the harness feeds a sine tone, and without this the model replies
  /// to a beep in whatever language it hallucinates. Gemini: text rides the open
  /// activity window (same rule as video frames).
  /// TEST SEAM (ptt_test_turn only): queue-synced snapshot of whether this session can
  /// accept in-turn input right now. Gemini needs the speech-activity window open.
  /// The headless turn waits on this before injecting
  /// text/committing — beginTurn may defer activityStart during a seed-stale reconnect,
  /// and an activityEnd without a window is a Gemini policy-close (1008).
  func activityWindowOpen() async -> Bool {
    await withCheckedContinuation { continuation in
      q.async {
        continuation.resume(
          returning: self.isOpen && self.activityOpen)
      }
    }
  }

  func sendTestTextInput(_ text: String) async -> Bool {
    await sendTextInput(text, logLabel: "test text input")
  }

  /// True when the session can accept injected (non-PTT) context *right now*.
  /// Evaluated on `q`. Gemini needs an open speech-activity window.
  private var canAcceptInjectedContext: Bool {
    isOpen && activityOpen
  }

  /// Silently appends completed background-agent context to the conversation.
  /// No response is requested — the model uses it on its next turn.
  ///
  /// Unlike ordinary PTT text input this does NOT buffer: the caller advances an
  /// exactly-once kernel checkpoint on a `true` return, so `true` must mean
  /// "confirmed delivered," never "buffered" (a buffered item is dropped by
  /// `stopOnQueue`/`abandonInputTurn` — an acked-but-lost completion). When the
  /// session can't accept context yet it returns `false` and the checkpoint
  /// stays unadvanced; the delivery service retries when the session next
  /// becomes ready (`hubDidOpenInputWindow`). When it can, `true` follows the
  /// provider send's completion, not a fire-and-forget enqueue.
  func sendBackgroundAgentContext(_ text: String) async -> Bool {
    await withCheckedContinuation { continuation in
      q.async { [weak self] in
        guard let self, self.canAcceptInjectedContext else {
          continuation.resume(returning: false)
          return
        }
        self.send(json: self.textInputWire(text)) { error in
          continuation.resume(returning: error == nil)
        }
      }
    }
  }

  /// A provider can complete a tool-only response after accepting the final tool
  /// result without emitting a user-facing reply. Continue the same physical turn
  /// once, never as a synthetic user request. The continuation is bounded here so
  /// every caller shares the same no-loop contract.
  func resumeAfterToolOnlyCycle(
    identity: RealtimeHubEventIdentity,
    completion: @escaping (RealtimePostToolContinuationStartResult) -> Void
  ) {
    // The caller's completion is non-Sendable; box it so the session queue can
    // carry it across without forcing the caller's closure to be @Sendable.
    let completionBox = SessionCallbackBox(completion)
    q.async { [weak self] in
      guard let self else {
        completionBox.value(.transportUnavailable)
        return
      }

      guard self.activeEventIdentity == identity else {
        completionBox.value(.stale)
        return
      }
      guard self.isOpen else {
        completionBox.value(.transportUnavailable)
        return
      }

      let providerHasResponseInFlight =
        self.activityOpen || self.geminiResponsePending || !self.pendingGeminiToolCallIds.isEmpty
      if self.postToolContinuationAttempted {
        completionBox.value(providerHasResponseInFlight ? .alreadyInFlight : .exhausted)
        return
      }
      guard !providerHasResponseInFlight else {
        completionBox.value(.alreadyInFlight)
        return
      }

      self.postToolContinuationAttempted = true
      self.completedGeminiEventIdentity = nil
      self.activityOpen = true
      for wire in Self.geminiPostToolContinuationWires() {
        self.send(json: wire)
      }
      self.activityOpen = false
      self.geminiResponsePending = true
      log("\(self.tag): requested explicit Gemini post-tool continuation")
      completionBox.value(.started)
    }
  }

  static let geminiPostToolContinuationInstruction =
    "The tool work for the user's most recent request is complete. Do not call any more tools. "
    + "Now give the concise, natural spoken answer to that same request using the tool result already provided."

  static func geminiPostToolContinuationWires() -> [[String: Any]] {
    [
      ["realtimeInput": ["activityStart": [:]]],
      ["realtimeInput": ["text": geminiPostToolContinuationInstruction]],
      ["realtimeInput": ["activityEnd": [:]]],
    ]
  }

  private func sendTextInput(_ text: String, logLabel: String) async -> Bool {
    await withCheckedContinuation { continuation in
      q.async { [weak self] in
        guard let self else {
          continuation.resume(returning: false)
          return
        }
        guard self.isOpen else {
          self.bufferTextInput(text, logLabel: logLabel, reason: "socket not open")
          continuation.resume(returning: true)
          return
        }
        if !self.activityOpen {
          self.bufferTextInput(text, logLabel: logLabel, reason: "no open activity window")
          continuation.resume(returning: true)
          return
        }
        self.sendTextInputNow(text, logLabel: logLabel)
        continuation.resume(returning: true)
      }
    }
  }

  private func bufferTextInput(_ text: String, logLabel: String, reason: String) {
    pendingTextInputs.append((text: text, logLabel: logLabel))
    log("\(tag): \(logLabel) buffered — \(reason) (\(text.count) chars)")
  }

  private func flushPendingTextInputs() {
    guard isOpen else { return }
    guard activityOpen else { return }
    let inputs = pendingTextInputs
    pendingTextInputs.removeAll()
    for input in inputs {
      sendTextInputNow(input.text, logLabel: input.logLabel)
    }
  }

  /// Gemini wire form of a user text-input message. Shared by the buffered
  /// PTT path (`sendTextInputNow`) and the confirmed, non-buffering background
  /// path (`sendBackgroundAgentContext`).
  private func textInputWire(_ text: String) -> [String: Any] {
    ["realtimeInput": ["text": text]]
  }

  private func sendTextInputNow(_ text: String, logLabel: String) {
    send(json: textInputWire(text))
    log("\(tag): \(logLabel) sent (\(text.count) chars)")
  }

  /// End the user's PTT turn and ask the model to respond.
  /// Start a new PTT turn. Gemini: open a fresh speech-activity window (must be
  /// done EVERY turn on a warm session).
  func beginInputTurn(
    turnID: VoiceTurnID? = nil,
    responseID: VoiceResponseID? = nil,
    interrupting: Bool = false
  ) {
    q.async { [weak self] in
      guard let self else { return }
      if let turnID, let responseID {
        self.activeEventIdentity = RealtimeHubEventIdentity(
          turnID: turnID,
          responseID: responseID)
      } else {
        self.activeEventIdentity = nil
      }
      self.postToolContinuationAttempted = false
      // Barge-in on a live Gemini generation uses a fresh session at the controller
      // boundary. This same-session flag is only a local gate for abandoned/stale
      // Gemini events that arrive before replacement or on non-provider interruptions.
      if interrupting {
        self.geminiResponsePending = false
        self.pendingGeminiToolCallIds.removeAll()
      }
      guard !self.activityOpen else { return }
      self.activityOpen = true
      if self.isOpen {
        self.send(json: ["realtimeInput": ["activityStart": [:]]])
        self.flushPendingAudioIfReady()
        self.flushPendingTextInputs()
        log("\(self.tag): turn begin (activityStart\(interrupting ? ", interrupting in-flight reply" : ""))")
        // The activity window is open — the session can now accept injected
        // context. Signal delivery so a background completion left unadvanced
        // while warm-idle is retried at this natural turn boundary.
        let delegate = self.delegate
        Task { @MainActor in delegate?.hubDidOpenInputWindow(source: self) }
        if self.pendingCommit {
          self.pendingCommit = false
          self.commitInputTurnNow()
        }
      } else {
        self.pendingActivityStart = true
      }
    }
  }

  func commitInputTurn() {
    q.async { [weak self] in
      guard let self else { return }
      self.resetTurnUsage()  // fresh per-turn usage before the model responds
      guard self.isOpen, self.activityOpen else {
        self.pendingCommit = true
        return
      }
      self.commitInputTurnNow()
    }
  }

  private func commitInputTurnNow() {
    flushPendingAudioIfReady()
    flushPendingTextInputs()
    log("\(tag): turn committed")
    pendingGeminiToolCallIds.removeAll()
    send(json: ["realtimeInput": ["activityEnd": [:]]])
    activityOpen = false
    geminiResponsePending = true
    // Gemini auto-responds at activityEnd; no explicit response request.
  }

  /// Abandon the current turn without expecting a reply (silent tap / cancel). No
  /// teardown — closes the activity window and leaves the reply gated off, so the
  /// model never answers the silence and the warm socket (with context) is kept.
  func abandonInputTurn() {
    q.async { [weak self] in
      guard let self else { return }
      self.geminiResponsePending = false
      self.pendingAudio.removeAll()
      self.pendingVideo.removeAll()
      self.pendingTextInputs.removeAll()
      self.pendingCommit = false
      self.pendingActivityStart = false
      self.activeEventIdentity = nil
      self.completedGeminiEventIdentity = nil
      self.pendingGeminiToolCallIds.removeAll()
      if self.activityOpen, self.isOpen {
        self.send(json: ["realtimeInput": ["activityEnd": [:]]])
      }
      self.activityOpen = false
    }
  }

  /// Return a tool's result to the model and let it continue (speak).
  ///
  /// Gemini handles realtime video and tool responses as concurrent streams, so sending a
  /// screenshot as `realtimeInput.video` and then unblocking the function can race: the model
  /// may answer from older context before it processes the frame. Gemini 3 supports inline
  /// FunctionResponse parts; attach the fresh pixels there so the paused screenshot call resumes
  /// only with the exact image it captured.
  func sendToolResult(
    callId: String,
    name: String,
    output: String,
    screenEvidence: RealtimeScreenEvidenceAttachment? = nil,
    onWireEnqueued: ((Bool) -> Void)? = nil
  ) {
    // `onWireEnqueued` is caller-owned and non-Sendable; box it so the session
    // queue can carry it across without forcing the caller's closure @Sendable.
    let onWireEnqueuedBox = SessionCallbackBox(onWireEnqueued)
    q.async { [weak self] in
      guard let self else { return }
      self.pendingGeminiToolCallIds.remove(callId)
      if let screenEvidence {
        self.activeScreenEvidence = screenEvidence.descriptor
      }
      let wire = Self.geminiToolResponse(
        callId: callId,
        name: name,
        output: output,
        screenEvidence: screenEvidence)
      if let screenEvidence {
        let serializedBytes = (try? JSONSerialization.data(withJSONObject: wire))?.count ?? 0
        log(
          "\(self.tag): ptt_screen_evidence stage=tool_wire_prepared evidence=\(screenEvidence.descriptor.opaqueID) "
            + "image_bytes=\(screenEvidence.jpeg.count) serialized_bytes=\(serializedBytes)")
      }
      self.send(json: wire) { error in
        onWireEnqueuedBox.value?(error == nil)
      }
    }
  }

  static func geminiToolResponse(
    callId: String,
    name: String,
    output: String,
    screenEvidence: RealtimeScreenEvidenceAttachment?
  ) -> [String: Any] {
    var functionResponse: [String: Any] = [
      "id": callId,
      "name": name,
      "response": ["result": output],
    ]
    if let screenEvidence {
      let displayName = "live-screenshot.jpg"
      functionResponse["response"] = [
        "result": output,
        "image": ["$ref": displayName],
        "evidence_id": screenEvidence.descriptor.evidenceID,
      ]
      functionResponse["parts"] = [
        [
          "inlineData": [
            "mimeType": "image/jpeg",
            "data": screenEvidence.jpeg.base64EncodedString(),
            "displayName": displayName,
          ]
        ]
      ]
    }
    return ["toolResponse": ["functionResponses": [functionResponse]]]
  }

  // MARK: - Request / setup

  private func makeRequest() -> URLRequest? {
    let prefix = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage"
    let base = "\(prefix).v1alpha.GenerativeService.BidiGenerateContentConstrained"
    guard var comps = URLComponents(string: base) else { return nil }
    comps.queryItems = [URLQueryItem(name: "access_token", value: auth.value)]
    guard let url = comps.url else { return nil }
    return URLRequest(url: url)
  }

  var supportsInputTranscriptionLanguage: Bool { false }
  func setInputTranscriptionLanguage(_ code: String?) { _ = code }

  private func sendSessionSetup() {
    // AUDIO modality: the only currently-available Live models are native-audio
    // (TEXT is rejected with close 1007). The spoken reply (24k PCM) is played by
    // StreamingPCMPlayer. outputAudioTranscription gives us the text for logging /
    // an optional bubble; inputAudioTranscription gives the user's STT.
    send(json: [
      "setup": [
        "model": "models/\(provider.modelID)",
        // Low temperature → tool-choice routing is consistent for identical inputs
        // (default ~1.0 made the same request flip between answering and escalating).
        // mediaResolution HIGH so a screenshot frame isn't downsampled to a generic blur.
        "generationConfig": [
          "responseModalities": ["AUDIO"], "temperature": 0.3,
          "mediaResolution": "MEDIA_RESOLUTION_HIGH",
          // Pin the spoken voice so model revisions cannot change it implicitly.
          "speechConfig": [
            "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": "Charon"]]
          ],
        ],
        "systemInstruction": ["parts": [["text": instructions]]],
        "tools": [
          [
            "functionDeclarations": RealtimeHubTools.geminiFunctionDeclarations
          ]
        ],
        "inputAudioTranscription": [:],
        "outputAudioTranscription": [:],
        // turnCoverage = ALL_VIDEO so an injected screenshot frame is part of the turn
        // even though we send it after activityEnd (default coverage would drop it).
        "realtimeInputConfig": [
          "automaticActivityDetection": ["disabled": true],
          "turnCoverage": "TURN_INCLUDES_AUDIO_ACTIVITY_AND_ALL_VIDEO",
        ],
        // Keep the session from degrading as turns accumulate: a sliding context
        // window stops unbounded growth (which was making replies slow to ~30–48s
        // and eventually stop). Without this, long sessions slowly die.
        "contextWindowCompression": ["slidingWindow": [:]],
      ]
    ])
  }

  private func markReady() {
    guard !terminated, !isOpen else { return }
    isOpen = true
    log("\(tag): ready")
    // Open the speech window if a turn started before we connected (Gemini).
    if pendingActivityStart {
      pendingActivityStart = false
      send(json: ["realtimeInput": ["activityStart": [:]]])
    }
    flushPendingTextInputs()
    flushPendingAudioIfReady()
    // Flush any screen frame INTO the turn (after activityStart + audio, before commit).
    for v in pendingVideo {
      send(json: ["realtimeInput": ["video": ["data": v.b64, "mimeType": v.mime]]])
      log("\(tag): screen frame flushed into turn")
    }
    pendingVideo.removeAll()
    flushPendingTextInputs()
    if pendingCommit, activityOpen {
      pendingCommit = false
      commitInputTurnNow()
    }
    let d = delegate
    Task { @MainActor in d?.hubDidConnect(source: self) }
  }

  // Send buffered audio after open (already on q).
  /// Send one mic PCM frame to the provider. Must be called on `q` with `isOpen`.
  /// Shared by sendAudio (live) and the markReady flush of buffered pre-connect audio.
  private func appendAudioFrame(_ pcm: Data) {
    let b64 = pcm.base64EncodedString()
    send(json: ["realtimeInput": ["audio": ["data": b64, "mimeType": "audio/pcm;rate=16000"]]])
  }

  private func flushPendingAudioIfReady() {
    guard isOpen, activityOpen else { return }
    for chunk in pendingAudio { appendAudioFrame(chunk) }
    pendingAudio.removeAll()
  }

  // MARK: - Receive + parse

  private func handleMessage(_ data: Data) {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    handleGemini(obj)
  }

  private func deliverToDelegate(
    _ body: @escaping @MainActor (RealtimeHubSessionDelegate) -> Void
  ) {
    guard let delegate else { return }
    // `body` (@MainActor closure) and `delegate` are non-Sendable; box both for
    // the main hop. They are only ever used on the main actor.
    let delegateBox = SessionCallbackBox(delegate)
    let bodyBox = SessionCallbackBox(body)
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        bodyBox.value(delegateBox.value)
      }
    }
  }

  private func emitText(
    _ text: String,
    isFinal: Bool,
    identity explicitIdentity: RealtimeHubEventIdentity? = nil
  ) {
    guard !text.isEmpty || isFinal else { return }
    let identity = explicitIdentity ?? activeEventIdentity
    deliverToDelegate { delegate in
      delegate.hubDidEmitText(text, isFinal: isFinal, identity: identity, source: self)
    }
  }

  private func emitTranscript(
    _ text: String,
    isFinal: Bool,
    identity explicitIdentity: RealtimeHubEventIdentity? = nil
  ) {
    let identity = explicitIdentity ?? activeEventIdentity
    deliverToDelegate { delegate in
      delegate.hubDidReceiveInputTranscript(
        text, isFinal: isFinal, identity: identity, source: self)
    }
  }

  private func emitAudio(
    _ pcm: Data,
    identity explicitIdentity: RealtimeHubEventIdentity? = nil
  ) {
    let identity = explicitIdentity ?? activeEventIdentity
    deliverToDelegate { delegate in
      delegate.hubDidReceiveAudio(pcm, identity: identity, source: self)
    }
  }

  private func emitTool(
    name: String,
    callId: String,
    argumentsJSON: String,
    identity explicitIdentity: RealtimeHubEventIdentity? = nil
  ) {
    log("\(tag): tool_call \(name)(\(argumentsJSON.prefix(160)))")
    let identity = explicitIdentity ?? activeEventIdentity
    deliverToDelegate { delegate in
      delegate.hubDidRequestTool(
        name: name, callId: callId, argumentsJSON: argumentsJSON,
        identity: identity, source: self)
    }
  }

  private func finishTurn(identity explicitIdentity: RealtimeHubEventIdentity? = nil) {
    reportUsageIfNeeded()
    let identity = explicitIdentity ?? activeEventIdentity
    deliverToDelegate { delegate in
      delegate.hubDidFinishTurn(identity: identity, source: self)
    }
  }

  // MARK: - Usage (client-reported billing, managed sessions only)

  private func resetTurnUsage() {
    usageInText = 0
    usageInAudio = 0
    usageInImage = 0
    usageInCached = 0
    usageOutText = 0
    usageOutAudio = 0
  }

  /// Gemini: usageMetadata is cumulative for the turn → keep the latest (replace, not sum).
  private func accumulateGeminiUsage(_ um: [String: Any]) {
    func split(_ arr: Any?) -> (text: Int, audio: Int, image: Int) {
      var t = 0
      var a = 0
      var i = 0
      for d in (arr as? [[String: Any]]) ?? [] {
        let c = (d["tokenCount"] as? Int) ?? (d["tokenCount"] as? NSNumber)?.intValue ?? 0
        switch (d["modality"] as? String)?.uppercased() {
        case "AUDIO": a += c
        case "IMAGE": i += c
        default: t += c
        }
      }
      return (t, a, i)
    }
    let pin = split(um["promptTokensDetails"])
    let pout = split(um["responseTokensDetails"])
    if pin.text == 0 && pin.audio == 0 && pin.image == 0 {
      usageInText = (um["promptTokenCount"] as? Int) ?? 0
      usageInAudio = 0
      usageInImage = 0
    } else {
      usageInText = pin.text
      usageInAudio = pin.audio
      usageInImage = pin.image
    }
    if pout.text == 0 && pout.audio == 0 {
      usageOutText = (um["candidatesTokenCount"] as? Int) ?? (um["responseTokenCount"] as? Int) ?? 0
      usageOutAudio = 0
    } else {
      usageOutText = pout.text
      usageOutAudio = pout.audio
    }
    usageInCached = (um["cachedContentTokenCount"] as? Int) ?? 0
  }

  /// Report the turn's usage to the backend for every production managed session.
  /// Resets first so a second finishTurn (barge-in edge) can't double-report.
  private func reportUsageIfNeeded() {
    let it = usageInText
    let ia = usageInAudio
    let ic = usageInCached
    let ot = usageOutText
    let oa = usageOutAudio
    if let evidence = activeScreenEvidence {
      log(
        "\(tag): ptt_screen_evidence stage=provider_turn_done evidence=\(evidence.opaqueID) "
          + "image_tokens=\(usageInImage)")
      activeScreenEvidence = nil
    }
    resetTurnUsage()
    guard auth.reportsUsage, it + ia + ic + ot + oa > 0 else { return }
    Task {
      await APIClient.shared.reportRealtimeUsage(
        inputText: it, inputAudio: ia, inputCached: ic, outputText: ot, outputAudio: oa)
    }
  }

  // MARK: Gemini events

  private func handleGemini(_ e: [String: Any]) {
    if e["setupComplete"] != nil {
      markReady()
      return
    }
    if let um = e["usageMetadata"] as? [String: Any] { accumulateGeminiUsage(um) }
    if let toolCall = e["toolCall"] as? [String: Any],
      let calls = toolCall["functionCalls"] as? [[String: Any]]
    {
      // Ignore tool calls when no committed turn is awaiting a reply — an abandoned/
      // discarded turn still reaches Gemini (we send activityEnd to close the window),
      // and without this guard it acts on half-heard audio (e.g. fires get_tasks).
      guard geminiResponsePending else {
        log("\(tag): ignoring tool call — no live committed turn (abandoned/discarded)")
        return
      }
      for call in calls {
        let name = call["name"] as? String ?? ""
        // Gemini may omit ids; synthesize unique ones so same-name calls in one turn
        // do not collapse controller/session pending-tool bookkeeping.
        let callId = call["id"] as? String ?? nextGeminiSyntheticToolCallId(name: name)
        pendingGeminiToolCallIds.insert(callId)
        let args = call["args"] as? [String: Any] ?? [:]
        let argsJSON =
          (try? JSONSerialization.data(withJSONObject: args)).flatMap {
            String(data: $0, encoding: .utf8)
          } ?? "{}"
        if !name.isEmpty { emitTool(name: name, callId: callId, argumentsJSON: argsJSON) }
      }
      return
    }
    guard let sc = e["serverContent"] as? [String: Any] else { return }
    if (sc["interrupted"] as? Bool) == true {
      // Barge-in: drop the pending reply so its trailing audio + bookkeeping turnComplete
      // are ignored; the new turn (already started via activityStart) re-arms on commit.
      geminiResponsePending = false
      pendingGeminiToolCallIds.removeAll()
      log("\(tag): server confirmed interrupt")
    }
    // NOTE: do NOT finish on generationComplete — Gemini sends it while the spoken audio
    // is still streaming, so finishing there truncates the reply and makes the next turn
    // interrupt the server's still-open turn. We finish on turnComplete (below), which
    // arrives when the audio actually completes.
    if let it = sc["inputTranscription"] as? [String: Any], let t = it["text"] as? String {
      if let identity = GeminiRealtimeEventOwnership.inputIdentity(
        active: activeEventIdentity,
        completed: completedGeminiEventIdentity)
      {
        emitTranscript(t, isFinal: false, identity: identity)
      } else {
        log("\(tag): dropping ambiguous Gemini input transcription across turn boundary")
      }
    }
    if let ot = sc["outputTranscription"] as? [String: Any], let t = ot["text"] as? String {
      emitText(t, isFinal: false)  // the spoken reply's text, for logging / the bubble
    }
    if let parts = (sc["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] {
      for p in parts {
        if let t = p["text"] as? String { emitText(t, isFinal: false) }
        if let inline = p["inlineData"] as? [String: Any],
          let mime = inline["mimeType"] as? String, mime.contains("audio/pcm"),
          let b64 = inline["data"] as? String, let d = Data(base64Encoded: b64)
        {
          if geminiResponsePending { emitAudio(d) }  // gated: only the live turn's reply
        }
      }
    }
    if (sc["turnComplete"] as? Bool) == true {
      guard pendingGeminiToolCallIds.isEmpty else {
        log("\(tag): deferring Gemini turnComplete with \(pendingGeminiToolCallIds.count) tool result(s) pending")
        return
      }
      // Only finish the turn we're actually awaiting a reply for. A turnComplete that
      // closes an interrupted/abandoned generation (pending=false) is ignored, so it
      // can't prematurely end the live turn.
      if geminiResponsePending {
        geminiResponsePending = false
        completedGeminiEventIdentity = activeEventIdentity
        emitText("", isFinal: true)
        finishTurn(identity: completedGeminiEventIdentity)
      }
    }
  }

  private func nextGeminiSyntheticToolCallId(name: String) -> String {
    geminiSyntheticToolCallCounter += 1
    return "\(name):\(geminiSyntheticToolCallCounter)"
  }

  // MARK: - Send (on q)

  private func send(json: [String: Any], completion: ((Error?) -> Void)? = nil) {
    // `completion` is non-Sendable; box it for the raw-websocket completion.
    let completionBox = SessionCallbackBox(completion)
    guard let data = try? JSONSerialization.data(withJSONObject: json),
      let text = String(data: data, encoding: .utf8)
    else {
      failSend(RealtimeHubSessionSendError.encodingFailed, completion: completion)
      return
    }
    #if DEBUG
      if acceptsTestingTransport {
        if (json["type"] as? String) == "response.create" {
          testingResponseCreateCount += 1
          testingLastResponseToolChoice = (json["response"] as? [String: Any])?["tool_choice"] as? String
          testingLastResponseInstruction = (json["response"] as? [String: Any])?["instructions"] as? String
        }
        // Lets tests exercise a failed send so callers that gate on delivery
        // (sendBackgroundAgentContext → exactly-once checkpoint) can be verified.
        completion?(testingForcedSendError)
        return
      }
    #endif
    guard let rawWS else {
      failSend(RealtimeHubSessionSendError.notConnected, completion: completion)
      return
    }
    rawWS.sendText(text) { [weak self] error in
      guard let self else { return }
      self.q.async {
        if let error { self.notifyError(.system(error, phase: .send)) }
        completionBox.value?(error)
      }
    }
  }

  /// Every local send failure is a terminal session failure, including synchronous no-transport
  /// and encoding paths. A screen-evidence receipt must never wait for a provider deadline after
  /// the session has already proved it cannot enqueue the exact wire.
  private func failSend(_ error: Error, completion: ((Error?) -> Void)?) {
    notifyError(.system(error, phase: .send))
    completion?(error)
  }
}

private enum RealtimeHubSessionSendError: LocalizedError {
  case encodingFailed
  case notConnected

  var errorDescription: String? {
    switch self {
    case .encodingFailed: "Could not encode realtime transport data."
    case .notConnected: "Realtime transport is not connected."
    }
  }
}
