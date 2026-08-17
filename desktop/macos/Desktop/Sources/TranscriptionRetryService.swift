import Foundation

/// Background service for recovering local finalization and enrichment work.
class TranscriptionRetryService: @unchecked Sendable {
  static let shared = TranscriptionRetryService()

  private var retryTimer: Timer?
  private var isProcessing = false
  private let retryInterval: TimeInterval = 60  // Check every 60 seconds
  private var consecutiveDBFailures = 0
  private let maxConsecutiveDBFailures = 3
  private var isPausedForDBErrors = false

  private init() {}

  // MARK: - Service Lifecycle

  /// Start the retry service (call on app launch)
  func start() {
    guard retryTimer == nil else { return }
    isPausedForDBErrors = false
    scheduleRetryTimer()
  }

  private func scheduleRetryTimer() {
    log("TranscriptionRetryService: Starting retry timer (interval: \(retryInterval)s)")
    retryTimer = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: true) { [weak self] _ in
      Task {
        await self?.processRetryQueue()
      }
    }
  }

  /// Resume the retry timer after database recovery (e.g. ViewModelContainer retry).
  func resumeAfterDatabaseRecovery() {
    consecutiveDBFailures = 0
    isPausedForDBErrors = false
    start()
  }

  /// Stop the retry service (call on app termination)
  func stop() {
    log("TranscriptionRetryService: Stopping")
    retryTimer?.invalidate()
    retryTimer = nil
  }

  // MARK: - Recovery

  /// Recover pending transcriptions on app launch
  /// Call this after database initialization
  func recoverPendingTranscriptions() async {
    log("TranscriptionRetryService: Checking local conversation work...")
    await ConversationFinalizationService.shared.recoverPendingFinalizations()
  }

  // MARK: - Retry Queue Processing

  /// Process the retry queue (called periodically by timer)
  private func processRetryQueue() async {
    // Skip if user is signed out (tokens are cleared)
    guard await AuthState.shared.isSignedIn else { return }
    guard !isProcessing else {
      log("TranscriptionRetryService: Already processing, skipping")
      return
    }

    isProcessing = true
    defer { isProcessing = false }

    do {
      _ = try await TranscriptionStorage.shared.conversationCount(query: .all)
      if consecutiveDBFailures > 0 || isPausedForDBErrors {
        log("TranscriptionRetryService: DB healthy again — resuming retry timer")
      }
      consecutiveDBFailures = 0
      if isPausedForDBErrors {
        isPausedForDBErrors = false
        start()
      }
      await ConversationFinalizationService.shared.recoverPendingFinalizations()

    } catch {
      consecutiveDBFailures += 1
      await RewindDatabase.shared.reportQueryError(error)
      if consecutiveDBFailures >= maxConsecutiveDBFailures {
        log(
          "TranscriptionRetryService: \(consecutiveDBFailures) consecutive DB failures, pausing timer "
            + "(failure_class=db_backoff recovery_action=pause_timer recovery_result=degraded)")
        DesktopDiagnosticsManager.shared.recordFallback(
          area: "transcription_retry",
          from: "timer_active",
          to: "timer_paused",
          reason: "db_backoff",
          outcome: .degraded,
          extra: ["consecutive_failures": consecutiveDBFailures]
        )
        retryTimer?.invalidate()
        retryTimer = nil
        isPausedForDBErrors = true
      } else {
        logError(
          "TranscriptionRetryService: Queue processing failed (\(consecutiveDBFailures)/\(maxConsecutiveDBFailures))",
          error: error)
      }
    }
  }

}
