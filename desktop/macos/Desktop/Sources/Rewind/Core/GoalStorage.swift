import Foundation
@preconcurrency import GRDB

enum GoalStorageError: LocalizedError {
  case databaseNotInitialized
  case recordNotFound
  case invalidInput

  var errorDescription: String? {
    switch self {
    case .databaseNotInitialized: return "Goal storage database is not initialized"
    case .recordNotFound: return "Goal record not found"
    case .invalidInput: return "Goal title is required"
    }
  }
}

actor GoalStorage {
  static let shared = GoalStorage()

  private var dbQueue: DatabasePool?
  private var dbGeneration = -1

  private init() {}

  func invalidateCache() {
    dbQueue = nil
    dbGeneration = -1
  }

  private func ensureInitialized() async throws -> DatabasePool {
    if let dbQueue, await RewindDatabase.shared.poolGeneration() == dbGeneration {
      return dbQueue
    }
    try await RewindDatabase.shared.initialize()
    let (queue, generation) = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    guard let queue else { throw GoalStorageError.databaseNotInitialized }
    dbQueue = queue
    dbGeneration = generation
    return queue
  }

  private static func rowID(for surfacedID: String) throws -> Int64 {
    guard surfacedID.hasPrefix("local_"), let id = Int64(surfacedID.dropFirst(6)) else {
      throw GoalStorageError.recordNotFound
    }
    return id
  }

  func getLocalGoals(activeOnly: Bool = true) async throws -> [LocalGoal] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      var request = GoalRecord.all()
      if activeOnly { request = request.filter(Column("isActive") == true) }
      return
        try request
        .order(Column("isActive").desc, Column("createdAt").desc, Column("id").desc)
        .fetchAll(database)
        .compactMap { $0.toLocalGoal() }
    }
  }

  /// Complete, deterministic, owner-scoped page for S-08's offline export
  /// composition. Both active and completed goals are included.
  func getLocalExportPage(limit: Int = 100, offset: Int = 0) async throws -> [LocalGoal] {
    let db = try await ensureInitialized()
    return try await db.read { database in
      try GoalRecord.all()
        .order(Column("createdAt").asc, Column("id").asc)
        .limit(max(0, limit), offset: max(0, offset))
        .fetchAll(database)
        .compactMap { $0.toLocalGoal() }
    }
  }

  @discardableResult
  func createGoal(
    title: String,
    description: String?,
    authorization: LocalMutationAuthorization
  ) async throws -> LocalGoal {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty else { throw GoalStorageError.invalidInput }
    let normalizedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    let now = Date()
    let record = GoalRecord(
      title: normalizedTitle,
      goalDescription: normalizedDescription?.isEmpty == true ? nil : normalizedDescription,
      isActive: true,
      completedAt: nil,
      createdAt: now,
      updatedAt: now
    )
    try authorization.require()
    let db = try await ensureInitialized()
    let inserted = try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        let inserted = try record.inserted(database)
        try authorization.require()
        return inserted
      }
    }
    guard let goal = inserted.toLocalGoal() else { throw GoalStorageError.recordNotFound }
    return goal
  }

  @discardableResult
  func updateGoal(
    surfacedID: String,
    title: String,
    description: String?,
    authorization: LocalMutationAuthorization
  ) async throws -> LocalGoal {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty else { throw GoalStorageError.invalidInput }
    let rowID = try Self.rowID(for: surfacedID)
    let normalizedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    try authorization.require()
    let db = try await ensureInitialized()
    let record = try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard var record = try GoalRecord.fetchOne(database, key: rowID) else {
          throw GoalStorageError.recordNotFound
        }
        record.title = normalizedTitle
        record.goalDescription = normalizedDescription?.isEmpty == true ? nil : normalizedDescription
        record.updatedAt = Date()
        try record.update(database)
        try authorization.require()
        return record
      }
    }
    guard let goal = record.toLocalGoal() else { throw GoalStorageError.recordNotFound }
    return goal
  }

  @discardableResult
  func setCompleted(
    surfacedID: String,
    completed: Bool,
    authorization: LocalMutationAuthorization
  ) async throws -> LocalGoal {
    let rowID = try Self.rowID(for: surfacedID)
    try authorization.require()
    let db = try await ensureInitialized()
    let record = try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard var record = try GoalRecord.fetchOne(database, key: rowID) else {
          throw GoalStorageError.recordNotFound
        }
        record.isActive = !completed
        record.completedAt = completed ? Date() : nil
        record.updatedAt = Date()
        try record.update(database)
        try authorization.require()
        return record
      }
    }
    guard let goal = record.toLocalGoal() else { throw GoalStorageError.recordNotFound }
    return goal
  }
}
