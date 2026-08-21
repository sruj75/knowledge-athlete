import Combine
import Foundation
import SwiftUI

/// View model for the Rewind page
@MainActor
class RewindViewModel: ObservableObject {
  // MARK: - Published State

  @Published var screenshots: [Screenshot] = []
  @Published var selectedScreenshot: Screenshot? = nil
  @Published var searchQuery: String = ""
  @Published var selectedApp: String? = nil
  @Published var selectedDate: Date = Date()
  @Published var availableApps: [String] = []

  @Published var isLoading = false
  @Published var isSearching = false
  @Published var errorMessage: String? = nil

  @Published var stats: (total: Int, indexed: Int, storageSize: Int64)? = nil

  /// The active search query (trimmed, non-empty) for highlighting
  @Published var activeSearchQuery: String? = nil

  // MARK: - Recovery Status

  /// Whether the database was recovered from corruption on this launch
  @Published var didRecoverFromCorruption = false

  /// Number of records recovered (0 if fresh database created)
  @Published var recoveredRecordCount = 0

  /// Whether the recovery banner should be shown
  @Published var showRecoveryBanner = false

  /// Whether a database rebuild is in progress
  @Published var isRebuilding = false

  /// Progress of database rebuild (0.0 to 1.0)
  @Published var rebuildProgress: Double = 0.0

  /// Time window in seconds for grouping search results
  var searchGroupingTimeWindow: TimeInterval = 30

  /// Grouped search results (computed from screenshots when searching)
  var groupedSearchResults: [SearchResultGroup] {
    guard activeSearchQuery != nil else { return [] }
    return screenshots.groupedByContext(timeWindowSeconds: searchGroupingTimeWindow)
  }

  /// Total number of individual screenshots across all groups
  var totalScreenshotCount: Int {
    screenshots.count
  }

  // MARK: - Private State

  private var searchTask: Task<Void, Never>?
  private var activeSearchOperationID: UUID?
  private var cancellables = Set<AnyCancellable>()

  /// Whether initial data has been loaded (prevents race condition with debounced search)
  private var isInitialized = false

  /// Set by RewindPage when the transcript/notes panel is expanded.
  /// Auto-refresh skips when true so the view tree stays stable and @State is preserved.
  var isTranscriptExpanded = false

  // MARK: - Initialization

  init() {
    // Debounce search queries
    $searchQuery
      .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
      .sink { [weak self] query in
        Task { await self?.performSearch(query: query) }
      }
      .store(in: &cancellables)

    // Listen for new frame captures to update stats live
    NotificationCenter.default.publisher(for: .rewindFrameCaptured)
      .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] _ in
        Task { await self?.updateStatsOnly() }
      }
      .store(in: &cancellables)

    // Auto-refresh timeline every 3 seconds when viewing today
    Timer.publish(every: 3.0, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        Task { await self?.refreshTimelineIfViewingToday() }
      }
      .store(in: &cancellables)
  }

  /// Refresh timeline only if viewing today and not actively searching.
  /// Uses a silent path that never sets isLoading and only updates screenshots
  /// when the data actually changed, preventing view-tree destruction.
  private func refreshTimelineIfViewingToday() async {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    // Skip if not initialized or currently loading
    guard isInitialized, !isLoading, !isSearching else { return }

    // Skip if there's an active search query
    guard activeSearchQuery == nil else { return }

    // Skip if transcript/notes panel is expanded — refreshing would
    // destroy the expanded view tree and lose @State (typed notes).
    guard !isTranscriptExpanded else { return }

    // Only refresh if viewing today
    let calendar = Calendar.current
    guard calendar.isDateInToday(selectedDate) else { return }

    // Silent refresh: don't set isLoading, and only update if data changed
    await silentLoadScreenshotsForDate(
      selectedDate,
      authorizationSnapshot: authorizationSnapshot)
  }

  /// Update only the stats (for live frame count updates)
  private func updateStatsOnly() async {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    if let indexerStats = await RewindIndexer.shared.getStats(
      authorizationSnapshot: authorizationSnapshot),
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    {
      stats = indexerStats
    }
  }

  // MARK: - Loading

  func loadInitialData() async {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    isLoading = true
    errorMessage = nil

    do {
      // Initialize the indexer if needed
      try await RewindIndexer.shared.initialize()
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      // Ensure database is ready — RewindIndexer.initialize() may return early
      // (already initialized) while the database is being re-opened for a different
      // user by ViewModelContainer. This call waits for any in-progress init.
      try await RewindDatabase.shared.initialize()
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      // Check if database was recovered from corruption
      let recovered = await RewindDatabase.shared.didRecoverFromCorruption
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      let recoveredCount = await RewindDatabase.shared.recoveredRecordCount
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      if recovered {
        didRecoverFromCorruption = true
        recoveredRecordCount = recoveredCount
        showRecoveryBanner = true
        log("RewindViewModel: Database was recovered from corruption, \(recoveredCount) records salvaged")
      }

      // Load today's screenshots (date filter is always active)
      await loadScreenshotsForDate(
        selectedDate,
        authorizationSnapshot: authorizationSnapshot)
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      // Load available apps for filtering
      let apps = try await RewindDatabase.shared.getUniqueAppNames(
        authorizationSnapshot: authorizationSnapshot)
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      availableApps = apps

      // Mark as initialized after successful load
      isInitialized = true

    } catch {
      if RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
        errorMessage = error.localizedDescription
        logError("RewindViewModel: Failed to load initial data: \(error)")
      }
    }

    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    isLoading = false

    // Notify that Rewind page finished loading (for sidebar loading indicator)
    log("RewindViewModel: Posting rewindPageDidLoad notification")
    NotificationCenter.default.post(name: .rewindPageDidLoad, object: nil)

    // Load stats asynchronously (includes storage size calculation which can be slow)
    Task { [weak self] in
      if let indexerStats = await RewindIndexer.shared.getStats(
        authorizationSnapshot: authorizationSnapshot),
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
      {
        self?.stats = indexerStats
      }
    }
  }

  /// Dismiss the recovery banner
  func dismissRecoveryBanner() {
    showRecoveryBanner = false
  }

  func refresh() async {
    await loadInitialData()
  }

  // MARK: - Search

  private func performSearch(query: String) async {
    // Skip if not yet initialized (prevents race condition with debounced publisher)
    guard isInitialized else { return }
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }

    // Cancel any existing search
    searchTask?.cancel()

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedQuery.isEmpty {
      // Reset to date-filtered view (date filter is always active)
      isSearching = false
      activeSearchQuery = nil
      activeSearchOperationID = nil
      await loadScreenshotsForDate(
        selectedDate,
        authorizationSnapshot: authorizationSnapshot)
      return
    }

    isSearching = true
    activeSearchQuery = trimmedQuery

    // Track rewind search
    AnalyticsManager.shared.rewindSearchPerformed(queryLength: trimmedQuery.count)

    // Calculate date range (date filter is always active)
    let calendar = Calendar.current
    let startDate = calendar.startOfDay(for: selectedDate)
    let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
    let searchOperationID = UUID()
    activeSearchOperationID = searchOperationID

    searchTask = Task {
      defer {
        if activeSearchOperationID == searchOperationID,
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
        {
          activeSearchOperationID = nil
          isSearching = false
        }
      }
      do {
        // Run FTS and vector search in parallel
        async let ftsResults = RewindDatabase.shared.search(
          query: trimmedQuery,
          appFilter: selectedApp,
          startDate: startDate,
          endDate: endDate,
          limit: 100,
          authorizationSnapshot: authorizationSnapshot
        )
        async let vectorResults = OCREmbeddingService.shared.searchSimilar(
          query: trimmedQuery,
          startDate: startDate,
          endDate: endDate,
          appFilter: selectedApp,
          topK: 50,
          authorizationSnapshot: authorizationSnapshot
        )

        let fts = try await ftsResults
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        // Vector search failures are non-fatal — FTS results still show
        let vector = (try? await vectorResults) ?? []
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        if !Task.isCancelled,
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
        {
          // Merge: FTS first, then add vector-only results above threshold
          let ftsIds = Set(fts.compactMap { $0.id })
          var merged = fts
          for result in vector where result.similarity > 0.5 && !ftsIds.contains(result.screenshotId) {
            if let screenshot = try? await RewindDatabase.shared.getScreenshot(
              id: result.screenshotId,
              authorizationSnapshot: authorizationSnapshot)
            {
              guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
              merged.append(screenshot)
            }
          }
          _ = publishSearchResults(
            merged,
            authorizationSnapshot: authorizationSnapshot)
        }
      } catch {
        if !Task.isCancelled,
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
        {
          logError("RewindViewModel: Search failed: \(error)")
        }
      }
    }
  }

  /// The single publication boundary for owner-bound search results.
  @discardableResult
  func publishSearchResults(
    _ results: [Screenshot],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) -> Bool {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return false }
    screenshots = results
    return true
  }

  // MARK: - Filtering

  func filterByApp(_ app: String?) async {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    selectedApp = app

    if !searchQuery.isEmpty {
      await performSearch(query: searchQuery)
    } else {
      await loadScreenshotsForDate(
        selectedDate,
        authorizationSnapshot: authorizationSnapshot)
    }
  }

  func filterByDate(_ date: Date) async {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    selectedDate = date

    if !searchQuery.isEmpty {
      await performSearch(query: searchQuery)
    } else {
      await loadScreenshotsForDate(
        date,
        authorizationSnapshot: authorizationSnapshot)
    }
  }

  private func loadScreenshotsForDate(
    _ date: Date,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    isLoading = true

    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    do {
      var results = try await RewindDatabase.shared.getScreenshotsSampled(
        from: startOfDay,
        to: endOfDay,
        targetCount: 500,
        authorizationSnapshot: authorizationSnapshot
      )
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      // Filter out frames from the active (unfinalized) video chunk — they can't be displayed yet
      let activeChunk = await VideoChunkEncoder.shared.currentChunkPath
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      if let activeChunk = activeChunk {
        results = results.filter { $0.videoChunkPath != activeChunk }
      }

      // Apply app filter if set
      if let app = selectedApp {
        results = results.filter { $0.appName == app }
      }

      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      screenshots = results

    } catch {
      if RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
        logError("RewindViewModel: Failed to load screenshots for date: \(error)")
      }
    }

    if RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
      isLoading = false
    }
  }

  /// Silent variant for auto-refresh: never touches isLoading, and only
  /// updates `screenshots` when the fetched IDs differ from the current set.
  /// This prevents unnecessary SwiftUI view-tree rebuilds that destroy @State.
  private func silentLoadScreenshotsForDate(
    _ date: Date,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    do {
      var results = try await RewindDatabase.shared.getScreenshotsSampled(
        from: startOfDay,
        to: endOfDay,
        targetCount: 500,
        authorizationSnapshot: authorizationSnapshot
      )
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      // Filter out frames from the active (unfinalized) video chunk
      let activeChunk = await VideoChunkEncoder.shared.currentChunkPath
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
      if let activeChunk = activeChunk {
        results = results.filter { $0.videoChunkPath != activeChunk }
      }

      // Apply app filter if set
      if let app = selectedApp {
        results = results.filter { $0.appName == app }
      }

      // Only update if the data actually changed (compare by IDs)
      let oldIds = screenshots.compactMap { $0.id }
      let newIds = results.compactMap { $0.id }
      if oldIds != newIds {
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        screenshots = results
      }

    } catch {
      if RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
        logError("RewindViewModel: Failed to silently refresh screenshots: \(error)")
      }
    }
  }

  // MARK: - Screenshot Selection

  func selectScreenshot(_ screenshot: Screenshot) {
    selectedScreenshot = screenshot
    AnalyticsManager.shared.rewindScreenshotViewed(timestamp: screenshot.timestamp)
  }

  func selectNextScreenshot() {
    guard let current = selectedScreenshot,
      let currentIndex = screenshots.firstIndex(where: { $0.id == current.id }),
      currentIndex < screenshots.count - 1
    else { return }

    selectedScreenshot = screenshots[currentIndex + 1]
    AnalyticsManager.shared.rewindTimelineNavigated(direction: "next")
  }

  func selectPreviousScreenshot() {
    guard let current = selectedScreenshot,
      let currentIndex = screenshots.firstIndex(where: { $0.id == current.id }),
      currentIndex > 0
    else { return }

    selectedScreenshot = screenshots[currentIndex - 1]
    AnalyticsManager.shared.rewindTimelineNavigated(direction: "previous")
  }

  // MARK: - Search Result Helpers

  /// Get a context snippet for the current search query on a screenshot
  func contextSnippet(for screenshot: Screenshot) -> String? {
    guard let query = activeSearchQuery else { return nil }
    return screenshot.contextSnippet(for: query)
  }

  /// Get matching text blocks for highlighting
  func matchingBlocks(for screenshot: Screenshot) -> [OCRTextBlock] {
    guard let query = activeSearchQuery else { return [] }
    return screenshot.matchingBlocks(for: query)
  }

  // MARK: - Delete

  func deleteScreenshot(_ screenshot: Screenshot) async {
    guard let id = screenshot.id else { return }
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }

    do {
      _ = try await RewindDatabase.shared.deleteScreenshotAndArtifacts(
        id: id,
        authorizationSnapshot: authorizationSnapshot)
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

      // Remove from local array
      screenshots.removeAll { $0.id == id }

      // Clear selection if deleted
      if selectedScreenshot?.id == id {
        selectedScreenshot = nil
      }

    } catch {
      if RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
        logError("RewindViewModel: Failed to delete screenshot: \(error)")
      }
    }
  }

  // MARK: - Stats

  func refreshStats() async {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    if let indexerStats = await RewindIndexer.shared.getStats(
      authorizationSnapshot: authorizationSnapshot),
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    {
      stats = indexerStats
    }
  }
}
