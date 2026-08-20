import Foundation

/// Stored insight item with additional metadata
struct StoredInsight: Codable, Identifiable {
  let id: String
  let insight: ExtractedInsight
  let contextSummary: String
  let currentActivity: String
  let createdAt: Date
  var isRead: Bool
  var isDismissed: Bool

  init(
    id: String = UUID().uuidString,
    insight: ExtractedInsight,
    contextSummary: String,
    currentActivity: String,
    createdAt: Date = Date(),
    isRead: Bool = false,
    isDismissed: Bool = false
  ) {
    self.id = id
    self.insight = insight
    self.contextSummary = contextSummary
    self.currentActivity = currentActivity
    self.createdAt = createdAt
    self.isRead = isRead
    self.isDismissed = isDismissed
  }

  /// Convert from the authoritative local Memory model.
  init(from memory: MemoryItem) {
    self.id = memory.id
    // Extract category from tags: ["tips", "productivity"] → .productivity
    let categoryTag = memory.tags.first(where: { $0 != "tips" })
    let category = InsightCategory(rawValue: categoryTag ?? "other") ?? .other
    self.insight = ExtractedInsight(
      insight: memory.content,
      headline: nil,
      reasoning: memory.reasoning,
      category: category,
      sourceApp: memory.sourceApp ?? "Unknown",
      confidence: memory.confidence ?? 0.5
    )
    self.contextSummary = memory.contextSummary ?? ""
    self.currentActivity = memory.currentActivity ?? ""
    self.createdAt = memory.createdAt
    self.isRead = memory.isRead
    self.isDismissed = memory.isDismissed
  }

  func withRead(_ read: Bool) -> StoredInsight {
    var copy = self
    copy.isRead = read
    return copy
  }

  func withDismissed(_ dismissed: Bool) -> StoredInsight {
    var copy = self
    copy.isDismissed = dismissed
    return copy
  }
}

/// Presentation cache for advice history. Memory rows remain authoritative in omi.db.
@MainActor
class InsightStorage: ObservableObject {
  static let shared = InsightStorage()

  @Published private(set) var insightHistory: [StoredInsight] = []
  @Published private(set) var isLoading = false
  @Published private(set) var lastSyncError: String?

  private let localStorageKey = "omi.advice.history"
  private let maxLocalInsights = 100
  private var isSyncing = false

  private init() {
    // Load from local cache first for immediate display
    loadFromLocalCache()

    // Then refresh the Memory-backed portion from the owner-local database.
    Task {
      await refreshFromLocalMemories()
    }
  }

  // MARK: - Public Methods

  /// Add new insight to presentation storage after InsightAssistant commits its Memory row.
  func addInsight(_ result: InsightExtractionResult, memoryID: Int64? = nil) {
    guard let insight = result.insight else { return }

    // Create local stored insight
    let storedInsight = StoredInsight(
      id: memoryID.map(String.init) ?? UUID().uuidString,
      insight: insight,
      contextSummary: result.contextSummary,
      currentActivity: result.currentActivity
    )

    // Add locally for immediate UI update
    insightHistory.insert(storedInsight, at: 0)
    trimLocalCache()
    saveToLocalCache()
  }

  /// Mark advice as read
  func markAsRead(_ id: String) {
    guard let index = insightHistory.firstIndex(where: { $0.id == id }) else { return }

    insightHistory[index] = insightHistory[index].withRead(true)
    saveToLocalCache()

    // Mirror the presentation flag into the authoritative local Memory when linked.
    Task {
      await updateLocalMemory(id: id, isRead: true, isDismissed: nil)
    }
  }

  /// Mark all advice as read
  func markAllAsRead() {
    insightHistory = insightHistory.map { $0.withRead(true) }
    saveToLocalCache()

    // Mirror all linked rows locally.
    Task {
      await markAllLocalMemoriesRead()
    }
  }

  /// Dismiss advice (hide from list)
  func dismissInsight(_ id: String) {
    guard let index = insightHistory.firstIndex(where: { $0.id == id }) else { return }

    insightHistory[index] = insightHistory[index].withDismissed(true)
    saveToLocalCache()

    // Mirror the presentation flag into the authoritative local Memory when linked.
    Task {
      await updateLocalMemory(id: id, isRead: nil, isDismissed: true)
    }
  }

  /// Delete advice permanently
  func deleteInsight(_ id: String) {
    insightHistory.removeAll { $0.id == id }
    saveToLocalCache()

    // Delete the linked local Memory immediately; this history surface has no Undo UI.
    Task {
      await deleteLocalMemory(id: id)
    }
  }

  /// Clear all advice history
  func clearAll() {
    insightHistory = []
    saveToLocalCache()

    Task {
      do {
        _ = try await MemoryStorage.shared.deleteTaggedAssertions(tag: "tips")
      } catch {
        logError("Insight: Failed to clear local Memory rows", error: error)
      }
    }
  }

  /// Refresh from authoritative local Memory storage.
  func refresh() async {
    await refreshFromLocalMemories()
  }

  /// Get unread count
  var unreadCount: Int {
    insightHistory.filter { !$0.isRead && !$0.isDismissed }.count
  }

  /// Get visible advice (not dismissed)
  var visibleInsights: [StoredInsight] {
    insightHistory.filter { !$0.isDismissed }
  }

  // MARK: - Local Memory Projection

  private func refreshFromLocalMemories() async {
    guard !isSyncing else { return }

    isSyncing = true
    isLoading = true
    lastSyncError = nil

    do {
      let memories = try await MemoryStorage.shared.list(
        scope: .allIncludingArchive,
        categories: [.interesting],
        tags: ["tips"],
        includeDismissed: true,
        limit: maxLocalInsights,
        offset: 0
      )

      let localInsight = memories.map { StoredInsight(from: $0) }

      // Update local cache
      await MainActor.run {
        self.insightHistory = localInsight
        self.saveToLocalCache()
        self.isLoading = false
      }

      log("Insight: Refreshed \(localInsight.count) items from local Memories")
    } catch {
      await MainActor.run {
        self.lastSyncError = error.localizedDescription
        self.isLoading = false
      }
      logError("Insight: Failed to refresh local Memories", error: error)
    }

    isSyncing = false
  }

  private func updateLocalMemory(id: String, isRead: Bool?, isDismissed: Bool?) async {
    guard Int64(id) != nil else { return }
    do {
      if let isRead { try await MemoryStorage.shared.markRead(id: id, isRead: isRead) }
      if let isDismissed { try await MemoryStorage.shared.markDismissed(id: id, isDismissed: isDismissed) }
    } catch {
      logError("Insight: Failed to update local Memory", error: error)
    }
  }

  private func deleteLocalMemory(id: String) async {
    guard Int64(id) != nil else { return }
    do {
      _ = try await MemoryStorage.shared.beginDeletion(id: id)
      try await MemoryStorage.shared.finalizeDeletion(id: id)
    } catch {
      logError("Insight: Failed to delete local Memory", error: error)
    }
  }

  private func markAllLocalMemoriesRead() async {
    let unreadIds = insightHistory.filter { !$0.isRead }.map { $0.id }
    guard !unreadIds.isEmpty else { return }
    await withTaskGroup(of: Void.self) { group in
      for id in unreadIds {
        group.addTask {
          guard Int64(id) != nil else { return }
          do {
            try await MemoryStorage.shared.markRead(id: id, isRead: true)
          } catch {
            logError("Insight: Failed to mark \(id) as read locally", error: error)
          }
        }
      }
    }
    log("Insight: Marked \(unreadIds.count) insight(s) as read locally")
  }

  // MARK: - Local Cache

  private func loadFromLocalCache() {
    guard let data = UserDefaults.standard.data(forKey: localStorageKey) else {
      return
    }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      insightHistory = try decoder.decode([StoredInsight].self, from: data)
    } catch {
      logError("Failed to load insights from local cache", error: error)
    }
  }

  private func saveToLocalCache() {
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(insightHistory)
      UserDefaults.standard.set(data, forKey: localStorageKey)
    } catch {
      logError("Failed to save insights to local cache", error: error)
    }
  }

  private func trimLocalCache() {
    if insightHistory.count > maxLocalInsights {
      insightHistory = Array(insightHistory.prefix(maxLocalInsights))
    }
  }
}

// MARK: - InsightCategory Extensions

extension InsightCategory: CaseIterable {
  public static var allCases: [InsightCategory] {
    [.productivity, .health, .communication, .learning, .other]
  }

  var displayName: String {
    switch self {
    case .productivity: return "Productivity"
    case .health: return "Health"
    case .communication: return "Communication"
    case .learning: return "Learning"
    case .other: return "Other"
    }
  }

  var icon: String {
    switch self {
    case .productivity: return "chart.line.uptrend.xyaxis"
    case .health: return "heart.fill"
    case .communication: return "bubble.left.and.bubble.right.fill"
    case .learning: return "book.fill"
    case .other: return "lightbulb.fill"
    }
  }
}
