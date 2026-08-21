import Foundation
import OmiSupport

/// Focus monitoring assistant that detects when users are distracted
actor FocusAssistant: ProactiveAssistant {
  typealias AnalysisOverride =
    @Sendable (
      _ jpegData: Data,
      _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
    ) async throws -> ScreenAnalysis?
  typealias FocusSessionPersister =
    @Sendable (
      _ record: FocusSessionRecord,
      _ authorization: LocalMutationAuthorization
    ) async throws -> FocusSessionRecord

  // MARK: - ProactiveAssistant Protocol

  nonisolated let identifier = "focus"
  nonisolated let displayName = "Focus Monitor"

  var isEnabled: Bool {
    get async {
      await MainActor.run {
        // Gate the Gemini screen analysis on notifications (off by default) — no
        // notification, no Gemini call. Re-enabling notifications resumes analysis.
        FocusAssistantSettings.shared.isEnabled
          && FocusAssistantSettings.shared.notificationsEnabled
      }
    }
  }

  // MARK: - Properties

  private let geminiClient: GeminiClient?
  private let analysisOverride: AnalysisOverride?
  private let focusSessionPersister: FocusSessionPersister
  private let onAlert: @Sendable (String, RuntimeOwnerAuthorizationSnapshot) -> Void
  private let onStatusChange: (@Sendable (FocusStatus, RuntimeOwnerAuthorizationSnapshot) -> Void)?
  private let onRefocus: (@Sendable (RuntimeOwnerAuthorizationSnapshot) -> Void)?
  private let onDistraction: (@Sendable (RuntimeOwnerAuthorizationSnapshot) -> Void)?

  private var isRunning = false
  private let frameStream: AsyncStream<OwnerBoundCapturedFrame>
  private let frameContinuation: AsyncStream<OwnerBoundCapturedFrame>.Continuation
  private var analysisHistory: [ScreenAnalysis] = []
  private let maxHistorySize = 10
  private var lastStatus: FocusStatus?
  private var lastProcessedFrameNum = 0
  private var processingTask: Task<Void, Never>?
  private var pendingTasks: Set<Task<Void, Never>> = []
  private let maxPendingTasks = 3
  private var currentApp: String?
  private var commitTurnActive = false
  private var commitTurnWaiters: [CheckedContinuation<Void, Never>] = []
  private var commitTurnWaiterObservers: [CheckedContinuation<Void, Never>] = []

  // MARK: - Context Cache
  // Cached context from local DB (goals, tasks, memories) to enrich focus analysis
  private var cachedContextString: String?
  private var contextCacheTime: Date?
  private let contextCacheDuration: TimeInterval = 120  // 2 minutes

  // MARK: - Smart Analysis Filtering
  // Skip analysis when user is focused on the same context (app + window title)
  // Also skip during cooldown period after distraction (unless context changes)
  private var lastAnalyzedApp: String?
  private var lastAnalyzedWindowTitle: String?
  private var analysisCooldownEndTime: Date?

  // MARK: - Notification Deduplication
  // Track the last state we notified about to prevent duplicate notifications
  // from parallel frame analysis (only notify on state change)
  private var lastNotifiedState: FocusStatus?

  // MARK: - Error Backoff
  // Prevents infinite retry loops when Gemini consistently rejects content (e.g. safety filter)
  private var consecutiveErrorCount = 0
  private var errorBackoffEndTime: Date?

  /// Get the current system prompt from settings (accessed on MainActor for thread safety)
  private var systemPrompt: String {
    get async {
      await MainActor.run {
        FocusAssistantSettings.shared.analysisPrompt
      }
    }
  }

  // MARK: - Initialization

  init(
    apiKey: String? = nil,
    onAlert: @escaping @Sendable (String, RuntimeOwnerAuthorizationSnapshot) -> Void = { _, _ in },
    onStatusChange: (@Sendable (FocusStatus, RuntimeOwnerAuthorizationSnapshot) -> Void)? = nil,
    onRefocus: (@Sendable (RuntimeOwnerAuthorizationSnapshot) -> Void)? = nil,
    onDistraction: (@Sendable (RuntimeOwnerAuthorizationSnapshot) -> Void)? = nil
  ) throws {
    self.geminiClient = try GeminiClient(apiKey: apiKey, fallbackModel: "gemini-2.5-flash")
    self.analysisOverride = nil
    self.focusSessionPersister = { record, authorization in
      try await ProactiveStorage.shared.insertFocusSession(
        record,
        authorization: authorization)
    }
    self.onAlert = onAlert
    self.onStatusChange = onStatusChange
    self.onRefocus = onRefocus
    self.onDistraction = onDistraction

    let (stream, continuation) = AsyncStream.makeStream(of: OwnerBoundCapturedFrame.self)
    self.frameStream = stream
    self.frameContinuation = continuation

    // Start processing loop in a task
    Task {
      await self.startProcessing()
    }
  }

  init(
    analysisOverride: @escaping AnalysisOverride,
    focusSessionPersister: @escaping FocusSessionPersister,
    onAlert: @escaping @Sendable (String, RuntimeOwnerAuthorizationSnapshot) -> Void = { _, _ in },
    onStatusChange: (@Sendable (FocusStatus, RuntimeOwnerAuthorizationSnapshot) -> Void)? = nil,
    onRefocus: (@Sendable (RuntimeOwnerAuthorizationSnapshot) -> Void)? = nil,
    onDistraction: (@Sendable (RuntimeOwnerAuthorizationSnapshot) -> Void)? = nil
  ) {
    self.geminiClient = nil
    self.analysisOverride = analysisOverride
    self.focusSessionPersister = focusSessionPersister
    self.onAlert = onAlert
    self.onStatusChange = onStatusChange
    self.onRefocus = onRefocus
    self.onDistraction = onDistraction
    let (stream, continuation) = AsyncStream.makeStream(of: OwnerBoundCapturedFrame.self)
    self.frameStream = stream
    self.frameContinuation = continuation
  }

  // MARK: - Processing

  private func removePendingTask(_ task: Task<Void, Never>) {
    pendingTasks.remove(task)
  }

  private func acquireCommitTurn() async {
    guard commitTurnActive else {
      commitTurnActive = true
      return
    }
    await withCheckedContinuation { continuation in
      commitTurnWaiters.append(continuation)
      let observers = commitTurnWaiterObservers
      commitTurnWaiterObservers.removeAll()
      observers.forEach { $0.resume() }
    }
  }

  private func releaseCommitTurn() {
    guard !commitTurnWaiters.isEmpty else {
      commitTurnActive = false
      return
    }
    commitTurnWaiters.removeFirst().resume()
  }

  private func startProcessing() {
    isRunning = true
    processingTask = Task {
      await processFrameLoop()
    }
  }

  private func processFrameLoop() async {
    log("Focus assistant started (parallel mode)")

    for await ownerBoundFrame in frameStream {
      guard isRunning else { break }

      // Backpressure: skip frame if too many analyses in flight
      if pendingTasks.count >= maxPendingTasks {
        continue
      }

      // Fire off analysis in background (don't wait) - like Python version
      let task = Task { [weak self] () -> Void in
        await self?.processFrame(
          ownerBoundFrame.frame,
          authorizationSnapshot: ownerBoundFrame.authorizationSnapshot)
      }
      pendingTasks.insert(task)

      // Remove the task from the set after it completes to prevent unbounded growth
      Task { [weak self] in
        _ = await task.result
        await self?.removePendingTask(task)
      }
    }

    // Wait for pending tasks on shutdown
    for task in pendingTasks {
      _ = await task.result
    }

    log("Focus assistant stopped")
  }

  // MARK: - ProactiveAssistant Protocol Methods

  func shouldAnalyze(frameNumber: Int, timeSinceLastAnalysis: TimeInterval) -> Bool {
    // Focus assistant analyzes every frame
    return true
  }

  func analyze(
    frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> AssistantResult? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return nil }
    // Skip lock screen / login screen — no useful content to analyze
    let skipApps = ["loginwindow", "ScreenSaverEngine"]
    if skipApps.contains(frame.appName) {
      return nil
    }

    // Skip apps excluded from focus analysis
    let excluded = await MainActor.run { FocusAssistantSettings.shared.isAppExcluded(frame.appName) }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return nil }
    if excluded {
      log("Focus: Skipping excluded app '\(frame.appName)'")
      return nil
    }

    // Smart filtering: Skip analysis if user is focused on the same context
    if shouldSkipAnalysis(for: frame, authorizationSnapshot: authorizationSnapshot) {
      return nil
    }

    // Update last analyzed context IMMEDIATELY when queuing (not after API response)
    // This prevents multiple frames from being queued for the same context change
    lastAnalyzedApp = frame.appName
    lastAnalyzedWindowTitle = frame.windowTitle

    // Submit frame to stream for processing
    frameContinuation.yield(
      OwnerBoundCapturedFrame(
        frame: frame,
        authorizationSnapshot: authorizationSnapshot))
    log("Focus: Analyzing frame \(frame.frameNumber): App=\(frame.appName), Window=\(frame.windowTitle ?? "unknown")")

    // Return nil since we process asynchronously
    return nil
  }

  /// Determines if we should skip analysis for this frame
  /// Returns true if:
  /// - User is focused on the same app AND same window title
  /// - OR we're in cooldown period after distraction (unless context changed)
  /// - OR we're in error backoff period
  private func shouldSkipAnalysis(
    for frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) -> Bool {
    // Check error backoff FIRST (before the lastStatus guard)
    // This prevents infinite retry loops when lastStatus is nil due to repeated errors
    if let backoffEnd = errorBackoffEndTime {
      if Date() < backoffEnd {
        return true
      } else {
        // Backoff expired, allow retry
        errorBackoffEndTime = nil
        log("Focus: Error backoff expired, allowing retry")
      }
    }

    // Always analyze if we don't have a status yet
    guard lastStatus != nil else {
      return false
    }

    // Check if context changed (app or window title different from last analysis)
    // Compare normalized titles so spinner/timer updates don't trigger re-analysis
    let contextChanged = ContextDetection.didContextChange(
      fromApp: lastAnalyzedApp,
      fromWindowTitle: lastAnalyzedWindowTitle,
      toApp: frame.appName,
      toWindowTitle: frame.windowTitle
    )

    // Check 1: Context switch - ALWAYS analyze (bypass cooldown)
    if contextChanged {
      // Clear cooldown on context switch since user changed context
      if analysisCooldownEndTime != nil {
        log("Focus: Context switch detected, clearing cooldown - will analyze")
        analysisCooldownEndTime = nil
        // Clear cooldown in UI
        Task { @MainActor in
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          FocusStorage.shared.updateCooldownEndTime(nil)
        }
      } else {
        log(
          "Focus: Context changed (app: \(lastAnalyzedApp ?? "nil") → \(frame.appName), window: \(lastAnalyzedWindowTitle ?? "nil") → \(frame.windowTitle ?? "nil")) - will analyze"
        )
      }
      return false
    }

    // Check 2: Are we in cooldown period after distraction?
    if let cooldownEnd = analysisCooldownEndTime {
      if Date() < cooldownEnd {
        // Still in cooldown and no context switch - skip analysis
        return true
      } else {
        // Cooldown expired, clear it
        analysisCooldownEndTime = nil
        log("Focus: Cooldown ended, resuming analysis")
        // Clear cooldown in UI
        Task { @MainActor in
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          FocusStorage.shared.updateCooldownEndTime(nil)
        }
      }
    }

    // Check 3: User is focused on the same context - skip analysis
    if lastStatus == .focused {
      // User is focused on the same context - no need to re-analyze
      return true
    }

    // Default: analyze (status is distracted or unknown edge case)
    return false
  }

  func handleResult(
    _ result: AssistantResult,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    sendEvent: @escaping @Sendable (String, [String: Any]) -> Void
  ) async {
    // Results are handled internally in processFrame
  }

  func onAppSwitch(
    newApp: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    if newApp != currentApp {
      if let currentApp = currentApp {
        log("Focus: APP SWITCH: \(currentApp) -> \(newApp)")
      } else {
        log("Focus: Active app: \(newApp)")
      }
      currentApp = newApp
    }
  }

  var needsFrameDuringDelay: Bool {
    lastNotifiedState == .distracted
  }

  func clearPendingWork(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    clearPendingWorkForOwnerReset()
  }

  private func clearPendingWorkForOwnerReset() {
    // Cancel pending analysis tasks since those frames are now stale
    let count = pendingTasks.count
    for task in pendingTasks {
      task.cancel()
    }
    pendingTasks.removeAll()
    if count > 0 {
      log("Focus: Cancelled \(count) pending analysis tasks")
    }
  }

  func resetForOwnerChange() async {
    clearPendingWorkForOwnerReset()
    analysisHistory.removeAll()
    testAnalysisHistory.removeAll()
    lastProcessedFrameNum = 0
    currentApp = nil
    cachedContextString = nil
    contextCacheTime = nil
    lastAnalyzedApp = nil
    lastAnalyzedWindowTitle = nil
    analysisCooldownEndTime = nil
    lastStatus = nil
    lastNotifiedState = nil
    consecutiveErrorCount = 0
    errorBackoffEndTime = nil
    await MainActor.run {
      FocusStorage.shared.updateCooldownEndTime(nil)
    }
  }

  func stop() async {
    isRunning = false
    frameContinuation.finish()
    processingTask?.cancel()
    // Cancel all pending analysis tasks
    for task in pendingTasks {
      task.cancel()
    }
    pendingTasks.removeAll()

    // Reset tracking state
    lastAnalyzedApp = nil
    lastAnalyzedWindowTitle = nil
    lastStatus = nil
    lastNotifiedState = nil
    analysisCooldownEndTime = nil
    consecutiveErrorCount = 0
    errorBackoffEndTime = nil
    cachedContextString = nil
    contextCacheTime = nil

    // Clear cooldown in UI
    await MainActor.run {
      FocusStorage.shared.updateCooldownEndTime(nil)
    }
  }

  // MARK: - Diagnostics

  /// Number of pending analysis tasks (for memory diagnostics)
  var pendingTasksCount: Int { pendingTasks.count }

  /// Starts the real queue consumer for hermetic queue-boundary tests. The
  /// production initializer starts it automatically.
  func startProcessingForTests() {
    guard !isRunning else { return }
    startProcessing()
  }

  /// Number of analysis history entries retained
  var analysisHistoryCount: Int { analysisHistory.count }
  var lastProcessedFrameNumberForTests: Int { lastProcessedFrameNum }

  func waitUntilCommitTurnQueuedForTests() async {
    guard commitTurnWaiters.isEmpty else { return }
    await withCheckedContinuation { continuation in
      commitTurnWaiterObservers.append(continuation)
    }
  }

  // MARK: - Test API

  /// Run analysis on a screenshot with no side effects (no saving, no state updates, no notifications).
  /// Used by the test runner GUI and CLI.
  func testAnalyze(jpegData: Data, appName: String) async throws -> ScreenAnalysis? {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    return try await analyzeScreenshot(
      jpegData: jpegData,
      authorizationSnapshot: authorizationSnapshot)
  }

  /// Reset test history — call before starting a test run to get a clean slate.
  func resetTestHistory() {
    testAnalysisHistory.removeAll()
  }

  /// Run analysis with accumulating history across calls (simulates production behavior).
  /// Each result is appended to a separate test history buffer so the model sees prior decisions.
  func testAnalyzeWithHistory(jpegData: Data, appName: String) async throws -> ScreenAnalysis? {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    let result = try await analyzeScreenshotWithHistory(
      jpegData: jpegData,
      history: testAnalysisHistory,
      authorizationSnapshot: authorizationSnapshot)
    try requireCurrentAuthorization(authorizationSnapshot)
    if let result = result {
      testAnalysisHistory.append(result)
      if testAnalysisHistory.count > maxHistorySize {
        testAnalysisHistory.removeFirst()
      }
    }
    return result
  }

  /// Separate history buffer for test runs (doesn't pollute production history)
  private var testAnalysisHistory: [ScreenAnalysis] = []
  var testAnalysisHistoryCountForTests: Int { testAnalysisHistory.count }

  /// Variant of analyzeScreenshot that accepts an explicit history array
  private func analyzeScreenshotWithHistory(
    jpegData: Data,
    history: [ScreenAnalysis],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> ScreenAnalysis? {
    if let analysisOverride {
      let result = try await analysisOverride(jpegData, authorizationSnapshot)
      try requireCurrentAuthorization(authorizationSnapshot)
      return result
    }
    let context = try await refreshContext(
      authorizationSnapshot: authorizationSnapshot)

    // Format provided history
    var historyText = ""
    if !history.isEmpty {
      var lines = ["Recent activity (oldest to newest):"]
      for (i, past) in history.enumerated() {
        lines.append("\(i + 1). [\(past.status.rawValue)] \(past.appOrSite): \(past.description)")
        if let message = past.message {
          lines.append("   Message: \(message)")
        }
      }
      historyText = lines.joined(separator: "\n")
    }

    var promptParts: [String] = []
    if !context.isEmpty {
      promptParts.append(context)
    }
    if !historyText.isEmpty {
      promptParts.append(historyText)
    }
    promptParts.append("Now analyze this new screenshot:")
    let prompt = promptParts.joined(separator: "\n\n")

    let currentSystemPrompt = await systemPrompt
    try requireCurrentAuthorization(authorizationSnapshot)

    let responseSchema = GeminiRequest.GenerationConfig.ResponseSchema(
      type: "object",
      properties: [
        "status": .init(
          type: "string", enum: ["focused", "distracted"], description: "Whether the user is focused or distracted"),
        "app_or_site": .init(type: "string", enum: nil, description: "The app or website visible"),
        "description": .init(type: "string", enum: nil, description: "Brief description of what's on screen"),
        "message": .init(type: "string", enum: nil, description: "Coaching message"),
      ],
      required: ["status", "app_or_site", "description"]
    )

    guard let geminiClient else { return nil }
    let responseText = try await geminiClient.sendRequest(
      prompt: prompt,
      imageData: jpegData,
      systemPrompt: currentSystemPrompt,
      responseSchema: responseSchema,
      authorizationSnapshot: authorizationSnapshot
    )
    try requireCurrentAuthorization(authorizationSnapshot)

    let result = try JSONDecoder().decode(ScreenAnalysis.self, from: Data(responseText.utf8))
    try requireCurrentAuthorization(authorizationSnapshot)
    return result
  }

  // MARK: - Analysis

  private func formatHistory() -> String {
    guard !analysisHistory.isEmpty else { return "" }

    var lines = ["Recent activity (oldest to newest):"]
    for (i, past) in analysisHistory.enumerated() {
      lines.append("\(i + 1). [\(past.status.rawValue)] \(past.appOrSite): \(past.description)")
      if let message = past.message {
        lines.append("   Message: \(message)")
      }
    }
    return lines.joined(separator: "\n")
  }

  func processFrame(
    _ frame: CapturedFrame,
    authorizationSnapshot ownerAuthorization: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
    let ownerID = ownerAuthorization.ownerID
    guard await isEnabled,
      RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization)
    else { return }

    do {
      guard
        let analysis = try await analyzeScreenshot(
          jpegData: frame.jpegData,
          authorizationSnapshot: ownerAuthorization)
      else { return }
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }

      await acquireCommitTurn()
      defer { releaseCommitTurn() }
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }

      guard frame.frameNumber > lastProcessedFrameNum else {
        log("[Frame \(frame.frameNumber)] Skipped (newer frame already processed)")
        return
      }

      let previousNotifiedState = lastNotifiedState
      let isStateTransition = previousNotifiedState != analysis.status
      var sqliteId: Int64?
      if isStateTransition {
        sqliteId = await saveFocusSessionToSQLite(
          analysis: analysis,
          screenshotId: frame.screenshotId,
          windowTitle: frame.windowTitle,
          ownerAuthorization: ownerAuthorization)
        guard sqliteId != nil,
          RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization)
        else { return }
      }

      // Publish actor state only after the transition is durable. No await may
      // split this block because parallel Focus analyses are actor-reentrant.
      consecutiveErrorCount = 0
      errorBackoffEndTime = nil
      lastProcessedFrameNum = frame.frameNumber
      analysisHistory.append(analysis)
      if analysisHistory.count > maxHistorySize { analysisHistory.removeFirst() }
      lastStatus = analysis.status
      if isStateTransition { lastNotifiedState = analysis.status }
      onStatusChange?(analysis.status, ownerAuthorization)

      log(
        "[Frame \(frame.frameNumber)] Focus state accepted (status=\(analysis.status.rawValue))"
      )

      guard isStateTransition, let sqliteId else { return }
      await MainActor.run {
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
        FocusStorage.shared.addSession(from: analysis, sqliteId: sqliteId)
      }
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }

      if analysis.status == .distracted {
        await MainActor.run {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
          AnalyticsManager.shared.distractionDetected(
            app: analysis.appOrSite,
            windowTitle: frame.windowTitle)
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
        onDistraction?(ownerAuthorization)

        let cooldownSeconds = await MainActor.run {
          FocusAssistantSettings.shared.cooldownIntervalSeconds
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
        analysisCooldownEndTime = Date().addingTimeInterval(cooldownSeconds)
        let cooldownEndTime = analysisCooldownEndTime
        await MainActor.run {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
          FocusStorage.shared.updateCooldownEndTime(cooldownEndTime)
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }

        if let message = analysis.message {
          let fullMessage = "\(analysis.appOrSite) - \(message)"
          let notificationsEnabled = await MainActor.run {
            FocusAssistantSettings.shared.notificationsEnabled
          }
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
          let context = FloatingBarNotificationContext(
            sourceTitle: "Focus",
            assistantId: identifier,
            sourceApp: analysis.appOrSite.isEmpty ? nil : analysis.appOrSite,
            windowTitle: frame.windowTitle,
            contextSummary: nil,
            currentActivity: analysis.description.isEmpty ? nil : analysis.description,
            reasoning: "Distraction detected: user switched from focused work to \(analysis.appOrSite).",
            detail: message)
          await MainActor.run {
            guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
            AnalyticsManager.shared.focusAlertShown(app: analysis.appOrSite)
            if notificationsEnabled {
              NotificationService.shared.sendNotification(
                ownerID: ownerID,
                title: "Focus",
                message: fullMessage,
                assistantId: identifier,
                sound: .none,
                context: context,
                authorizationSnapshot: ownerAuthorization)
            }
          }
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
          onAlert(fullMessage, ownerAuthorization)
        }
      } else if previousNotifiedState == .distracted {
        await MainActor.run {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
          AnalyticsManager.shared.focusRestored(app: analysis.appOrSite)
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
        onRefocus?(ownerAuthorization)

        if let message = analysis.message {
          let notificationsEnabled = await MainActor.run {
            FocusAssistantSettings.shared.notificationsEnabled
          }
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
          let context = FloatingBarNotificationContext(
            sourceTitle: "Focus",
            assistantId: identifier,
            sourceApp: analysis.appOrSite.isEmpty ? nil : analysis.appOrSite,
            windowTitle: frame.windowTitle,
            contextSummary: nil,
            currentActivity: analysis.description.isEmpty ? nil : analysis.description,
            reasoning: "Focus restored: user returned to focused work after a distraction.",
            detail: message)
          if notificationsEnabled {
            await MainActor.run {
              guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
              NotificationService.shared.sendNotification(
                ownerID: ownerID,
                title: "Focus",
                message: message,
                assistantId: identifier,
                sound: .none,
                context: context,
                authorizationSnapshot: ownerAuthorization)
            }
          }
        }
      }
    } catch {
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return }
      consecutiveErrorCount += 1
      let backoffSeconds = min(5.0 * pow(2.0, Double(consecutiveErrorCount - 1)), 300.0)
      errorBackoffEndTime = Date().addingTimeInterval(backoffSeconds)
      logError(
        "Frame \(frame.frameNumber) error (consecutive: \(consecutiveErrorCount), backoff: \(Int(backoffSeconds))s)",
        error: error)
    }
  }

  /// Refresh context from local DB (goals, tasks, memories) with caching
  private func refreshContext(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> String {
    try requireCurrentAuthorization(authorizationSnapshot)
    // Return cached context if fresh
    if let cached = cachedContextString,
      let cacheTime = contextCacheTime,
      Date().timeIntervalSince(cacheTime) < contextCacheDuration
    {
      return cached
    }

    var sections: [String] = []

    // AI User Profile
    do {
      if let profile = await AIUserProfileService.shared.getLatestProfile(
        authorizationSnapshot: authorizationSnapshot)
      {
        try requireCurrentAuthorization(authorizationSnapshot)
        sections.append("USER PROFILE (who this user is):\n\(profile.profileText)")
      }
      try requireCurrentAuthorization(authorizationSnapshot)
    }

    // Time context
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
    sections.append("TIME CONTEXT:\n\(formatter.string(from: Date()))")

    // Active goals
    do {
      let goals = try await GoalStorage.shared.getLocalGoals(
        activeOnly: true,
        authorizationSnapshot: authorizationSnapshot)
      try requireCurrentAuthorization(authorizationSnapshot)
      if !goals.isEmpty {
        var lines = ["ACTIVE GOALS:"]
        for (i, goal) in goals.prefix(10).enumerated() {
          let desc = goal.description.map { " - \($0)" } ?? ""
          lines.append("\(i + 1). \(goal.title)\(desc)")
        }
        sections.append(lines.joined(separator: "\n"))
      }
    } catch is LocalMutationAuthorizationError {
      throw LocalMutationAuthorizationError.revoked
    } catch {
      logError(
        "Focus: Failed to load goals for context",
        error: error,
        context: StorageFailureDiagnostics.context(
          pathClass: "goals-db",
          containingURL: DesktopLocalProfile.applicationSupportURL(),
          databaseURL: nil,
          error: error,
          appIsTerminating: RewindDatabase.isTerminationInProgress))
    }

    // Current local tasks in deterministic priority/due/order/recency order.
    do {
      let tasks = try await ActionItemStorage.shared.getLocalActionItems(
        limit: 50,
        completed: false,
        authorizationSnapshot: authorizationSnapshot)
      try requireCurrentAuthorization(authorizationSnapshot)
      if !tasks.isEmpty {
        var lines = ["CURRENT TASKS:"]
        for (i, task) in tasks.enumerated() {
          let priority = task.priority ?? "medium"
          lines.append("\(i + 1). [\(priority)] \(task.description)")
        }
        sections.append(lines.joined(separator: "\n"))
      }
    } catch is LocalMutationAuthorizationError {
      throw LocalMutationAuthorizationError.revoked
    } catch {
      logError("Focus: Failed to load tasks for context", error: error)
    }

    // Recent memories
    do {
      let memories = try await MemoryStorage.shared.list(
        limit: 50,
        authorizationSnapshot: authorizationSnapshot)
      try requireCurrentAuthorization(authorizationSnapshot)
      if !memories.isEmpty {
        var lines = ["RECENT MEMORIES:"]
        for (i, memory) in memories.enumerated() {
          lines.append("\(i + 1). \(memory.content)")
        }
        sections.append(lines.joined(separator: "\n"))
      }
    } catch is LocalMutationAuthorizationError {
      throw LocalMutationAuthorizationError.revoked
    } catch {
      logError("Focus: Failed to load memories for context", error: error)
    }

    let contextString = sections.joined(separator: "\n\n")
    try requireCurrentAuthorization(authorizationSnapshot)
    cachedContextString = contextString
    contextCacheTime = Date()
    return contextString
  }

  private func analyzeScreenshot(
    jpegData: Data,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> ScreenAnalysis? {
    if let analysisOverride {
      let result = try await analysisOverride(jpegData, authorizationSnapshot)
      try requireCurrentAuthorization(authorizationSnapshot)
      return result
    }
    guard let geminiClient else { return nil }
    // Refresh context from local DB
    let context = try await refreshContext(authorizationSnapshot: authorizationSnapshot)
    try requireCurrentAuthorization(authorizationSnapshot)

    // Build prompt with context + history
    let historyText = formatHistory()
    var promptParts: [String] = []
    if !context.isEmpty {
      promptParts.append(context)
    }
    if !historyText.isEmpty {
      promptParts.append(historyText)
    }
    promptParts.append("Now analyze this new screenshot:")
    let prompt = promptParts.joined(separator: "\n\n")

    // Get current system prompt from settings
    let currentSystemPrompt = await systemPrompt
    try requireCurrentAuthorization(authorizationSnapshot)

    // Build response schema
    let responseSchema = GeminiRequest.GenerationConfig.ResponseSchema(
      type: "object",
      properties: [
        "status": .init(
          type: "string", enum: ["focused", "distracted"], description: "Whether the user is focused or distracted"),
        "app_or_site": .init(type: "string", enum: nil, description: "The app or website visible"),
        "description": .init(type: "string", enum: nil, description: "Brief description of what's on screen"),
        "message": .init(type: "string", enum: nil, description: "Coaching message"),
      ],
      required: ["status", "app_or_site", "description"]
    )

    let responseText = try await geminiClient.sendRequest(
      prompt: prompt,
      imageData: jpegData,
      systemPrompt: currentSystemPrompt,
      responseSchema: responseSchema,
      authorizationSnapshot: authorizationSnapshot
    )

    return try JSONDecoder().decode(ScreenAnalysis.self, from: Data(responseText.utf8))
  }

  // MARK: - Storage

  /// Save focus session and its Memory assertion to their local authorities.
  /// Returns the inserted `focus_sessions` rowid so the caller can reuse it as
  /// the in-memory session id (see `FocusStorage.addSession(from:sqliteId:)`).
  @discardableResult
  private func saveFocusSessionToSQLite(
    analysis: ScreenAnalysis,
    screenshotId: Int64?,
    windowTitle: String? = nil,
    ownerAuthorization: RuntimeOwnerAuthorizationSnapshot
  ) async -> Int64? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return nil }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization)
    }
    // Save to focus_sessions table (for detailed tracking)
    let focusRecord = FocusSessionRecord(
      screenshotId: screenshotId,
      status: analysis.status.rawValue,
      appOrSite: analysis.appOrSite,
      windowTitle: windowTitle,
      description: analysis.description,
      message: analysis.message
    )

    var focusSessionId: Int64?
    do {
      let inserted = try await focusSessionPersister(focusRecord, authorization)
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(ownerAuthorization) else { return nil }
      focusSessionId = inserted.id
      log("Focus: Saved to focus_sessions (id: \(inserted.id ?? -1), status: \(analysis.status.rawValue))")
    } catch {
      logError("Focus: Failed to save to focus_sessions", error: error)
    }

    return focusSessionId
  }

  private func requireCurrentAuthorization(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) throws {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
  }

}
