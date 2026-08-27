import Foundation

/// Service for real-time speech-to-text transcription.
/// Conversation capture: Python backend `/v4/listen` WebSocket used as transient speech transport.
/// PTT live streaming: Python backend `/v2/voice-message/transcribe-stream` WebSocket (transcription only).
/// PTT batch: Python backend `/v2/voice-message/transcribe` REST API.
/// Full stereo batch: removed with the retired Rust proxy.
class TranscriptionService: @unchecked Sendable {

  // MARK: - Types

  /// Streaming mode determines which backend endpoint and parameters are used.
  enum StreamingMode {
    /// Conversation capture via `/v4/listen` — transient speech segments and translations.
    case conversation
    /// PTT live transcription via `/v2/voice-message/transcribe-stream` — transcription only,
    /// no conversation lifecycle. Supports "finalize" text message for flush.
    case ptt

    var telemetryLabel: String {
      switch self {
      case .conversation: return "conversation"
      case .ptt: return "ptt"
      }
    }
  }

  /// Locally attached translation (lang code + translated text)
  struct BackendTranslation: Decodable, Equatable {
    let lang: String
    let text: String
  }

  /// The backend-selected provider for one pre-recorded PTT request.
  struct BatchTranscriptionResult: Equatable {
    let transcript: String?
    let provider: String?
    let model: String?
  }

  /// Canonical segment shared by cloud listen and on-device Parakeet ingestion.
  struct BackendSegment: Equatable {
    let segmentId: String
    let speakerId: Int
    let text: String
    let isUser: Bool
    let start: Double
    let end: Double
    let translations: [BackendTranslation]

    init(
      segmentId: String,
      speakerId: Int,
      text: String,
      isUser: Bool,
      start: Double,
      end: Double,
      translations: [BackendTranslation] = []
    ) {
      self.segmentId = segmentId
      self.speakerId = speakerId
      self.text = text
      self.isUser = isUser
      self.start = start
      self.end = end
      self.translations = translations
    }
  }

  private struct TransientSegmentWire: Decodable {
    let segmentId: String
    let speakerId: Int
    let text: String
    let start: Double
    let end: Double
  }

  private struct TransientSegmentsEnvelope: Decodable {
    let type: String
    let segments: [TransientSegmentWire]
  }

  private struct ListenServiceStatusWire: Decodable {
    let type: String
    let status: ListenServiceStatus
    let statusText: String?
    let outcome: String?
    let provider: String?
    let retryable: Bool?
    let reason: String?

    enum CodingKeys: String, CodingKey {
      case type
      case status
      case statusText = "status_text"
      case outcome
      case provider
      case retryable
      case reason
    }
  }

  private struct ListenTranslationWire: Decodable {
    let type: String
    let segmentId: String
    let language: String
    let text: String
  }

  private struct ListenFreemiumWire: Decodable {
    let type: String
    let remainingSeconds: Int
    let action: String

    enum CodingKeys: String, CodingKey {
      case type
      case remainingSeconds = "remaining_seconds"
      case action
    }
  }

  private struct ListenFairUseReviewWire: Decodable {
    let type: String
    let reviewId: String
    let trigger: String
    let windowSpeechMs: [String: Int]
    let thresholdsMs: [String: Int]
    let classifierContract: String
    let requestedAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
      case type, trigger
      case reviewId = "review_id"
      case windowSpeechMs = "window_speech_ms"
      case thresholdsMs = "thresholds_ms"
      case classifierContract = "classifier_contract"
      case requestedAt = "requested_at"
      case expiresAt = "expires_at"
    }
  }

  private struct ListenFairUseManagedCloudExhaustedWire: Decodable {
    let type: String
    let resetsAt: String
    let caseRef: String
    let supportEmail: String

    enum CodingKeys: String, CodingKey {
      case type
      case resetsAt = "resets_at"
      case caseRef = "case_ref"
      case supportEmail = "support_email"
    }
  }

  private struct PTTSegmentWire: Decodable {
    let id: String?
    let text: String
    let speaker_id: Int?
    let is_user: Bool
    let start: Double
    let end: Double
    let translations: [BackendTranslation]?
  }

  enum ListenServiceStatus: String, Decodable, Sendable {
    case ready
    case sttFailed = "stt_failed"
  }

  /// Exact retained event domain for `/v4/listen`; PTT has its own response shape.
  enum ListenEvent: Sendable {
    case serviceStatus(ListenServiceStatus)
    case translation(segmentId: String, language: String, text: String)
    case freemiumThresholdReached(remainingSeconds: Int, action: String)
    case fairUseReviewRequested(FairUseReviewRequest)
    case fairUseManagedCloudExhausted(FairUseManagedCloudExhaustion)

    var type: String {
      switch self {
      case .serviceStatus: "service_status"
      case .translation: "translation"
      case .freemiumThresholdReached: "freemium_threshold_reached"
      case .fairUseReviewRequested: "fair_use_review_requested"
      case .fairUseManagedCloudExhausted: "fair_use_managed_cloud_exhausted"
      }
    }
  }

  /// Callback types
  typealias BackendSegmentsHandler = ([BackendSegment]) -> Void
  typealias ListenEventHandler = (ListenEvent) -> Void
  typealias ErrorHandler = (Error) -> Void
  typealias ConnectionHandler = () -> Void

  enum TranscriptionError: LocalizedError {
    case missingBackendURL
    case connectionFailed(Error)
    case invalidResponse
    case invalidSessionConfiguration(String)
    case payloadTooLarge
    case webSocketError(String)

    var errorDescription: String? {
      switch self {
      case .missingBackendURL:
        return "Python backend URL is not configured for this build"
      case .connectionFailed(let error):
        return "Connection failed: \(error.localizedDescription)"
      case .invalidResponse:
        return "Invalid response from backend"
      case .invalidSessionConfiguration(let message):
        return "Invalid transcription session: \(message)"
      case .payloadTooLarge:
        return "Recording too long — keep it under 5 minutes"
      case .webSocketError(let message):
        return "WebSocket error: \(message)"
      }
    }
  }

  // MARK: - Properties

  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var webSocketDelegate: WebSocketConnectionDelegate?
  // Internal for @testable import access in unit tests
  var isConnected = false
  var shouldReconnect = false
  private(set) var managedCloudAudioQuiesced = false

  // Callbacks
  private var onBackendSegments: BackendSegmentsHandler?
  private var onListenEvent: ListenEventHandler?
  private var onError: ErrorHandler?
  private var onConnected: ConnectionHandler?
  private var onDisconnected: ConnectionHandler?

  // Configuration
  private let language: String
  private let sampleRate = 16000
  private let encoding = "linear16"
  private let channels = 1  // Always mono for Python backend streaming
  private let streamingMode: StreamingMode
  private let contextKeywords: [String]
  private let translationTarget: String?
  private let vocabulary: [String]

  /// Canonical backend base URL for transcription endpoints.
  /// Resolution order: explicit OMI_PYTHON_API_URL → the signed environment default.
  private static let pythonBackendBaseURL: String = DesktopBackendEnvironment.backendBaseURL()

  private static func sanitizedContextKeywords(_ keywords: [String]) -> [String] {
    let stopWords: Set<String> = [
      "about", "after", "again", "all", "also", "and", "app", "are", "ask", "back", "browser", "but", "can",
      "chat", "code", "done", "each", "for", "from", "get", "has", "have", "help", "here", "home", "how",
      "into", "just", "like", "means", "more", "next", "not", "now", "open", "question", "read", "right",
      "said", "screen", "sent", "show", "some", "task", "test", "text", "that", "the", "this", "time",
      "use", "user", "voice", "was", "what", "when", "window", "with", "you", "your",
    ]
    var seen = Set<String>()
    var result: [String] = []
    for keyword in ["Omi", "OMI"] + keywords {
      let normalized =
        keyword
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      let pattern = #"\b[A-Za-z][A-Za-z'\-]{1,31}\b"#
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let nsText = normalized as NSString
      let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsText.length))

      for match in matches {
        let term = nsText.substring(with: match.range)
        let key = term.lowercased()
        guard term.count >= 2 && term.count <= 32 else { continue }
        guard !stopWords.contains(key), !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(term)
        if result.count >= 40 {
          return result
        }
      }
    }
    return result
  }

  // Reconnection (internal for @testable import)
  var reconnectAttempts = 0
  let maxReconnectAttempts = 10
  private var reconnectTask: Task<Void, Never>?

  // Watchdog: detect stale connections where WebSocket dies silently
  private var watchdogTask: Task<Void, Never>?
  private var lastDataReceivedAt: Date?
  private let watchdogInterval: TimeInterval = 30.0  // Check every 30 seconds
  private let staleThreshold: TimeInterval = 60.0  // Reconnect if no data for 60 seconds

  // Audio buffering
  private var audioBuffer = Data()
  private let audioBufferSize = 3200  // ~100ms of 16kHz 16-bit audio (16000 * 2 * 0.1)
  private let audioBufferLock = NSLock()

  // MARK: - Initialization

  /// Initialize the transcription service for streaming.
  /// - Parameters:
  ///   - language: Language code for transcription (e.g., "en", "uk", "ru", "multi" for auto-detect)
  ///   - mode: Streaming mode — `.conversation` for `/v4/listen` (default), `.ptt` for `/v2/voice-message/transcribe-stream`
  init(
    language: String = "en",
    mode: StreamingMode = .conversation,
    contextKeywords: [String] = [],
    translationTarget: String? = nil,
    vocabulary: [String] = []
  ) throws {
    self.language = language
    self.streamingMode = mode
    self.contextKeywords = Self.sanitizedContextKeywords(contextKeywords)
    self.translationTarget = translationTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.vocabulary = try Self.validatedListenVocabulary(vocabulary)
    if mode == .conversation, let target = self.translationTarget,
      target.isEmpty || target == "auto" || target == "multi"
    {
      throw TranscriptionError.invalidSessionConfiguration("translation target is invalid")
    }
    log(
      "TranscriptionService: Initialized for \(mode == .conversation ? "/v4/listen" : "/v2/voice-message/transcribe-stream"), language=\(language), contextKeywords=\(self.contextKeywords.count)"
    )
  }

  private static func validatedListenVocabulary(_ rawTerms: [String]) throws -> [String] {
    guard rawTerms.count <= 100 else {
      throw TranscriptionError.invalidSessionConfiguration("vocabulary exceeds 100 terms")
    }
    var result: [String] = []
    var seen = Set<String>()
    for rawTerm in rawTerms {
      let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, term.count <= 256 else {
        throw TranscriptionError.invalidSessionConfiguration("vocabulary contains an invalid term")
      }
      if seen.insert(term.lowercased()).inserted {
        result.append(term)
      }
    }
    guard result.reduce(0, { $0 + $1.count }) <= 8_000 else {
      throw TranscriptionError.invalidSessionConfiguration("vocabulary exceeds 8,000 characters")
    }
    return result
  }

  /// Flush remaining audio and (for PTT mode) tell the backend to finalize transcription.
  /// PTT live mode calls this to get the final transcript segment before closing.
  /// In PTT mode, sends a "finalize" text message so the backend flushes any sub-threshold
  /// audio to managed STT and triggers provider finalization.
  /// In conversation mode, just flushes the local audio buffer (no "finalize" — `/v4/listen`
  /// relies on finalized utterances from the transient Modulate transport).
  func finishStream() {
    flushAudioBuffer()

    // Only PTT mode uses the "finalize" protocol — conversation mode (/v4/listen) doesn't support it
    guard streamingMode == .ptt else { return }
    guard isConnected, let webSocketTask = webSocketTask else { return }
    let message = URLSessionWebSocketTask.Message.string("finalize")
    webSocketTask.send(message) { error in
      if let error = error {
        logError("TranscriptionService: finishStream send error", error: error)
      }
    }
  }

  // MARK: - Public Methods (Streaming)

  /// Start the streaming transcription service (endpoint selected by `streamingMode`)
  func start(
    onSegments: @escaping BackendSegmentsHandler,
    onEvent: @escaping ListenEventHandler,
    onError: ErrorHandler? = nil,
    onConnected: ConnectionHandler? = nil,
    onDisconnected: ConnectionHandler? = nil
  ) {
    self.onBackendSegments = onSegments
    self.onListenEvent = onEvent
    self.onError = onError
    self.onConnected = onConnected
    self.onDisconnected = onDisconnected
    self.shouldReconnect = true
    self.managedCloudAudioQuiesced = false
    self.reconnectAttempts = 0

    connect()
  }

  /// Stop the transcription service
  func stop(discardBufferedAudio: Bool = false) {
    shouldReconnect = false
    reconnectTask?.cancel()
    reconnectTask = nil
    watchdogTask?.cancel()
    watchdogTask = nil
    managedCloudAudioQuiesced = false

    if discardBufferedAudio {
      audioBufferLock.lock()
      audioBuffer = Data()
      audioBufferLock.unlock()
    } else {
      // Ordinary turn finalization flushes its final partial chunk. Owner
      // replacement revokes that authority and discards it instead.
      flushAudioBuffer()
    }

    disconnect()
    onBackendSegments = nil
  }

  /// Stop provider-funded audio and reconnect ownership after a fair-use handoff while retaining
  /// the authenticated listen socket long enough for its server heartbeat to remain stable.
  func quiesceManagedCloudAudioForFairUse() {
    managedCloudAudioQuiesced = true
    shouldReconnect = false
    reconnectTask?.cancel()
    reconnectTask = nil
    audioBufferLock.lock()
    audioBuffer = Data()
    audioBufferLock.unlock()
  }

  /// Send audio data to the backend (buffered for efficiency)
  func sendAudio(_ data: Data) {
    guard isConnected, !managedCloudAudioQuiesced else { return }

    audioBufferLock.lock()
    audioBuffer.append(data)

    // Send when buffer is full enough
    if audioBuffer.count >= audioBufferSize {
      let chunk = audioBuffer
      audioBuffer = Data()
      audioBufferLock.unlock()
      sendAudioChunk(chunk)
    } else {
      audioBufferLock.unlock()
    }
  }

  /// Flush any remaining audio in the buffer
  private func flushAudioBuffer() {
    audioBufferLock.lock()
    let chunk = audioBuffer
    audioBuffer = Data()
    audioBufferLock.unlock()

    if !chunk.isEmpty {
      sendAudioChunk(chunk)
    }
  }

  /// Actually send an audio chunk to the backend
  private func sendAudioChunk(_ data: Data) {
    guard isConnected, let webSocketTask = webSocketTask else { return }

    let message = URLSessionWebSocketTask.Message.data(data)
    webSocketTask.send(message) { [weak self] error in
      if let error = error {
        logError("TranscriptionService: Send error", error: error)
        self?.handleDisconnection()
      }
    }
  }

  /// Check if connected
  var connected: Bool {
    return isConnected
  }

  // MARK: - Private Methods (Connection)

  private func connect() {
    // Test hook: simulate the cloud WS being unreachable (reconnects exhausted) to exercise
    // the on-device fallback. Toggle with `defaults write <bundle> forceCloudReconnectFail -bool true`.
    if UserDefaults.standard.bool(forKey: "forceCloudReconnectFail") {
      log("TranscriptionService: forceCloudReconnectFail set — simulating max reconnects reached")
      onError?(TranscriptionError.webSocketError("Max reconnect attempts reached"))
      return
    }
    // Always use Firebase auth for Python backend
    Task { [weak self] in
      guard let self = self else { return }
      do {
        let authService = await MainActor.run { AuthService.shared }
        let authHeader = try await authService.getAuthHeader(forceRefresh: self.reconnectAttempts > 0)
        self.connectToBackend(authHeader: authHeader)
      } catch {
        logError("TranscriptionService: Failed to get auth token", error: error)
        self.onError?(TranscriptionError.connectionFailed(error))
      }
    }
  }

  private func connectToBackend(authHeader: String) {
    let request: URLRequest
    do {
      request = try makeBackendWebSocketRequest(base: Self.pythonBackendBaseURL, authHeader: authHeader)
    } catch {
      log("TranscriptionService: Invalid Python backend URL")
      onError?(TranscriptionError.connectionFailed(error))
      return
    }

    log("TranscriptionService: Connecting to \(request.url?.absoluteString ?? "invalid")")

    // Create URLSession and WebSocket task
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 0  // No resource timeout for long-lived WebSocket
    let delegate = WebSocketConnectionDelegate()
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    let task = session.webSocketTask(with: request)
    webSocketDelegate = delegate
    urlSession = session
    webSocketTask = task

    delegate.onOpen = { [weak self, weak task] in
      guard let self,
        WebSocketConnectionAttempt.matches(task, current: self.webSocketTask)
      else { return }
      DispatchQueue.main.async { [weak self, weak task] in
        guard let self,
          WebSocketConnectionAttempt.matches(task, current: self.webSocketTask)
        else { return }
        self.handleWebSocketOpen()
      }
    }
    delegate.onClose = { [weak self, weak task] closeCode in
      guard let self,
        WebSocketConnectionAttempt.matches(task, current: self.webSocketTask)
      else { return }
      log("TranscriptionService: WebSocket closed with code \(closeCode.rawValue)")
      if self.isConnected {
        self.handleDisconnection()
      } else if self.shouldReconnect {
        self.cleanupAndReconnect()
      }
    }

    // Start the connection
    task.resume()

    // Start receiving messages
    receiveMessage()

    // Connect timeout: if still not connected after 10s, force reconnect
    Task { [weak self, weak task] in
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      guard let self,
        WebSocketConnectionAttempt.matches(task, current: self.webSocketTask),
        !self.isConnected,
        self.shouldReconnect
      else { return }
      log("TranscriptionService: Connect timeout (10s) — forcing reconnect")
      self.cleanupAndReconnect()
    }
  }

  func makeBackendWebSocketRequest(base: String, authHeader: String) throws -> URLRequest {
    var request = URLRequest(url: try makeBackendWebSocketURL(base: base))
    request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    request.setValue("macos", forHTTPHeaderField: "X-App-Platform")
    return request
  }

  /// Builds the exact authenticated WebSocket destination used by `connectToBackend`.
  /// Internal visibility keeps the transient conversation contract behaviorally testable.
  func makeBackendWebSocketURL(base: String) throws -> URL {
    let websocketBase =
      base
      .replacingOccurrences(of: "https://", with: "wss://")
      .replacingOccurrences(of: "http://", with: "ws://")
    let normalizedBase = websocketBase.hasSuffix("/") ? String(websocketBase.dropLast()) : websocketBase

    let path: String
    let queryItems: [URLQueryItem]

    switch streamingMode {
    case .conversation:
      // Immutable transient-session snapshot; audio format is fixed by the route contract.
      path = "/v4/listen"
      var items = [URLQueryItem(name: "language", value: language == "multi" ? "auto" : language)]
      if let translationTarget {
        items.append(URLQueryItem(name: "translation_target", value: translationTarget))
      }
      items.append(contentsOf: vocabulary.map { URLQueryItem(name: "vocabulary", value: $0) })
      queryItems = items
    case .ptt:
      // PTT-only transcription — no conversation lifecycle
      path = "/v2/voice-message/transcribe-stream"
      var items = [
        URLQueryItem(name: "language", value: language),
        URLQueryItem(name: "sample_rate", value: String(sampleRate)),
        URLQueryItem(name: "codec", value: encoding),
        URLQueryItem(name: "channels", value: String(channels)),
      ]
      if !contextKeywords.isEmpty {
        items.append(URLQueryItem(name: "keywords", value: contextKeywords.joined(separator: ",")))
      }
      queryItems = items
    }

    guard var components = URLComponents(string: "\(normalizedBase)\(path)") else {
      throw TranscriptionError.invalidResponse
    }

    components.queryItems = queryItems

    guard let url = components.url else {
      throw TranscriptionError.invalidResponse
    }
    return url
  }

  private func handleWebSocketOpen() {
    guard !isConnected else { return }
    isConnected = true
    reconnectAttempts = 0
    lastDataReceivedAt = Date()
    log("TranscriptionService: WebSocket opened (handshake complete)")
    startWatchdog()
    onConnected?()
  }

  /// Start watchdog to detect stale connections (WebSocket dies silently)
  private func startWatchdog() {
    watchdogTask?.cancel()
    watchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(self?.watchdogInterval ?? 30.0) * 1_000_000_000)
        guard !Task.isCancelled, let self = self, self.isConnected else { break }

        if let lastData = self.lastDataReceivedAt,
          Date().timeIntervalSince(lastData) > self.staleThreshold
        {
          log(
            "TranscriptionService: Watchdog detected stale connection (no data for \(String(format: "%.0f", Date().timeIntervalSince(lastData)))s) - forcing reconnect"
          )
          self.handleDisconnection()
        }
      }
    }
  }

  private func disconnect() {
    isConnected = false
    watchdogTask?.cancel()
    watchdogTask = nil
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    webSocketDelegate = nil
    log("TranscriptionService: Disconnected")
    onDisconnected?()
  }

  func handleDisconnection() {
    guard isConnected else { return }

    isConnected = false
    watchdogTask?.cancel()
    watchdogTask = nil
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    webSocketDelegate = nil
    onDisconnected?()

    // Attempt reconnection if enabled
    if shouldReconnect && reconnectAttempts < maxReconnectAttempts {
      reconnectAttempts += 1
      let delay = min(pow(2.0, Double(reconnectAttempts)), 32.0)  // Exponential backoff, max 32s
      log("TranscriptionService: Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

      reconnectTask = Task {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled, self.shouldReconnect else { return }
        self.connect()
      }
    } else if reconnectAttempts >= maxReconnectAttempts {
      log(
        "TranscriptionService: Max reconnect attempts reached "
          + "(failure_class=ws_reconnect_exhausted recovery_action=surface_error recovery_result=exhausted)")
      DesktopDiagnosticsManager.shared.recordTranscriptionWsReconnectExhausted(
        reconnectAttempts: reconnectAttempts,
        streamingMode: streamingMode.telemetryLabel
      )
      onError?(TranscriptionError.webSocketError("Max reconnect attempts reached"))
    }
  }

  /// Cleanup a failed/pending connection and schedule reconnect.
  /// Unlike handleDisconnection(), this works even when isConnected is false (pre-handshake failures).
  func cleanupAndReconnect() {
    isConnected = false
    webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    webSocketDelegate = nil

    guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
      if reconnectAttempts >= maxReconnectAttempts {
        log(
          "TranscriptionService: Max reconnect attempts reached (pre-connect) "
            + "(failure_class=ws_reconnect_exhausted recovery_action=surface_error recovery_result=exhausted)")
        DesktopDiagnosticsManager.shared.recordTranscriptionWsReconnectExhausted(
          reconnectAttempts: reconnectAttempts,
          streamingMode: streamingMode.telemetryLabel
        )
        onError?(TranscriptionError.webSocketError("Max reconnect attempts reached"))
      }
      return
    }

    reconnectAttempts += 1
    let delay = min(pow(2.0, Double(reconnectAttempts)), 32.0)
    log("TranscriptionService: Reconnecting in \(delay)s (attempt \(reconnectAttempts), pre-connect failure)")

    reconnectTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled, self.shouldReconnect else { return }
      self.connect()
    }
  }

  private func receiveMessage() {
    webSocketTask?.receive { [weak self] result in
      guard let self = self else { return }

      switch result {
      case .success(let message):
        self.handleMessage(message)
        // Continue receiving
        self.receiveMessage()

      case .failure(let error):
        guard self.isConnected else { return }
        logError("TranscriptionService: Receive error", error: error)
        self.handleDisconnection()
      }
    }
  }

  private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    // Track that we received data (for watchdog stale detection)
    lastDataReceivedAt = Date()

    switch message {
    case .string(let text):
      parseBackendResponse(text)
    case .data(let data):
      if let text = String(data: data, encoding: .utf8) {
        parseBackendResponse(text)
      }
    @unknown default:
      break
    }
  }

  /// Parse response from Python backend transcription WebSocket.
  /// Conversation mode accepts only the typed transient envelope/events. PTT retains its
  /// independent array response contract. Plain text `ping` is the listen heartbeat.
  /// Visible to tests (`@testable import`) so ListenProtocolTests can drive real callback dispatch.
  func parseBackendResponse(_ text: String) {
    // Handle heartbeat ping
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "ping" {
      if managedCloudAudioQuiesced, let webSocketTask {
        // A zero-length binary frame updates the listen runtime's client-activity
        // clock without forwarding provider audio or consuming fair-use budget.
        webSocketTask.send(.data(Data())) { [weak self] error in
          if error != nil { self?.handleDisconnection() }
        }
      }
      return
    }

    guard let data = text.data(using: .utf8) else { return }

    do {
      let json = try JSONSerialization.jsonObject(with: data)

      switch streamingMode {
      case .ptt:
        guard json is [[String: Any]] else { return }
        let wireSegments = try JSONDecoder().decode([PTTSegmentWire].self, from: data)
        let segments = wireSegments.map { wire in
          BackendSegment(
            segmentId: UUID(uuidString: wire.id ?? "")?.uuidString.lowercased()
              ?? UUID().uuidString.lowercased(),
            speakerId: max(0, wire.speaker_id ?? 0),
            text: wire.text,
            isUser: wire.is_user,
            start: wire.start,
            end: wire.end,
            translations: wire.translations ?? [])
        }
        if !segments.isEmpty { onBackendSegments?(segments) }

      case .conversation:
        guard let dict = json as? [String: Any], let type = dict["type"] as? String else { return }
        if type == "segments" {
          guard Set(dict.keys) == ["type", "segments"],
            let rawSegments = dict["segments"] as? [[String: Any]],
            !rawSegments.isEmpty,
            rawSegments.allSatisfy({
              Set($0.keys) == ["segmentId", "speakerId", "text", "start", "end"]
            })
          else { return }
          let envelope = try JSONDecoder().decode(TransientSegmentsEnvelope.self, from: data)
          guard envelope.type == "segments" else { return }
          let segments = envelope.segments.compactMap { wire -> BackendSegment? in
            guard UUID(uuidString: wire.segmentId) != nil,
              wire.speakerId >= 0,
              !wire.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              wire.start >= 0,
              wire.end >= wire.start
            else { return nil }
            return BackendSegment(
              segmentId: wire.segmentId.lowercased(),
              speakerId: wire.speakerId,
              text: wire.text,
              isUser: false,
              start: wire.start,
              end: wire.end)
          }
          guard segments.count == envelope.segments.count else { return }
          onBackendSegments?(segments)
          return
        }

        switch type {
        case "service_status":
          let wire = try JSONDecoder().decode(ListenServiceStatusWire.self, from: data)
          guard wire.type == "service_status" else { return }
          switch wire.status {
          case .ready:
            guard Set(dict.keys) == ["type", "status"] else { return }
          case .sttFailed:
            guard
              Set(dict.keys) == [
                "type", "status", "status_text", "outcome", "provider", "retryable", "reason",
              ],
              !(wire.statusText ?? "").isEmpty,
              !(wire.outcome ?? "").isEmpty,
              !(wire.provider ?? "").isEmpty,
              wire.retryable != nil,
              !(wire.reason ?? "").isEmpty
            else { return }
          }
          onListenEvent?(.serviceStatus(wire.status))
        case "translation":
          guard Set(dict.keys) == ["type", "segmentId", "language", "text"] else { return }
          let wire = try JSONDecoder().decode(ListenTranslationWire.self, from: data)
          guard wire.type == "translation",
            UUID(uuidString: wire.segmentId) != nil,
            !wire.language.isEmpty,
            !wire.text.isEmpty
          else { return }
          onListenEvent?(
            .translation(
              segmentId: wire.segmentId.lowercased(), language: wire.language, text: wire.text))
        case "freemium_threshold_reached":
          guard Set(dict.keys) == ["type", "remaining_seconds", "action"] else { return }
          let wire = try JSONDecoder().decode(ListenFreemiumWire.self, from: data)
          guard wire.type == "freemium_threshold_reached", wire.remainingSeconds >= 0,
            !wire.action.isEmpty
          else { return }
          onListenEvent?(
            .freemiumThresholdReached(
              remainingSeconds: wire.remainingSeconds, action: wire.action))
        case "fair_use_review_requested":
          guard
            Set(dict.keys) == [
              "type", "review_id", "trigger", "window_speech_ms", "thresholds_ms", "classifier_contract",
              "requested_at", "expires_at",
            ]
          else { return }
          let wire = try JSONDecoder().decode(ListenFairUseReviewWire.self, from: data)
          let expectedWindowKeys: Set<String> = ["daily_ms", "three_day_ms", "weekly_ms"]
          let formatter = ISO8601DateFormatter()
          guard wire.type == "fair_use_review_requested",
            UUID(uuidString: wire.reviewId) != nil,
            ["daily", "3day", "weekly"].contains(wire.trigger),
            Set(wire.windowSpeechMs.keys) == expectedWindowKeys,
            Set(wire.thresholdsMs.keys) == expectedWindowKeys,
            wire.windowSpeechMs.values.allSatisfy({ $0 >= 0 }),
            wire.thresholdsMs.values.allSatisfy({ $0 > 0 }),
            wire.classifierContract == "openai/gpt-5.1:prompt-v2",
            let requestedAt = formatter.date(from: wire.requestedAt),
            let expiresAt = formatter.date(from: wire.expiresAt),
            expiresAt > requestedAt
          else { return }
          onListenEvent?(
            .fairUseReviewRequested(
              FairUseReviewRequest(
                reviewId: wire.reviewId.lowercased(), trigger: wire.trigger,
                windowSpeechMs: wire.windowSpeechMs, thresholdsMs: wire.thresholdsMs,
                classifierContract: wire.classifierContract, requestedAt: requestedAt, expiresAt: expiresAt)))
        case "fair_use_managed_cloud_exhausted":
          guard
            Set(dict.keys) == ["type", "resets_at", "case_ref", "support_email"]
          else { return }
          let wire = try JSONDecoder().decode(ListenFairUseManagedCloudExhaustedWire.self, from: data)
          let formatter = ISO8601DateFormatter()
          guard wire.type == "fair_use_managed_cloud_exhausted",
            formatter.date(from: wire.resetsAt) != nil,
            wire.caseRef.isEmpty || wire.caseRef.range(of: #"^FU-[A-F0-9]{12}$"#, options: .regularExpression) != nil,
            wire.supportEmail == "support@heyintentive.com"
          else { return }
          onListenEvent?(
            .fairUseManagedCloudExhausted(
              FairUseManagedCloudExhaustion(resetsAt: wire.resetsAt, caseRef: wire.caseRef)))
        default:
          return
        }
      }
    } catch {
      logError("TranscriptionService: Parse error", error: error)
    }
  }
}

final class WebSocketConnectionDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
  var onOpen: (() -> Void)?
  var onClose: ((URLSessionWebSocketTask.CloseCode) -> Void)?

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onOpen?()
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onClose?(closeCode)
  }
}

enum WebSocketConnectionAttempt {
  static func matches(_ candidate: URLSessionWebSocketTask?, current: URLSessionWebSocketTask?) -> Bool {
    guard let candidate, let current else { return false }
    return candidate === current
  }
}

// MARK: - Batch (Pre-Recorded) Transcription (PTT only)

extension TranscriptionService {
  /// Transcribe a complete audio buffer using the Python backend `/v2/voice-message/transcribe`.
  /// Returns the transcript plus the provider/model selected by the backend.
  static func batchTranscribe(
    audioData: Data,
    language: String = "en",
    contextKeywords: [String] = []
  ) async throws -> BatchTranscriptionResult {
    // Always use Firebase auth + Python backend
    let authService = await MainActor.run { AuthService.shared }
    let authHeader = try await authService.getAuthHeader()
    let baseURLString = "\(pythonBackendBaseURL)v2/voice-message/transcribe"

    guard var components = URLComponents(string: baseURLString) else {
      throw TranscriptionError.connectionFailed(NSError(domain: "Invalid backend URL", code: -1))
    }
    let sanitizedKeywords = sanitizedContextKeywords(contextKeywords)
    var queryItems = [
      URLQueryItem(name: "language", value: language),
      URLQueryItem(name: "sample_rate", value: "16000"),
      URLQueryItem(name: "encoding", value: "linear16"),
      URLQueryItem(name: "channels", value: "1"),
    ]
    if !sanitizedKeywords.isEmpty {
      queryItems.append(URLQueryItem(name: "keywords", value: sanitizedKeywords.joined(separator: ",")))
    }
    components.queryItems = queryItems

    guard let url = components.url else {
      throw TranscriptionError.connectionFailed(NSError(domain: "Invalid URL", code: -1))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.httpBody = audioData

    log(
      "TranscriptionService: Batch transcribing \(audioData.count) bytes via Python backend, contextKeywords=\(sanitizedKeywords.count)"
    )

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
      let body = String(data: data, encoding: .utf8) ?? "no body"
      logError("TranscriptionService: Batch transcription failed with status \(statusCode): \(body)", error: nil)
      if statusCode == 413 {
        throw TranscriptionError.payloadTooLarge
      }
      throw TranscriptionError.invalidResponse
    }

    // Parse Python backend response, including the provider selected by routed STT.
    let json = try JSONDecoder().decode(PythonTranscribeResponse.self, from: data)
    let transcript = json.transcript.isEmpty ? nil : json.transcript
    let result = BatchTranscriptionResult(
      transcript: transcript,
      provider: json.stt_provider,
      model: json.stt_model)
    log(
      "TranscriptionService: Batch transcription result provider=\(result.provider ?? "unknown") "
        + "model=\(result.model ?? "unknown") transcriptCharacters=\(transcript?.count ?? 0)")
    return result
  }

}

/// Response model for Python backend `/v2/voice-message/transcribe` (batch PTT)
private struct PythonTranscribeResponse: Decodable {
  let transcript: String
  let language: String?
  let stt_provider: String?
  let stt_model: String?
}
