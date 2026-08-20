import Combine
import Foundation

extension Notification.Name {
  /// Posted after local memory/task visibility changes so Home never waits for
  /// the activation cooldown before showing the new totals.
  static let homeKnowledgeCountsDidChange = Notification.Name("com.omi.desktop.homeKnowledgeCountsDidChange")
}

enum HomeKnowledgeCountInvalidation {
  static func post() {
    NotificationCenter.default.post(name: .homeKnowledgeCountsDidChange, object: nil)
  }

  static func post(logMessage: @autoclosure () -> String) {
    log(logMessage())
    post()
  }
}

struct HomeKnowledgeCounts: Equatable, Sendable {
  let conversations: Int?
  let memories: Int?
  let tasks: Int?
}

@MainActor
struct HomeStatusLoader {
  let loadScreenshotCount: @MainActor @Sendable () async -> Int?
  let loadKnowledgeCounts: @MainActor @Sendable () async -> HomeKnowledgeCounts

  static func live() -> HomeStatusLoader {
    HomeStatusLoader(
      loadScreenshotCount: {
        do {
          return try await RewindDatabase.shared.getScreenshotCount()
        } catch {
          logError("HomeStatusLoader: Failed to load screenshot count", error: error)
          return nil
        }
      },
      loadKnowledgeCounts: {
        async let conversations = try? TranscriptionStorage.shared.conversationCount(query: .all)
        async let memories = try? MemoryStorage.shared.count()
        async let tasks = try? ActionItemStorage.shared.getLocalActionItemsCount(completed: false)

        return await HomeKnowledgeCounts(
          conversations: conversations,
          memories: memories,
          tasks: tasks
        )
      }
    )
  }
}

/// Long-lived cache for status data shown on Home. The view is intentionally
/// recreated during navigation; this store is owned by ViewModelContainer so
/// returning to Home can render cached values without repeating provider scans.
@MainActor
final class HomeStatusStore: ObservableObject {
  @Published private(set) var screenshotCount: Int?
  @Published private(set) var conversationCount: Int?
  @Published private(set) var memoryCount: Int?
  @Published private(set) var taskCount: Int?
  private let loader: HomeStatusLoader
  private let currentUserIDProvider: () -> String?
  private var sessionUserID: String?
  private var localDatabaseReady: Bool
  private var lastRefreshAt = Date.distantPast
  private var refreshTask: Task<Void, Never>?
  private var refreshID: UUID?
  private var latestKnowledgeRefreshID: UUID?
  private var knowledgeRefreshTask: Task<Void, Never>?
  private var knowledgeRefreshQueued = false
  private var refreshGeneration = 0
  private var cancellables = Set<AnyCancellable>()

  init(
    defaults: UserDefaults = .standard,
    loader: HomeStatusLoader? = nil,
    currentUserIDProvider: (() -> String?)? = nil,
    localDatabaseReady: Bool = false
  ) {
    let currentUserIDProvider =
      currentUserIDProvider ?? {
        defaults.string(forKey: .authUserId)
      }
    let sessionUserID = Self.normalizedUserID(currentUserIDProvider())
    self.loader = loader ?? .live()
    self.currentUserIDProvider = currentUserIDProvider
    self.sessionUserID = sessionUserID
    self.localDatabaseReady = localDatabaseReady
    NotificationCenter.default.publisher(for: .homeKnowledgeCountsDidChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.refreshKnowledgeCountsAfterImport()
      }
      .store(in: &cancellables)
  }

  func refreshIfNeeded(force: Bool = false, now: Date = Date()) async {
    ensureCurrentSessionScope()

    if let refreshTask {
      await refreshTask.value
      return
    }

    guard force || PollingConfig.shouldAllowActivationRefresh(now: now, lastRefresh: lastRefreshAt) else {
      return
    }

    lastRefreshAt = now
    let generation = refreshGeneration
    let refreshID = UUID()
    let task = Task { [weak self] in
      guard let self else { return }
      await self.performRefresh(generation: generation)
    }
    self.refreshID = refreshID
    refreshTask = task
    await task.value
    if self.refreshID == refreshID {
      self.refreshID = nil
      refreshTask = nil
    }
  }

  func resetSessionState() {
    resetTransientState()
    sessionUserID = nil
  }

  /// The Rewind database has opened for the current owner. Load the local
  /// screenshot metric immediately instead of waiting for the Home refresh
  /// cooldown after a pre-startup refresh skipped it.
  func databaseDidBecomeReady() async {
    ensureCurrentSessionScope()
    localDatabaseReady = true

    let generation = refreshGeneration
    let loadedScreenshotCount = await loader.loadScreenshotCount()
    guard !Task.isCancelled,
      generation == refreshGeneration,
      localDatabaseReady
    else { return }
    apply(screenshotCount: loadedScreenshotCount)
  }

  private func resetTransientState() {
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    refreshID = nil
    latestKnowledgeRefreshID = nil
    knowledgeRefreshTask?.cancel()
    knowledgeRefreshTask = nil
    knowledgeRefreshQueued = false
    lastRefreshAt = .distantPast
    localDatabaseReady = false
    screenshotCount = nil
    conversationCount = nil
    memoryCount = nil
    taskCount = nil
  }

  private func ensureCurrentSessionScope() {
    let currentUserID = Self.normalizedUserID(currentUserIDProvider())
    guard currentUserID != sessionUserID else { return }

    resetTransientState()
    sessionUserID = currentUserID
  }

  private func performRefresh(generation: Int) async {
    let shouldLoadScreenshotCount = localDatabaseReady
    let knowledgeRefreshID = beginKnowledgeRefresh()
    async let screenshots: Int? = shouldLoadScreenshotCount ? loader.loadScreenshotCount() : nil
    async let knowledgeCounts = loader.loadKnowledgeCounts()
    let (loadedScreenshots, loadedKnowledgeCounts) = await (screenshots, knowledgeCounts)

    guard !Task.isCancelled, generation == refreshGeneration else { return }
    apply(screenshotCount: loadedScreenshots)
    if knowledgeRefreshID == latestKnowledgeRefreshID {
      apply(knowledgeCounts: loadedKnowledgeCounts)
    }
  }

  private func refreshKnowledgeCountsAfterImport() {
    ensureCurrentSessionScope()
    guard knowledgeRefreshTask == nil else {
      knowledgeRefreshQueued = true
      return
    }

    let generation = refreshGeneration
    let knowledgeRefreshID = beginKnowledgeRefresh()
    let task = Task { [weak self] in
      guard let self else { return }
      let counts = await self.loader.loadKnowledgeCounts()
      guard !Task.isCancelled,
        generation == self.refreshGeneration,
        knowledgeRefreshID == self.latestKnowledgeRefreshID
      else {
        self.completeKnowledgeRefresh(id: knowledgeRefreshID)
        return
      }
      self.apply(knowledgeCounts: counts)
      self.completeKnowledgeRefresh(id: knowledgeRefreshID)
    }
    knowledgeRefreshTask = task
  }

  private func completeKnowledgeRefresh(id: UUID) {
    guard id == latestKnowledgeRefreshID else { return }
    knowledgeRefreshTask = nil
    guard knowledgeRefreshQueued else { return }
    knowledgeRefreshQueued = false
    refreshKnowledgeCountsAfterImport()
  }

  private func beginKnowledgeRefresh() -> UUID {
    let refreshID = UUID()
    latestKnowledgeRefreshID = refreshID
    return refreshID
  }

  private func apply(screenshotCount: Int?) {
    if let screenshotCount {
      self.screenshotCount = screenshotCount
    }
  }

  private func apply(knowledgeCounts: HomeKnowledgeCounts) {
    if let conversations = knowledgeCounts.conversations {
      conversationCount = conversations
    }
    if let memories = knowledgeCounts.memories {
      memoryCount = memories
    }
    if let tasks = knowledgeCounts.tasks {
      taskCount = tasks
    }
  }

  private static func normalizedUserID(_ userID: String?) -> String? {
    let trimmed = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
