import Foundation
@preconcurrency import GRDB

extension RewindDatabase {
  @discardableResult
  func insertScreenshot(
    _ screenshot: Screenshot,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Screenshot {
    guard let databasePool = getDatabaseQueue() else {
      throw RewindError.databaseNotInitialized
    }
    let authorization = ownerAuthorization(authorizationSnapshot)
    return try await authorization.withCommitLease {
      try await databasePool.write { database in
        try authorization.require()
        if let videoChunkPath = screenshot.videoChunkPath, !videoChunkPath.isEmpty {
          try RewindAbandonedVideoChunkQuarantine.requireAvailable(
            database,
            videoChunkPath: videoChunkPath)
        }
        var record = screenshot
        if record.imagePath == nil { record.imagePath = "" }
        try record.insert(database)
        try authorization.require()
        return record
      }
    }
  }

  /// Owner-generation-aware hydration for delayed UI/provider work. The
  /// snapshot is checked on the database actor immediately before and after
  /// reading so a retargeted database can never satisfy an older operation.
  func getScreenshot(
    id: Int64,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Screenshot? {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getScreenshot(id: id)
    }
  }

  func getRecentScreenshots(
    limit: Int = 100,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Screenshot] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getRecentScreenshots(limit: limit)
    }
  }

  func isAvailable(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Bool {
    try await withOwnerRead(authorizationSnapshot) {
      await self.getDatabaseQueue() != nil
    }
  }

  /// Owner-generation-aware FTS for delayed work that can outlive an account
  /// transition. Callers must still revalidate immediately before publication.
  func search(
    query: String,
    appFilter: String? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    limit: Int = 100,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Screenshot] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.search(
        query: query,
        appFilter: appFilter,
        startDate: startDate,
        endDate: endDate,
        limit: limit)
    }
  }

  func getScreenshotsMissingEmbeddings(
    limit: Int = 100,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(id: Int64, ocrText: String, appName: String, windowTitle: String?)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getScreenshotsMissingEmbeddings(limit: limit)
    }
  }

  func getScreenshotEmbeddingBackfillStatus(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> (completed: Bool, processedCount: Int) {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getScreenshotEmbeddingBackfillStatus()
    }
  }

  func readEmbeddingBatch(
    startDate: Date,
    endDate: Date,
    appFilter: String? = nil,
    limit: Int = 5000,
    offset: Int = 0,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [(screenshotId: Int64, embedding: Data)] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.readEmbeddingBatch(
        startDate: startDate,
        endDate: endDate,
        appFilter: appFilter,
        limit: limit,
        offset: offset)
    }
  }

  func getScreenshotsSampled(
    from startDate: Date,
    to endDate: Date,
    targetCount: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Screenshot] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getScreenshotsSampled(
        from: startDate,
        to: endDate,
        targetCount: targetCount)
    }
  }

  func getUniqueAppNames(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [String] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getUniqueAppNames()
    }
  }

  func getStats(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> (total: Int, indexed: Int, oldestDate: Date?, newestDate: Date?) {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getStats()
    }
  }

  func getScreenshotCount(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Int {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getScreenshotCount()
    }
  }

  func getBatterySkippedScreenshots(
    limit: Int = 10,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Screenshot] {
    try await withOwnerRead(authorizationSnapshot) {
      try await self.getBatterySkippedScreenshots(limit: limit)
    }
  }

  func deleteScreenshotAndArtifacts(
    id: Int64,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Bool {
    let authorization = ownerAuthorization(authorizationSnapshot)
    return try await authorization.withCommitLease {
      try authorization.require()
      guard let result = try await self.deleteScreenshot(id: id) else { return false }
      try authorization.require()
      if let imagePath = result.imagePath {
        try await RewindStorage.shared.deleteScreenshot(relativePath: imagePath)
      }
      try authorization.require()
      if result.isLastFrameInChunk, let videoChunkPath = result.videoChunkPath {
        try await RewindStorage.shared.deleteVideoChunk(relativePath: videoChunkPath)
      }
      try authorization.require()
      return true
    }
  }

  func updateScreenshotEmbedding(
    id: Int64,
    embedding: Data,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws {
    guard let databasePool = getDatabaseQueue() else {
      throw RewindError.databaseNotInitialized
    }
    let authorization = ownerAuthorization(authorizationSnapshot)
    try await authorization.withCommitLease {
      try await databasePool.write { database in
        try authorization.require()
        try database.execute(
          sql: "UPDATE screenshots SET embedding = ? WHERE id = ?",
          arguments: [embedding, id])
        try authorization.require()
      }
    }
  }

  func updateOCRResult(
    id: Int64,
    ocrResult: OCRResult,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws {
    let authorization = ownerAuthorization(authorizationSnapshot)
    try await authorization.withCommitLease {
      try authorization.require()
      try await self.updateOCRResult(id: id, ocrResult: ocrResult)
      try authorization.require()
    }
  }

  func clearSkippedForBattery(
    id: Int64,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws {
    let authorization = ownerAuthorization(authorizationSnapshot)
    try await authorization.withCommitLease {
      try authorization.require()
      try await self.clearSkippedForBattery(id: id)
      try authorization.require()
    }
  }

  func updateScreenshotEmbeddingBackfillStatus(
    completed: Bool,
    processedCount: Int,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws {
    guard let databasePool = getDatabaseQueue() else {
      throw RewindError.databaseNotInitialized
    }
    let authorization = ownerAuthorization(authorizationSnapshot)
    try await authorization.withCommitLease {
      try await databasePool.write { database in
        try authorization.require()
        try database.execute(
          sql: """
            UPDATE migration_status
            SET completed = ?, processedCount = ?, completedAt = CASE WHEN ? = 1 THEN datetime('now') ELSE completedAt END
            WHERE name = 'screenshot_embedding_backfill'
            """,
          arguments: [completed ? 1 : 0, processedCount, completed ? 1 : 0])
        try authorization.require()
      }
    }
  }

  private func withOwnerRead<T: Sendable>(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let authorization = ownerAuthorization(authorizationSnapshot)
    return try await authorization.withReadLease {
      try authorization.require()
      let result = try await operation()
      try authorization.require()
      return result
    }
  }

  private nonisolated func ownerAuthorization(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) -> LocalMutationAuthorization {
    LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
  }
}
