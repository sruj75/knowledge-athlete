import Foundation

/// Gemini's automatic-VAD wire protocol. This transport has no tool registry,
/// microphone lifecycle, journal, or UI authority. The one fixed function can
/// request a conversation end after its answer has physically drained.
final class ConversationLiveSession: @unchecked Sendable {
  struct Usage: Sendable, Equatable {
    var inputText = 0
    var inputAudio = 0
    var inputCached = 0
    var outputText = 0
    var outputAudio = 0
    var thinking = 0

    init(_ metadata: [String: Any]) {
      func split(_ value: Any?) -> (text: Int, audio: Int) {
        var text = 0
        var audio = 0
        for detail in value as? [[String: Any]] ?? [] {
          let count = max(0, detail["tokenCount"] as? Int ?? 0)
          if (detail["modality"] as? String)?.uppercased() == "AUDIO" { audio += count } else { text += count }
        }
        return (text, audio)
      }
      let input = split(metadata["promptTokensDetails"])
      let output = split(metadata["responseTokensDetails"])
      inputText = input.text + input.audio == 0 ? max(0, metadata["promptTokenCount"] as? Int ?? 0) : input.text
      inputAudio = input.audio
      // Gemini prompt counts include cached tokens. The ledger expects mutually
      // exclusive uncached text/audio and cached buckets.
      inputCached = min(inputText + inputAudio, max(0, metadata["cachedContentTokenCount"] as? Int ?? 0))
      let cached = split(metadata["cacheTokensDetails"])
      var remaining = inputCached
      let knownText = min(inputText, cached.text, remaining)
      inputText -= knownText
      remaining -= knownText
      let knownAudio = min(inputAudio, cached.audio, remaining)
      inputAudio -= knownAudio
      remaining -= knownAudio
      // Missing modality details cannot duplicate cached tokens. Allocate the
      // remainder within available text first, then audio, never below zero.
      let remainingText = min(inputText, remaining)
      inputText -= remainingText
      remaining -= remainingText
      inputAudio -= min(inputAudio, remaining)
      outputText =
        output.text + output.audio == 0
        ? max(0, metadata["responseTokenCount"] as? Int ?? metadata["candidatesTokenCount"] as? Int ?? 0) : output.text
      outputAudio = output.audio
      thinking = max(0, metadata["thoughtsTokenCount"] as? Int ?? 0)
    }
  }
  enum Event: Sendable {
    case ready
    case usage(Usage)
    case userActivityStarted
    case transcript(turnID: String, text: String, final: Bool)
    case text(turnID: String, text: String)
    case audio(turnID: String, pcm: Data)
    case finished(turnID: String)
    case interrupted(turnID: String)
    case endRequested(turnID: String)
    case resumeHandle(String)
    case goAway
    case failed
  }
  typealias Receiver = @MainActor @Sendable (ConversationLiveSession, Event) -> Void
  private let queue = DispatchQueue(label: "com.heyintentive.conversation.live")
  private let token: String
  private let instructions: String
  private let resumeHandle: String?
  private let receive: Receiver
  private let factory: @Sendable (URL, DispatchQueue) -> RealtimeRawWebSocketTransport
  private var socket: RealtimeRawWebSocketTransport?
  private var ready = false
  private var stopped = false
  private var inputTurn: String?
  private var responseTurn: String?
  private var awaitingInterruptedBoundary = false
  private var inputAmbiguous = false
  private var inputActive = false
  private var latestUsage: Usage?
  private var reportedModelVersion: String?

  init(
    token: String, instructions: String, resumeHandle: String? = nil,
    factory: @escaping @Sendable (URL, DispatchQueue) -> RealtimeRawWebSocketTransport = {
      RawWebSocket(url: $0, queue: $1)
    }, receive: @escaping Receiver
  ) {
    self.token = token
    self.instructions = instructions
    self.resumeHandle = resumeHandle
    self.factory = factory
    self.receive = receive
  }

  func start() {
    queue.async {
      guard !self.stopped else { return }
      guard
        var url = URLComponents(
          string:
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
        )
      else {
        self.fail()
        return
      }
      url.queryItems = [URLQueryItem(name: "access_token", value: self.token)]
      guard let endpoint = url.url else {
        self.fail()
        return
      }
      let socket = self.factory(endpoint, self.queue)
      self.socket = socket
      socket.onOpen = { [weak self] in self?.sendSetup() }
      socket.onMessage = { [weak self] data in self?.handle(data) }
      socket.onClose = { [weak self] _, _ in self?.fail() }
      socket.onError = { [weak self] _ in self?.fail() }
      socket.connect()
    }
  }

  func stop() {
    queue.async {
      self.flushUsage()
      self.stopped = true
      self.ready = false
      self.socket?.close()
      self.socket = nil
    }
  }

  func beginUserTurn(_ turnID: String) {
    queue.async {
      guard !self.stopped, self.inputTurn != turnID else { return }
      if self.responseTurn != nil {
        self.awaitingInterruptedBoundary = true
        self.inputAmbiguous = true
      } else {
        self.inputAmbiguous = false
      }
      self.inputTurn = turnID
      self.inputActive = true
    }
  }

  func endUserTurn() { queue.async { self.inputActive = false } }

  func sendAudio(_ pcm: Data) {
    queue.async {
      guard self.ready, !self.stopped else { return }
      self.send([
        "realtimeInput": [
          "audio": [
            "data": pcm.base64EncodedString(), "mimeType": "audio/pcm;rate=16000",
          ]
        ]
      ])
    }
  }

  /// A proactive opening is sent exactly once. A failed or ambiguous send is
  /// never replayed by a reconnect or by the batch fallback.
  func initiate(_ text: String, turnID: String) {
    queue.async {
      guard self.ready, !self.stopped, self.responseTurn == nil else { return }
      self.inputTurn = turnID
      self.responseTurn = turnID
      self.send(["realtimeInput": ["text": text]])
    }
  }

  func sendUserMessage(_ text: String, imageJPEGBase64: String?, turnID: String) {
    queue.async {
      guard self.ready, !self.stopped else { return }
      if self.responseTurn != nil {
        self.awaitingInterruptedBoundary = true
        self.inputAmbiguous = true
      }
      self.inputTurn = turnID
      if !self.awaitingInterruptedBoundary { self.responseTurn = turnID }
      if let imageJPEGBase64 {
        self.send(["realtimeInput": ["video": ["data": imageJPEGBase64, "mimeType": "image/jpeg"]]])
      }
      self.send(["realtimeInput": ["text": text]])
    }
  }

  /// Only called at a quiet input/output boundary. The provider capability is
  /// separately acceptance-tested: transport delivery alone is not proof of silence.
  func appendPrivateContext(_ text: String) async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        guard self.ready, !self.stopped, self.responseTurn == nil,
          !self.awaitingInterruptedBoundary, !self.inputActive
        else {
          continuation.resume(returning: false)
          return
        }
        self.send([
          "clientContent": [
            "turns": [["role": "user", "parts": [["text": text]]]],
            "turnComplete": false,
          ]
        ]) { continuation.resume(returning: $0) }
      }
    }
  }

  private func sendSetup() {
    var resumption: [String: Any] = [:]
    if let resumeHandle { resumption["handle"] = resumeHandle }
    send([
      "setup": [
        "model": "models/\(RealtimeHubProvider.gemini.modelID)",
        "generationConfig": [
          "responseModalities": ["AUDIO"],
          "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": "Charon"]]],
        ],
        "systemInstruction": ["parts": [["text": instructions]]],
        "inputAudioTranscription": [:], "outputAudioTranscription": [:],
        "realtimeInputConfig": [
          "automaticActivityDetection": ["disabled": false],
          "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
        ],
        "tools": [
          [
            "functionDeclarations": [
              [
                "name": "end_conversation", "description": "End this conversation after your final spoken response.",
                "parameters": ["type": "OBJECT", "properties": [:]],
              ]
            ]
          ]
        ],
        "sessionResumption": resumption,
        "contextWindowCompression": ["slidingWindow": [:]],
      ]
    ])
  }

  private func handle(_ data: Data) {
    guard !stopped,
      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    let metadata = event["usageMetadata"] as? [String: Any]
    if let metadata { latestUsage = Usage(metadata) }
    let suppliedVersion = (event["modelVersion"] as? String) ?? (metadata?["modelVersion"] as? String)
    let safeVersion = suppliedVersion.flatMap {
      $0.range(of: #"^[A-Za-z0-9._/-]{1,128}$"#, options: .regularExpression) != nil ? $0 : nil
    }
    if let safeVersion, reportedModelVersion != safeVersion {
      reportedModelVersion = safeVersion
      log("ConversationLiveSession: actual_model_version=\(safeVersion)")
    } else if event["setupComplete"] != nil, reportedModelVersion == nil {
      log("ConversationLiveSession: actual_model_version=unavailable")
    }
    if event["setupComplete"] != nil {
      ready = true
      emit(.ready)
    }
    if let resume = event["sessionResumptionUpdate"] as? [String: Any],
      resume["resumable"] as? Bool == true, let handle = resume["newHandle"] as? String
    {
      emit(.resumeHandle(handle))
    }
    if event["goAway"] != nil { emit(.goAway) }
    if let activity = event["voiceActivity"] as? [String: Any],
      activity["type"] as? String == "ACTIVITY_START"
    {
      inputActive = true
      emit(.userActivityStarted)
    }
    if let calls = (event["toolCall"] as? [String: Any])?["functionCalls"] as? [[String: Any]] {
      for call in calls {
        guard call["name"] as? String == "end_conversation",
          (call["args"] as? [String: Any] ?? [:]).isEmpty,
          let turnID = responseTurn ?? inputTurn
        else {
          fail()
          return
        }
        emit(.endRequested(turnID: turnID))
        var response: [String: Any] = ["name": "end_conversation", "response": ["accepted": true]]
        if let id = call["id"] as? String { response["id"] = id }
        send(["toolResponse": ["functionResponses": [response]]])
      }
    }
    guard let content = event["serverContent"] as? [String: Any] else { return }
    if content["interrupted"] as? Bool == true {
      flushUsage()
      if let turnID = responseTurn { emit(.interrupted(turnID: turnID)) }
      responseTurn = nil
      awaitingInterruptedBoundary = false
      // Input transcriptions have no guaranteed ordering against realtime input.
      // Do not attach an unversioned late fragment to the interrupting user turn.
    }
    if let input = content["inputTranscription"] as? [String: Any],
      let text = input["text"] as? String, let turnID = inputTurn, !inputAmbiguous
    {
      emit(.transcript(turnID: turnID, text: text, final: input["finished"] as? Bool ?? false))
    }
    guard !awaitingInterruptedBoundary else {
      if content["turnComplete"] as? Bool == true {
        responseTurn = nil
        awaitingInterruptedBoundary = false
      }
      return
    }
    let parts = (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
    let outputText = (content["outputTranscription"] as? [String: Any])?["text"] as? String
    if responseTurn == nil, !parts.isEmpty || outputText != nil { responseTurn = inputTurn }
    guard let turnID = responseTurn else { return }
    if let outputText { emit(.text(turnID: turnID, text: outputText)) }
    for part in parts {
      if let inline = part["inlineData"] as? [String: Any],
        (inline["mimeType"] as? String)?.hasPrefix("audio/pcm") == true,
        let encoded = inline["data"] as? String, let pcm = Data(base64Encoded: encoded)
      {
        emit(.audio(turnID: turnID, pcm: pcm))
      }
    }
    if content["turnComplete"] as? Bool == true {
      flushUsage()
      responseTurn = nil
      inputActive = false
      emit(.finished(turnID: turnID))
    }
  }

  private func send(_ json: [String: Any], completion: (@Sendable (Bool) -> Void)? = nil) {
    guard !stopped, let socket,
      let data = try? JSONSerialization.data(withJSONObject: json),
      let text = String(data: data, encoding: .utf8)
    else {
      completion?(false)
      fail()
      return
    }
    socket.sendText(text) { [weak self] error in
      completion?(error == nil)
      guard error != nil, let self else { return }
      self.queue.async { self.fail() }
    }
  }

  private func emit(_ event: Event) {
    let receive = receive
    // Preserve wire event order when crossing onto the main actor.
    DispatchQueue.main.async { MainActor.assumeIsolated { receive(self, event) } }
  }

  private func flushUsage() {
    guard let usage = latestUsage else { return }
    latestUsage = nil
    emit(.usage(usage))
  }

  private func fail() {
    guard !stopped else { return }
    flushUsage()
    stopped = true
    ready = false
    socket?.close()
    socket = nil
    emit(.failed)
  }
}
