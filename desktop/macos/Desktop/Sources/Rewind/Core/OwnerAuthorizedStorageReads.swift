import Foundation

extension ActionItemStorage {
  func getFilterCounts(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> (todo: Int, done: Int, deleted: Int) {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getFilterCounts()
    }
  }

  func getFilteredActionItems(
    limit: Int = 200,
    offset: Int = 0,
    completedStates: [Bool]? = nil,
    includeDeleted: Bool = false,
    dueDateAfter: Date? = nil,
    dueDateBefore: Date? = nil,
    dueDateIsNull: Bool? = nil,
    createdAfter: Date? = nil,
    createdBefore: Date? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [TaskActionItem] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getFilteredActionItems(
        limit: limit,
        offset: offset,
        completedStates: completedStates,
        includeDeleted: includeDeleted,
        dueDateAfter: dueDateAfter,
        dueDateBefore: dueDateBefore,
        dueDateIsNull: dueDateIsNull,
        createdAfter: createdAfter,
        createdBefore: createdBefore)
    }
  }

  func getLocalActionItem(
    surfacedId: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> TaskActionItem? {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getLocalActionItem(surfacedId: surfacedId)
    }
  }

  func getAllEmbeddings(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, embedding: Data)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getAllEmbeddings()
    }
  }

  func getItemsMissingEmbeddings(
    limit: Int = 100,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, description: String)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getItemsMissingEmbeddings(limit: limit)
    }
  }

  func getLocalActionItems(
    limit: Int = 50,
    offset: Int = 0,
    completed: Bool? = nil,
    includeDeleted: Bool = false,
    startDate: Date? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [TaskActionItem] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getLocalActionItems(
        limit: limit,
        offset: offset,
        completed: completed,
        includeDeleted: includeDeleted,
        startDate: startDate)
    }
  }

  func getLocalActionItemsCount(
    completed: Bool? = nil,
    includeDeleted: Bool = false,
    startDate: Date? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Int {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getLocalActionItemsCount(
        completed: completed,
        includeDeleted: includeDeleted,
        startDate: startDate
      )
    }
  }

  func getActionItem(
    id: Int64,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> ActionItemRecord? {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getActionItem(id: id)
    }
  }

  func getRecentActiveTasks(
    limit: Int = 30,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, description: String, priority: String?)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getRecentActiveTasks(limit: limit)
    }
  }

  func getRecentCompletedTasks(
    limit: Int = 10,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, description: String)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getRecentCompletedTasks(limit: limit)
    }
  }

  func getRecentDeletedTasks(
    limit: Int = 10,
    deletedBy: String? = "user",
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, description: String)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getRecentDeletedTasks(limit: limit, deletedBy: deletedBy)
    }
  }

  func searchFTS(
    query: String,
    limit: Int = 20,
    includeCompleted: Bool = true,
    includeDeleted: Bool = false,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, description: String, completed: Bool, deleted: Bool, deletedBy: String?)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.searchFTS(
        query: query,
        limit: limit,
        includeCompleted: includeCompleted,
        includeDeleted: includeDeleted)
    }
  }

  private func withOwnerRead<T: Sendable>(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let result = try await operation()
      try authorization.require()
      return result
    }
  }
}

extension GoalStorage {
  func getLocalGoals(
    activeOnly: Bool = true,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalGoal] {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let results = try await self.getLocalGoals(activeOnly: activeOnly)
      try authorization.require()
      return results
    }
  }
}

extension TranscriptionStorage {
  func conversationCount(
    query: ConversationLocalQuery,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Int {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let result = try await self.conversationCount(query: query)
      try authorization.require()
      return result
    }
  }

  func fairUseEvidence(
    now: Date = Date(),
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [FairUseConversationEvidence] {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let results = try await self.fairUseEvidence(now: now)
      try authorization.require()
      return results
    }
  }

  func conversationPage(
    query: ConversationLocalQuery,
    offset: Int,
    limit: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalConversationSummary] {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let results = try await self.conversationPage(
        query: query,
        offset: offset,
        limit: limit)
      try authorization.require()
      return results
    }
  }
}

extension MemoryStorage {
  func getStats(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> MemoryStats {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let result = try await self.getStats()
      try authorization.require()
      return result
    }
  }

  func listForTool(
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false,
    startDate: Date? = nil,
    endDate: Date? = nil,
    limit: Int = 100,
    offset: Int = 0,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [MemoryItem] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.listForTool(
        scope: scope,
        categories: categories,
        tags: tags,
        includeDismissed: includeDismissed,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
        offset: offset)
    }
  }

  func literalSearch(
    _ text: String,
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false,
    limit: Int = 100,
    offset: Int = 0,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [MemoryItem] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.literalSearch(
        text,
        scope: scope,
        categories: categories,
        tags: tags,
        includeDismissed: includeDismissed,
        limit: limit,
        offset: offset)
    }
  }

  func list(
    scope: MemoryLayerScope = .defaultAccess,
    categories: [MemoryCategory] = [],
    tags: [String] = [],
    includeDismissed: Bool = false,
    limit: Int = 100,
    offset: Int = 0,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [MemoryItem] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.list(
        scope: scope,
        categories: categories,
        tags: tags,
        includeDismissed: includeDismissed,
        limit: limit,
        offset: offset)
    }
  }

  private func withOwnerRead<T: Sendable>(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let result = try await operation()
      try authorization.require()
      return result
    }
  }
}

extension RewindStorage {
  func loadScreenshotData(
    for screenshot: Screenshot,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Data {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let data = try await self.loadScreenshotData(for: screenshot)
      try authorization.require()
      return data
    }
  }
}

extension ProactiveStorage {
  func getTotalFocusSessionCount(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Int {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    return try await authorization.withReadLease {
      try authorization.require()
      let result = try await self.getTotalFocusSessionCount()
      try authorization.require()
      return result
    }
  }
}
