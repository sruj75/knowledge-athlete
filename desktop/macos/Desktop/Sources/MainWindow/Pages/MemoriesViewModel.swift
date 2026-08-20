import AppKit
import Combine
import Foundation

protocol MemoryPageStorage: Sendable {
  func list(
    scope: MemoryLayerScope,
    categories: [MemoryCategory],
    tags: [String],
    includeDismissed: Bool,
    limit: Int,
    offset: Int
  ) async throws -> [MemoryItem]
  func count(
    scope: MemoryLayerScope,
    categories: [MemoryCategory],
    tags: [String],
    includeDismissed: Bool
  ) async throws -> Int
  func literalSearch(
    _ text: String,
    scope: MemoryLayerScope,
    categories: [MemoryCategory],
    tags: [String],
    includeDismissed: Bool,
    limit: Int,
    offset: Int
  ) async throws -> [MemoryItem]
  func memories(ids: [String]) async throws -> [MemoryItem]
  func memory(id: String, includePendingDelete: Bool) async throws -> MemoryItem?
  func acceptExplicitAssertion(
    content: String,
    now: Date,
    authorization: LocalMutationAuthorization
  ) async throws -> MemoryItem
  func correct(
    id: String,
    expectedRevision: Int,
    content: String,
    now: Date,
    ownerGeneration: Int,
    authorization: LocalMutationAuthorization
  ) async throws -> MemoryItem
  func beginDeletion(
    id: String, now: Date, authorization: LocalMutationAuthorization
  ) async throws -> Date
  func undoDeletion(
    id: String, now: Date, authorization: LocalMutationAuthorization
  ) async throws
  func finalizeDeletion(
    id: String, authorization: LocalMutationAuthorization
  ) async throws
  func deleteDefaultMemories(authorization: LocalMutationAuthorization) async throws
}

extension MemoryStorage: MemoryPageStorage {}

@MainActor
final class MemoriesViewModel: ObservableObject {
  typealias Clock = @Sendable () -> Date
  typealias Sleeper = @Sendable (UInt64) async throws -> Void

  @Published var memories: [MemoryItem] = [] { didSet { recomputeCaches() } }
  @Published var isLoading = false { didSet { resumeLoadWaitersIfIdle() } }
  @Published var isLoadingMore = false { didSet { resumeLoadWaitersIfIdle() } }
  @Published var hasMoreMemories = true
  @Published var errorMessage: String?
  @Published var searchText = "" {
    didSet {
      guard oldValue != searchText else { return }
      scopeGeneration += 1
      displayLimit = pageSize
      searchCoordinator.submit(searchText) { [weak self] query in
        await self?.performSearch(query)
      }
    }
  }
  @Published private(set) var isSearching = false
  @Published private(set) var searchResults: [MemoryItem] = []
  @Published var selectedLayerFilter: MemoryLayerFilter = .defaultAccess {
    didSet {
      guard oldValue != selectedLayerFilter else { return }
      scopeGeneration += 1
      displayLimit = pageSize
      Task { await reloadCurrentScope() }
    }
  }
  @Published var selectedTags: Set<MemoryTag> = [] {
    didSet {
      guard oldValue != selectedTags else { return }
      scopeGeneration += 1
      displayLimit = pageSize
      Task { await reloadFilteredResults() }
    }
  }
  @Published private(set) var isLoadingFiltered = false
  @Published var showingAddMemory = false
  @Published var newMemoryText = ""
  @Published var editText = ""
  @Published var selectedMemory: MemoryItem?
  @Published var pendingDeleteMemory: MemoryItem?
  @Published var undoTimeRemaining = 0.0
  @Published var showingDeleteAllConfirmation = false
  @Published var isBulkOperationInProgress = false
  @Published var linkedConversation: LocalConversation?
  @Published var isLoadingConversation = false
  @Published private(set) var filteredMemories: [MemoryItem] = []
  @Published private(set) var totalMemoriesCount = 0
  @Published private(set) var hasMoreFilteredResults = false

  private(set) var refreshInvocations = 0
  private(set) var conversationDeleteInvocations = 0
  private(set) var memoryLoadLifecycleWaiterCount = 0

  var isActive = false {
    didSet {
      if isActive && !oldValue && hasLoadedInitially {
        Task { await refreshMemoriesIfNeeded() }
      }
    }
  }

  var isInFilteredMode: Bool {
    !DebouncedSearchCoordinator.normalized(searchText).isEmpty || !selectedTags.isEmpty
  }

  var areBulkMutationsAvailable: Bool { true }

  private let storage: any MemoryPageStorage
  private let clock: Clock
  private let sleeper: Sleeper
  private let searchCoordinator: DebouncedSearchCoordinator
  private let pageSize = 100
  private var currentOffset = 0
  private var displayLimit = 100
  private var allFilteredResults: [MemoryItem] = []
  private var tagCounts: [MemoryTag: Int] = [:]
  private var scopeGeneration = 0
  private var hasLoadedInitially = false
  private var inFlightLoads = 0
  private var loadWaiters: [CheckedContinuation<Void, Never>] = []
  private var deleteTask: Task<Void, Never>?
  private var pendingDeleteAuthorization: LocalMutationAuthorization?
  private var cancellables = Set<AnyCancellable>()
  private var didRegisterAutomationActions = false

  init(
    storage: any MemoryPageStorage = MemoryStorage.shared,
    clock: @escaping Clock = Date.init,
    sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
    searchCoordinator: DebouncedSearchCoordinator = DebouncedSearchCoordinator()
  ) {
    self.storage = storage
    self.clock = clock
    self.sleeper = sleeper
    self.searchCoordinator = searchCoordinator

    NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)
      .sink { [weak self] _ in MainActor.assumeIsolated { self?.resetSessionState() } }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in Task { await self?.refreshMemoriesIfNeeded() } }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: .refreshAllData)
      .sink { [weak self] _ in Task { await self?.refreshMemoriesIfNeeded() } }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: .conversationDeleted)
      .sink { [weak self] notification in
        guard let id = notification.userInfo?["conversationId"] as? String else { return }
        Task { await self?.handleConversationDeleted(id) }
      }
      .store(in: &cancellables)
  }

  func tagCount(_ tag: MemoryTag) -> Int { tagCounts[tag] ?? 0 }

  func resetSessionState() {
    deleteTask?.cancel()
    deleteTask = nil
    memories = []
    isLoading = false
    isLoadingMore = false
    hasMoreMemories = true
    errorMessage = nil
    searchText = ""
    searchResults = []
    selectedLayerFilter = .defaultAccess
    selectedTags = []
    isLoadingFiltered = false
    showingAddMemory = false
    newMemoryText = ""
    editText = ""
    selectedMemory = nil
    pendingDeleteMemory = nil
    pendingDeleteAuthorization = nil
    undoTimeRemaining = 0
    showingDeleteAllConfirmation = false
    isBulkOperationInProgress = false
    linkedConversation = nil
    isLoadingConversation = false
    currentOffset = 0
    displayLimit = pageSize
    allFilteredResults = []
    tagCounts = [:]
    totalMemoriesCount = 0
    hasMoreFilteredResults = false
    hasLoadedInitially = false
    isActive = false
    scopeGeneration += 1
  }

  func loadMemoriesIfNeeded() async {
    guard !hasLoadedInitially else { return }
    await loadMemories()
  }

  func loadMemories() async {
    guard !isLoading else { return }
    let generation = scopeGeneration
    isLoading = true
    inFlightLoads += 1
    defer {
      inFlightLoads -= 1
      isLoading = false
      resumeLoadWaitersIfIdle()
    }
    do {
      let loaded = try await storage.list(
        scope: selectedLayerFilter.layerScope,
        categories: [], tags: [], includeDismissed: false,
        limit: pageSize, offset: 0)
      guard generation == scopeGeneration else { return }
      memories = loaded
      currentOffset = loaded.count
      hasMoreMemories = loaded.count == pageSize
      hasLoadedInitially = true
      errorMessage = nil
      await refreshCounts(generation: generation)
    } catch {
      guard generation == scopeGeneration else { return }
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memories)
    }
  }

  func refreshMemoriesIfNeeded() async {
    refreshInvocations += 1
    guard isActive else { return }
    await waitForLoadToSettle()
    guard pendingDeleteMemory == nil else { return }
    await loadMemories()
  }

  func loadMoreIfNeeded(currentMemory: MemoryItem) async {
    guard let index = filteredMemories.firstIndex(where: { $0.id == currentMemory.id }) else { return }
    guard filteredMemories.count - index <= 10 else { return }
    if isInFilteredMode {
      loadMoreFiltered()
    } else {
      await loadMore()
    }
  }

  func loadMore() async {
    guard !isLoadingMore, hasMoreMemories else { return }
    let generation = scopeGeneration
    let requestedOffset = currentOffset
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await storage.list(
        scope: selectedLayerFilter.layerScope,
        categories: [], tags: [], includeDismissed: false,
        limit: pageSize, offset: requestedOffset)
      guard generation == scopeGeneration, requestedOffset == currentOffset else { return }
      let existing = Set(memories.map(\.id))
      memories.append(contentsOf: page.filter { !existing.contains($0.id) })
      currentOffset += page.count
      hasMoreMemories = page.count == pageSize
      errorMessage = nil
    } catch {
      guard generation == scopeGeneration else { return }
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memories)
    }
  }

  func loadMoreFiltered() {
    displayLimit += pageSize
    filteredMemories = Array(allFilteredResults.prefix(displayLimit))
    hasMoreFilteredResults = allFilteredResults.count > displayLimit
  }

  func createMemory() async {
    do {
      _ = try await storage.acceptExplicitAssertion(
        content: newMemoryText, now: clock(), authorization: try ownerAuthorization())
      newMemoryText = ""
      showingAddMemory = false
      hasLoadedInitially = false
      await loadMemories()
    } catch {
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memories)
    }
  }

  @discardableResult
  func saveEditedMemory(_ memory: MemoryItem) async -> Bool {
    let trimmedDraft = editText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDraft.isEmpty else { return false }
    do {
      let saved = try await storage.correct(
        id: memory.id,
        expectedRevision: memory.revision,
        content: trimmedDraft,
        now: clock(),
        ownerGeneration: await RewindDatabase.shared.poolGeneration(),
        authorization: try ownerAuthorization())
      replaceMemory(saved)
      editText = ""
      await refreshSelectedMemory()
      return true
    } catch {
      // The inline editor owns this rare local-acceptance failure. Keep its
      // draft open without replacing the entire page with a global error view.
      return false
    }
  }

  func deleteMemory(_ memory: MemoryItem) async {
    let authorization: LocalMutationAuthorization
    do {
      authorization = try ownerAuthorization()
    } catch {
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memoryDeletion)
      return
    }
    if let pending = pendingDeleteMemory, pending.id != memory.id {
      deleteTask?.cancel()
      deleteTask = nil
      do {
        try await storage.finalizeDeletion(
          id: pending.id,
          authorization: pendingDeleteAuthorization ?? authorization)
        pendingDeleteMemory = nil
        pendingDeleteAuthorization = nil
        undoTimeRemaining = 0
        if selectedMemory?.id == pending.id { selectedMemory = nil }
      } catch {
        errorMessage = UserFacingErrorPresentation.message(for: error, while: .memoryDeletion)
        return
      }
    }
    deleteTask?.cancel()
    do {
      _ = try await storage.beginDeletion(
        id: memory.id, now: clock(), authorization: authorization)
      removeMemory(id: memory.id)
      pendingDeleteMemory = memory
      pendingDeleteAuthorization = authorization
      undoTimeRemaining = 4
      deleteTask = Task { [weak self] in
        guard let self else { return }
        for remaining in stride(from: 3, through: 0, by: -1) {
          do { try await self.sleeper(1_000_000_000) } catch { return }
          guard !Task.isCancelled else { return }
          self.undoTimeRemaining = Double(remaining)
        }
        await self.finalizePendingDelete(expectedID: memory.id)
      }
    } catch {
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memoryDeletion)
    }
  }

  func undoDelete() async {
    guard let memory = pendingDeleteMemory else { return }
    deleteTask?.cancel()
    deleteTask = nil
    do {
      guard let authorization = pendingDeleteAuthorization else {
        throw LocalMutationAuthorizationError.revoked
      }
      try await storage.undoDeletion(
        id: memory.id, now: clock(), authorization: authorization)
      pendingDeleteMemory = nil
      pendingDeleteAuthorization = nil
      undoTimeRemaining = 0
      await reloadCurrentScope()
    } catch {
      await finalizePendingDelete(expectedID: memory.id)
    }
  }

  @discardableResult
  func confirmDelete() -> Task<Void, Never> {
    deleteTask?.cancel()
    deleteTask = nil
    let expectedID = pendingDeleteMemory?.id
    return Task { [weak self] in
      guard let self, let expectedID else { return }
      await self.finalizePendingDelete(expectedID: expectedID)
    }
  }

  private func finalizePendingDelete(expectedID: String) async {
    guard pendingDeleteMemory?.id == expectedID else { return }
    do {
      guard let authorization = pendingDeleteAuthorization else {
        throw LocalMutationAuthorizationError.revoked
      }
      try await storage.finalizeDeletion(id: expectedID, authorization: authorization)
      pendingDeleteMemory = nil
      pendingDeleteAuthorization = nil
      undoTimeRemaining = 0
      if selectedMemory?.id == expectedID { selectedMemory = nil }
      await refreshCounts(generation: scopeGeneration)
    } catch {
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memoryDeletion)
    }
  }

  func deleteMemories(scope: MemoryLayerScope) async {
    guard scope == .defaultAccess else { return }
    _ = confirmDelete()
    isBulkOperationInProgress = true
    defer { isBulkOperationInProgress = false }
    do {
      try await storage.deleteDefaultMemories(authorization: try ownerAuthorization())
      pendingDeleteMemory = nil
      pendingDeleteAuthorization = nil
      undoTimeRemaining = 0
      if selectedMemory?.layer.isDefaultAccessible == true { selectedMemory = nil }
      await reloadCurrentScope()
    } catch {
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memoryDeletion)
    }
  }

  func memories(withIDs ids: [String]) async -> [MemoryItem] {
    do { return try await storage.memories(ids: ids) } catch { return [] }
  }

  func refreshSelectedMemory() async {
    guard let id = selectedMemory?.id else { return }
    if let visible = memories.first(where: { $0.id == id }) {
      selectedMemory = visible
      return
    }
    selectedMemory = try? await storage.memory(id: id, includePendingDelete: false)
  }

  func openMemory(id: String) async -> Bool {
    guard let memory = try? await storage.memory(id: id, includePendingDelete: false) else {
      selectedMemory = nil
      return false
    }
    selectedMemory = memory
    return true
  }

  func handleConversationDeleted(_ conversationId: String) async {
    conversationDeleteInvocations += 1
    memories.removeAll { $0.conversationId == conversationId }
    if selectedMemory?.conversationId == conversationId { selectedMemory = nil }
    if hasLoadedInitially { await reloadCurrentScope() }
  }

  func navigateToConversation(id: String) async {
    isLoadingConversation = true
    defer { isLoadingConversation = false }
    do {
      linkedConversation = try await LocalAuthorityConversationDataSource().detail(id: id)
    } catch {
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .conversations)
    }
  }

  func dismissConversation() { linkedConversation = nil }

  private func ownerAuthorization() throws -> LocalMutationAuthorization {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    return LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
  }

  func registerAutomationActions() {
    guard !didRegisterAutomationActions else { return }
    didRegisterAutomationActions = true
    let registry = DesktopAutomationActionRegistry.shared
    registry.register(
      name: "memories_search",
      summary: "Set the local Memory search query and return its result count",
      params: ["query"]
    ) { [weak self] params in
      guard let self else { return ["error": "memories view model deallocated"] }
      let query = params["query"] ?? ""
      self.searchText = query
      let deadline = Date().addingTimeInterval(3)
      while self.isSearching, Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
      }
      return ["query": query, "result_count": "\(self.filteredMemories.count)"]
    }
    registry.register(
      name: "memories_set_tag_filter",
      summary: "Set local Memory category filters and return the result count",
      params: ["tags"]
    ) { [weak self] params in
      guard let self else { return ["error": "memories view model deallocated"] }
      self.selectedTags = Set(
        (params["tags"] ?? "").split(separator: ",")
          .compactMap { MemoryTag(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) })
      let deadline = Date().addingTimeInterval(3)
      while self.isLoadingFiltered, Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
      }
      return ["filtered_count": "\(self.filteredMemories.count)"]
    }
  }

  private func reloadCurrentScope() async {
    hasLoadedInitially = false
    await loadMemories()
    let query = DebouncedSearchCoordinator.normalized(searchText)
    if !query.isEmpty { await performSearch(query) }
    if !selectedTags.isEmpty { await reloadFilteredResults() }
  }

  private func reloadFilteredResults() async {
    let generation = scopeGeneration
    guard !selectedTags.isEmpty else {
      recomputeCaches()
      return
    }
    isLoadingFiltered = true
    defer { isLoadingFiltered = false }
    do {
      let results = try await storage.list(
        scope: selectedLayerFilter.layerScope,
        categories: selectedTags.map(\.category),
        tags: [], includeDismissed: false, limit: 10_000, offset: 0)
      guard generation == scopeGeneration else { return }
      allFilteredResults = results
      recomputeCaches()
    } catch {
      guard generation == scopeGeneration else { return }
      errorMessage = UserFacingErrorPresentation.message(for: error, while: .memories)
    }
  }

  private func performSearch(_ query: String) async {
    let generation = scopeGeneration
    guard !query.isEmpty else {
      searchResults = []
      isSearching = false
      recomputeCaches()
      return
    }
    isSearching = true
    defer { isSearching = false }
    do {
      let results = try await storage.literalSearch(
        query,
        scope: selectedLayerFilter.layerScope,
        categories: selectedTags.map(\.category),
        tags: [], includeDismissed: false, limit: 10_000, offset: 0)
      guard generation == scopeGeneration else { return }
      searchResults = results
      recomputeCaches()
    } catch {
      guard generation == scopeGeneration else { return }
      searchResults = memories.filter { $0.content.localizedCaseInsensitiveContains(query) }
      recomputeCaches()
    }
  }

  private func recomputeCaches() {
    let query = DebouncedSearchCoordinator.normalized(searchText)
    var source: [MemoryItem]
    if !query.isEmpty {
      source = searchResults
    } else if !selectedTags.isEmpty {
      source = allFilteredResults
    } else {
      source = memories
    }
    source.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
    if isInFilteredMode {
      filteredMemories = Array(source.prefix(displayLimit))
      hasMoreFilteredResults = source.count > displayLimit
    } else {
      filteredMemories = source
      hasMoreFilteredResults = false
    }
    var counts: [MemoryTag: Int] = [:]
    for tag in MemoryTag.allCases { counts[tag] = memories.filter(tag.matches).count }
    tagCounts = counts
  }

  private func refreshCounts(generation: Int) async {
    do {
      let total = try await storage.count(
        scope: selectedLayerFilter.layerScope,
        categories: [], tags: [], includeDismissed: false)
      guard generation == scopeGeneration else { return }
      totalMemoriesCount = total
      var counts: [MemoryTag: Int] = [:]
      for tag in MemoryTag.allCases {
        counts[tag] = try await storage.count(
          scope: selectedLayerFilter.layerScope,
          categories: [tag.category], tags: [], includeDismissed: false)
      }
      guard generation == scopeGeneration else { return }
      tagCounts = counts
    } catch {
      // The already-loaded page remains usable; the counts fall back to it.
      recomputeCaches()
    }
  }

  private func replaceMemory(_ memory: MemoryItem) {
    if let index = memories.firstIndex(where: { $0.id == memory.id }) {
      memories[index] = memory
    }
    if selectedMemory?.id == memory.id { selectedMemory = memory }
  }

  private func removeMemory(id: String) {
    memories.removeAll { $0.id == id }
    searchResults.removeAll { $0.id == id }
    allFilteredResults.removeAll { $0.id == id }
    recomputeCaches()
  }

  private var isLoadActive: Bool { inFlightLoads > 0 || isLoading || isLoadingMore }

  private func waitForLoadToSettle() async {
    guard isLoadActive else { return }
    await withCheckedContinuation { continuation in
      guard isLoadActive else {
        continuation.resume()
        return
      }
      loadWaiters.append(continuation)
      memoryLoadLifecycleWaiterCount = loadWaiters.count
    }
  }

  private func resumeLoadWaitersIfIdle() {
    guard !isLoadActive else { return }
    let waiters = loadWaiters
    loadWaiters.removeAll()
    memoryLoadLifecycleWaiterCount = 0
    waiters.forEach { $0.resume() }
  }
}
