import Foundation

/// Boxes a non-Sendable `[String: Any]` event payload so it can be sent into a
/// `@MainActor` task. The dictionary is built once and only read on the main
/// actor, so the unchecked Sendable conformance is sound.
private struct EventPayloadBox: @unchecked Sendable {
  let value: [String: Any]
}

/// Memory extraction assistant that identifies facts and wisdom from screen content
actor MemoryAssistant: ProactiveAssistant {
  typealias ExtractionOverride =
    @Sendable (_ jpegData: Data, _ appName: String) async throws -> MemoryExtractionResult?

  // MARK: - ProactiveAssistant Protocol

  nonisolated let identifier = "memory-extraction"
  nonisolated let displayName = "Memory Extractor"

  nonisolated static func discoveryEnabled(settingsEnabled: Bool, notificationsEnabled: Bool) -> Bool {
    settingsEnabled && notificationsEnabled
  }

  var isEnabled: Bool {
    get async {
      await MainActor.run {
        // Gate the Gemini screen analysis on notifications (off by default) — no
        // notification, no Gemini call. Re-enabling notifications resumes analysis.
        Self.discoveryEnabled(
          settingsEnabled: MemoryAssistantSettings.shared.isEnabled,
          notificationsEnabled: MemoryAssistantSettings.shared.notificationsEnabled
        )
      }
    }
  }

  // MARK: - Properties

  private let geminiClient: GeminiClient?
  private let extractionOverride: ExtractionOverride?
  private let durabilityPipeline: MemoryAssistantDurabilityPipeline
  private var isRunning = false
  private var lastAnalysisTime: Date = .distantPast
  private var previousMemories: [ExtractedMemory] = []  // Last 20 extracted memories for deduplication
  private let maxPreviousMemories = 20
  private var currentApp: String?
  private var pendingFrame: OwnerBoundCapturedFrame?
  private var processingTask: Task<Void, Never>?
  private let frameSignal: AsyncStream<Void>
  private let frameSignalContinuation: AsyncStream<Void>.Continuation

  /// Get the current system prompt from settings (accessed on MainActor for thread safety)
  private var systemPrompt: String {
    get async {
      await MainActor.run {
        MemoryAssistantSettings.shared.analysisPrompt
      }
    }
  }

  /// Get the extraction interval from settings
  private var extractionInterval: TimeInterval {
    get async {
      await MainActor.run {
        MemoryAssistantSettings.shared.extractionInterval
      }
    }
  }

  /// Get the minimum confidence threshold from settings
  private var minConfidence: Double {
    get async {
      await MainActor.run {
        MemoryAssistantSettings.shared.minConfidence
      }
    }
  }

  // MARK: - Initialization

  init(apiKey: String? = nil) throws {
    // Use Gemini Flash for memory extraction (text+vision, no tool loop — Flash-safe)
    self.geminiClient = try GeminiClient(apiKey: apiKey)
    self.extractionOverride = nil
    self.durabilityPipeline = MemoryAssistantDurabilityPipeline(
      runner: MemoryAssistantProductionDurability(operations: MemoryAssistantLiveDurabilityOperations())
    )

    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.frameSignal = stream
    self.frameSignalContinuation = continuation

    // Start processing loop
    Task {
      await self.startProcessing()
    }
  }

  /// Hermetic analysis-attempt initializer. It uses the same `processFrame`
  /// catch and analytics boundary as production without constructing a live
  /// Gemini client or starting the background frame loop.
  init(
    extractionOverride: @escaping ExtractionOverride,
    durabilityRunner: any MemoryAssistantDurabilityRunning
  ) {
    self.geminiClient = nil
    self.extractionOverride = extractionOverride
    self.durabilityPipeline = MemoryAssistantDurabilityPipeline(runner: durabilityRunner)

    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.frameSignal = stream
    self.frameSignalContinuation = continuation
  }

  // MARK: - Processing

  private func startProcessing() {
    isRunning = true
    processingTask = Task {
      await processLoop()
    }
  }

  private func processLoop() async {
    log("Memory assistant started")

    for await _ in frameSignal {
      guard isRunning else { break }
      guard pendingFrame != nil else { continue }

      // Wait until the extraction interval has passed
      let interval = await extractionInterval
      let timeSinceLastAnalysis = Date().timeIntervalSince(lastAnalysisTime)
      if timeSinceLastAnalysis < interval {
        let remaining = interval - timeSinceLastAnalysis
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
      }

      // Grab the latest frame (may have been updated or cleared during sleep)
      guard let ownerBoundFrame = pendingFrame else { continue }
      let waited = Date().timeIntervalSince(lastAnalysisTime)
      log("Memory: Starting analysis (interval: \(Int(interval))s, waited: \(Int(waited))s)")
      pendingFrame = nil
      lastAnalysisTime = Date()
      await processFrame(
        ownerBoundFrame.frame,
        authorizationSnapshot: ownerBoundFrame.authorizationSnapshot)
    }

    log("Memory assistant stopped")
  }

  // MARK: - ProactiveAssistant Protocol Methods

  func shouldAnalyze(frameNumber: Int, timeSinceLastAnalysis: TimeInterval) -> Bool {
    // Memory assistant analyzes less frequently - every N seconds
    // The actual interval is checked in the processing loop
    // Here we just accept frames to store the latest one
    return true
  }

  func analyze(
    frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> AssistantResult? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return nil }
    // Skip apps excluded from memory extraction (built-in + user's custom list)
    let excluded = await MainActor.run { MemoryAssistantSettings.shared.isAppExcluded(frame.appName) }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return nil }
    if excluded {
      log("Memory: Skipping excluded app '\(frame.appName)'")
      return nil
    }

    // Store the latest frame - we'll process it when the interval has passed
    let hadPending = pendingFrame != nil
    pendingFrame = OwnerBoundCapturedFrame(
      frame: frame,
      authorizationSnapshot: authorizationSnapshot)
    if !hadPending {
      log("Memory: Received frame from \(frame.appName), queued for analysis")
    }
    // Signal the processing loop that a frame is available
    frameSignalContinuation.yield()
    return nil
  }

  func handleResult(
    _ result: AssistantResult,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    sendEvent: @escaping @Sendable (String, [String: Any]) -> Void
  ) async {
    // This method is required by protocol but we use handleResultWithScreenshot instead
    guard let memoryResult = result as? MemoryExtractionResult else { return }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    await handleResultWithScreenshot(
      memoryResult,
      authorizationSnapshot: authorizationSnapshot,
      screenshotId: nil,
      sendEvent: sendEvent
    )
  }

  /// Handle result with screenshot ID for SQLite storage
  private func handleResultWithScreenshot(
    _ memoryResult: MemoryExtractionResult,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    screenshotId: Int64?,
    windowTitle: String? = nil,
    sendEvent: @escaping (String, [String: Any]) -> Void
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    // Check if AI found new memories
    guard memoryResult.hasNewMemory, !memoryResult.memories.isEmpty else {
      await recordAnalysisOutcome(.noNewMemory, authorizationSnapshot: authorizationSnapshot)
      return
    }

    // Get min confidence threshold
    let threshold = await minConfidence
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

    // Only process the first memory (max 1 per analysis)
    guard let memory = memoryResult.memories.first else { return }

    let confidencePercent = Int(memory.confidence * 100)

    // Check confidence threshold
    guard memory.confidence >= threshold else {
      log("Memory: [\(confidencePercent)% < \(Int(threshold * 100))%] Filtered: \"\(memory.content)\"")
      await recordAnalysisOutcome(
        .filteredLowConfidence,
        confidence: memory.confidence,
        authorizationSnapshot: authorizationSnapshot)
      return
    }

    log("Memory: [\(confidencePercent)% conf.] [\(memory.category.rawValue)] \"\(memory.content)\"")

    let durability = await durabilityPipeline.persistAndEmit(
      MemoryAssistantDurabilityRequest(
        memory: memory,
        screenshotId: screenshotId,
        contextSummary: memoryResult.contextSummary,
        windowTitle: windowTitle,
        authorizationSnapshot: authorizationSnapshot
      ),
      confidence: memory.confidence
    )
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    // A failed insert must never be reported as the historical extraction
    // success. The pipeline already recorded exactly
    // one closed analysis terminal (and historical success where appropriate).
    guard durability.shouldEmitMemoryExtracted else { return }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

    // A failed or revoked write must not leave a phantom entry in the prompt's
    // deduplication history. Publish the accepted memory to that cache only
    // after the canonical row is durable.
    previousMemories.insert(memory, at: 0)
    if previousMemories.count > maxPreviousMemories {
      previousMemories.removeLast()
    }

    // Send notification if enabled
    let notificationsEnabled = await MainActor.run {
      MemoryAssistantSettings.shared.notificationsEnabled
    }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    if notificationsEnabled {
      await sendMemoryNotification(
        authorizationSnapshot: authorizationSnapshot,
        memory: memory,
        result: memoryResult,
        windowTitle: windowTitle
      )
    }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

    // Send event to Flutter
    sendEvent(
      "memoryExtracted",
      [
        "assistant": identifier,
        "memory": memory.toDictionary(),
        "contextSummary": memoryResult.contextSummary,
      ])
  }

  /// Record one analysis-outcome telemetry event, gated on the owner not having
  /// switched mid-analysis (a prior owner's attempt must never be attributed to the
  /// current PostHog identity). Supplements — never replaces — `Memory Extracted`,
  /// which continues to fire only on the local-persistence success terminal below.
  private func recordAnalysisOutcome(
    _ outcome: MemoryAssistantTelemetry.AnalysisOutcome,
    confidence: Double? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    await MainActor.run {
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      AnalyticsManager.shared.memoryAssistantAnalysisRun(outcome: outcome, confidence: confidence)
    }
  }

  /// Send a notification for the extracted memory
  private func sendMemoryNotification(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    memory: ExtractedMemory,
    result: MemoryExtractionResult,
    windowTitle: String?
  ) async {
    let title = memory.category == .interesting ? "Wisdom Captured" : "Memory Saved"
    let message = "New memory: \(memory.content)"
    let context = FloatingBarNotificationContext(
      sourceTitle: title,
      assistantId: identifier,
      sourceApp: memory.sourceApp.isEmpty ? nil : memory.sourceApp,
      windowTitle: windowTitle,
      contextSummary: result.contextSummary,
      currentActivity: result.currentActivity,
      reasoning: nil,
      detail: memory.content
    )

    await MainActor.run {
      NotificationService.shared.sendNotification(
        ownerID: authorizationSnapshot.ownerID,
        title: title,
        message: message,
        assistantId: identifier,
        context: context,
        authorizationSnapshot: authorizationSnapshot
      )
    }
  }

  func onAppSwitch(
    newApp: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    if newApp != currentApp {
      if let currentApp = currentApp {
        log("Memory: APP SWITCH: \(currentApp) -> \(newApp)")
      } else {
        log("Memory: Active app: \(newApp)")
      }
      currentApp = newApp
      // Don't clear previous memories on app switch - we want to track across apps
    }
  }

  func clearPendingWork(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    clearPendingWorkForOwnerReset()
  }

  private func clearPendingWorkForOwnerReset() {
    pendingFrame = nil
    log("Memory: Cleared pending frame")
  }

  func resetForOwnerChange() async {
    clearPendingWorkForOwnerReset()
    previousMemories.removeAll()
    currentApp = nil
    lastAnalysisTime = .distantPast
  }

  func stop() async {
    isRunning = false
    frameSignalContinuation.finish()
    processingTask?.cancel()
    pendingFrame = nil
  }

  // MARK: - Analysis

  func processFrame(
    _ frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    let enabled = await isEnabled
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    guard enabled else {
      log("Memory: Skipping analysis (disabled)")
      return
    }

    log("Memory: Analyzing frame from \(frame.appName)...")
    do {
      guard
        let result = try await extractMemories(
          from: frame.jpegData,
          appName: frame.appName,
          authorizationSnapshot: authorizationSnapshot)
      else {
        log("Memory: Analysis returned no result")
        await recordAnalysisOutcome(
          .analysisFailed,
          authorizationSnapshot: authorizationSnapshot)
        return
      }
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      log(
        "Memory: Analysis complete - hasNewMemory: \(result.hasNewMemory), count: \(result.memories.count), context: \(result.contextSummary)"
      )

      // Handle the result with screenshot ID for SQLite storage
      await handleResultWithScreenshot(
        result,
        authorizationSnapshot: authorizationSnapshot,
        screenshotId: frame.screenshotId,
        windowTitle: frame.windowTitle
      ) { type, data in
        let payload = EventPayloadBox(value: data)
        Task { @MainActor in
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          AssistantCoordinator.shared.sendEvent(
            type: type,
            data: payload.value,
            authorizationSnapshot: authorizationSnapshot)
        }
      }
    } catch {
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      logError("Memory extraction error", error: error)
      await recordAnalysisOutcome(
        .analysisFailed,
        authorizationSnapshot: authorizationSnapshot)
    }
  }

  private func extractMemories(
    from jpegData: Data,
    appName: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> MemoryExtractionResult? {
    if let extractionOverride {
      return try await extractionOverride(jpegData, appName)
    }
    guard let geminiClient else {
      return nil
    }

    // Build context with previous memories for deduplication
    var prompt = "Analyze this screenshot from \(appName).\n\n"

    if !previousMemories.isEmpty {
      prompt += "RECENTLY EXTRACTED MEMORIES (do not re-extract these or semantically similar ones):\n"
      for (index, memory) in previousMemories.enumerated() {
        prompt += "\(index + 1). [\(memory.category.rawValue)] \(memory.content)\n"
      }
      prompt += "\nLook for NEW memories that are NOT already in the list above."
    } else {
      prompt += "Look for memories to extract (system facts about the user, or interesting wisdom from others)."
    }

    // Get current system prompt from settings
    let currentSystemPrompt = await systemPrompt
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }

    // Build response schema for memory extraction
    let memoryProperties: [String: GeminiRequest.GenerationConfig.ResponseSchema.Property] = [
      "content": .init(type: "string", description: "The memory content (max 15 words)"),
      "category": .init(type: "string", enum: ["system", "interesting"], description: "Memory category"),
      "source_app": .init(type: "string", description: "App where memory was found"),
      "confidence": .init(type: "number", description: "Confidence score 0.0-1.0"),
    ]

    let responseSchema = GeminiRequest.GenerationConfig.ResponseSchema(
      type: "object",
      properties: [
        "has_new_memory": .init(type: "boolean", description: "True if new memories were found"),
        "memories": .init(
          type: "array",
          description: "Array of extracted memories (0-3 max)",
          items: .init(
            type: "object",
            properties: memoryProperties,
            required: ["content", "category", "source_app", "confidence"]
          )
        ),
        "context_summary": .init(type: "string", description: "Brief summary of what user is looking at"),
        "current_activity": .init(type: "string", description: "High-level description of user's activity"),
      ],
      required: ["has_new_memory", "memories", "context_summary", "current_activity"]
    )

    let responseText = try await geminiClient.sendRequest(
      prompt: prompt,
      imageData: jpegData,
      systemPrompt: currentSystemPrompt,
      responseSchema: responseSchema,
      authorizationSnapshot: authorizationSnapshot
    )

    return try JSONDecoder().decode(MemoryExtractionResult.self, from: Data(responseText.utf8))
  }
}
