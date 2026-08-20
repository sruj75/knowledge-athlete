import Combine
import Foundation

protocol InsightMutationPersisting: Sendable {
  func persistMarkInsightRead(id: String, authorization: LocalMutationAuthorization) async throws
  func persistMarkAllInsightsRead(authorization: LocalMutationAuthorization) async throws
  func persistMarkInsightDismissed(
    id: String,
    isDismissed: Bool,
    authorization: LocalMutationAuthorization
  ) async throws
  func persistDeleteInsight(id: String, authorization: LocalMutationAuthorization) async throws
  func persistClearInsights(authorization: LocalMutationAuthorization) async throws -> Int
}

extension MemoryStorage: InsightMutationPersisting {
  func persistMarkInsightRead(id: String, authorization: LocalMutationAuthorization) async throws {
    try await markInsightRead(id: id, now: Date(), authorization: authorization)
  }

  func persistMarkAllInsightsRead(authorization: LocalMutationAuthorization) async throws {
    try await markAllInsightsRead(now: Date(), authorization: authorization)
  }

  func persistMarkInsightDismissed(
    id: String,
    isDismissed: Bool,
    authorization: LocalMutationAuthorization
  ) async throws {
    try await markInsightDismissed(
      id: id,
      isDismissed: isDismissed,
      now: Date(),
      authorization: authorization)
  }

  func persistDeleteInsight(
    id: String,
    authorization: LocalMutationAuthorization
  ) async throws {
    try await deleteInsight(id: id, authorization: authorization)
  }

  func persistClearInsights(authorization: LocalMutationAuthorization) async throws -> Int {
    try await clearInsights(authorization: authorization)
  }
}

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

/// Owner-scoped in-memory projection of authoritative `tips` Memory rows.
@MainActor
class InsightStorage: ObservableObject {
  static let shared = InsightStorage()

  @Published private(set) var insightHistory: [StoredInsight] = []
  @Published private(set) var isLoading = false
  @Published private(set) var lastSyncError: String?

  private let maxLocalInsights = 100
  private let mutationPersistence: any InsightMutationPersisting
  private let automaticallyRefresh: Bool
  private var isSyncing = false
  private var ownerScopeGeneration = 0
  private var cancellables = Set<AnyCancellable>()

  init(
    defaults: UserDefaults = .standard,
    startAutomatically: Bool = true,
    notificationCenter: NotificationCenter = .default,
    mutationPersistence: any InsightMutationPersisting = MemoryStorage.shared
  ) {
    self.mutationPersistence = mutationPersistence
    automaticallyRefresh = startAutomatically
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("omi.advice.history") {
      defaults.removeObject(forKey: key)
    }
    notificationCenter.publisher(for: .runtimeOwnerDidChange)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          self?.resetForCurrentOwner()
        }
      }
      .store(in: &cancellables)
    if startAutomatically {
      Task { await refreshFromLocalMemories() }
    }
  }

  private func resetForCurrentOwner() {
    ownerScopeGeneration += 1
    insightHistory = []
    isLoading = false
    lastSyncError = nil
    isSyncing = false
    if automaticallyRefresh {
      Task { await refreshFromLocalMemories() }
    }
  }

  // MARK: - Public Methods

  /// Add new insight to presentation storage after InsightAssistant commits its Memory row.
  func addInsight(_ result: InsightExtractionResult, memoryID: Int64) {
    guard let insight = result.insight else { return }

    // Create local stored insight
    let storedInsight = StoredInsight(
      id: String(memoryID),
      insight: insight,
      contextSummary: result.contextSummary,
      currentActivity: result.currentActivity
    )

    // Add locally for immediate UI update
    insightHistory.insert(storedInsight, at: 0)
    trimLocalCache()
  }

  /// Mark advice as read
  func markAsRead(_ id: String) async {
    guard insightHistory.contains(where: { $0.id == id }) else { return }
    guard let scope = currentMutationScope() else { return }
    do {
      try await mutationPersistence.persistMarkInsightRead(
        id: id,
        authorization: scope.authorization)
      guard canPublish(scope) else { return }
      guard let index = insightHistory.firstIndex(where: { $0.id == id }) else { return }
      insightHistory[index] = insightHistory[index].withRead(true)
      lastSyncError = nil
    } catch {
      guard canPublish(scope) else { return }
      lastSyncError = error.localizedDescription
      logError("Insight: Failed to mark local row read", error: error)
    }
  }

  /// Mark all advice as read
  func markAllAsRead() async {
    guard let scope = currentMutationScope() else { return }
    do {
      try await mutationPersistence.persistMarkAllInsightsRead(authorization: scope.authorization)
      guard canPublish(scope) else { return }
      insightHistory = insightHistory.map { $0.withRead(true) }
      lastSyncError = nil
    } catch {
      guard canPublish(scope) else { return }
      lastSyncError = error.localizedDescription
      logError("Insight: Failed to mark all local rows read", error: error)
    }
  }

  /// Dismiss advice (hide from list)
  func dismissInsight(_ id: String) async {
    guard insightHistory.contains(where: { $0.id == id }) else { return }
    guard let scope = currentMutationScope() else { return }
    do {
      try await mutationPersistence.persistMarkInsightDismissed(
        id: id,
        isDismissed: true,
        authorization: scope.authorization)
      guard canPublish(scope) else { return }
      guard let index = insightHistory.firstIndex(where: { $0.id == id }) else { return }
      insightHistory[index] = insightHistory[index].withDismissed(true)
      lastSyncError = nil
    } catch {
      guard canPublish(scope) else { return }
      lastSyncError = error.localizedDescription
      logError("Insight: Failed to dismiss local row", error: error)
    }
  }

  /// Delete advice permanently
  func deleteInsight(_ id: String) async {
    guard let scope = currentMutationScope() else { return }
    do {
      try await mutationPersistence.persistDeleteInsight(
        id: id,
        authorization: scope.authorization)
      guard canPublish(scope) else { return }
      insightHistory.removeAll { $0.id == id }
      lastSyncError = nil
    } catch {
      guard canPublish(scope) else { return }
      lastSyncError = error.localizedDescription
      logError("Insight: Failed to delete local row", error: error)
    }
  }

  /// Clear all advice history
  func clearAll() async {
    guard let scope = currentMutationScope() else { return }
    do {
      _ = try await mutationPersistence.persistClearInsights(authorization: scope.authorization)
      guard canPublish(scope) else { return }
      insightHistory = []
      lastSyncError = nil
    } catch {
      guard canPublish(scope) else { return }
      lastSyncError = error.localizedDescription
      logError("Insight: Failed to clear local rows", error: error)
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
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    let generation = ownerScopeGeneration

    isSyncing = true
    defer {
      if generation == ownerScopeGeneration { isSyncing = false }
    }
    isLoading = true
    lastSyncError = nil

    do {
      let memories = try await MemoryStorage.shared.listInsights(
        limit: maxLocalInsights,
        includeDismissed: true)

      let localInsight = memories.map { StoredInsight(from: $0) }
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }

      await MainActor.run {
        self.insightHistory = localInsight
        self.isLoading = false
      }

      log("Insight: Refreshed \(localInsight.count) items from local Memories")
    } catch {
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      await MainActor.run {
        self.lastSyncError = error.localizedDescription
        self.isLoading = false
      }
      logError("Insight: Failed to refresh local Memories", error: error)
    }

  }

  private struct MutationScope {
    let snapshot: RuntimeOwnerAuthorizationSnapshot
    let generation: Int

    var authorization: LocalMutationAuthorization {
      LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
    }
  }

  private func currentMutationScope() -> MutationScope? {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return nil }
    return MutationScope(snapshot: snapshot, generation: ownerScopeGeneration)
  }

  private func canPublish(_ scope: MutationScope) -> Bool {
    scope.generation == ownerScopeGeneration
      && RuntimeOwnerIdentity.isAuthorizationCurrent(scope.snapshot)
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
