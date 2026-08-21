import Foundation
@preconcurrency import GRDB

enum AIUserProfileInputPolicy {
  static let memoryLimit = 100
  static let taskLimit = 50
  static let conversationLimit = 20
  static let conversationLookbackDays = 7
  static let journalMessageLimit = 30
  static let priorProfileLimit = 5
  static let settingsHistoryLimit = 30

  static func conversationQuery(now: Date = Date()) -> ConversationLocalQuery {
    ConversationLocalQuery(
      starredOnly: false,
      startDate: Calendar.current.date(
        byAdding: .day,
        value: -conversationLookbackDays,
        to: now),
      endDate: nil,
      folderId: nil,
      statuses: [.completed])
  }
}

struct AIUserProfileInputs: Sendable {
  let memories: [String]
  let tasks: [String]
  let goals: [String]
  let conversations: [String]
  let journalMessages: [String]
}

// MARK: - Database Record

/// Database record for AI-generated user profile history
struct AIUserProfileRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  var id: Int64?
  var profileText: String
  var dataSourcesUsed: Int
  var generatedAt: Date

  static let databaseTableName = "ai_user_profiles"

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

// MARK: - TableDocumented

extension AIUserProfileRecord: TableDocumented {
  static var tableDescription: String { ChatPrompts.tableAnnotations["ai_user_profiles"]! }
  static var columnDescriptions: [String: String] { ChatPrompts.columnAnnotations["ai_user_profiles"] ?? [:] }
}

// MARK: - Service

/// Service that generates and maintains an AI-generated user profile.
/// Inspired by the ContextAgent paper (arXiv:2505.14668).
/// Runs once daily, fetches data from multiple sources, and calls Gemini to synthesize a concise profile.
/// All generated profiles are stored in the local database for history tracking.
actor AIUserProfileService {
  static let shared = AIUserProfileService()

  typealias TextRequest =
    @Sendable (
      _ prompt: String,
      _ systemPrompt: String,
      _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
    ) async throws -> String
  typealias DataSourceLoader =
    @Sendable (_ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot) async -> AIUserProfileInputs

  private let maxProfileLength = 10000
  private let textRequest: TextRequest
  private let dataSourceLoader: DataSourceLoader?

  /// Whether profile generation is currently in progress
  private var isGenerating = false

  /// Cached database pool
  private var _dbQueue: DatabasePool?
  private var _dbGeneration = -1

  init(
    textRequest: @escaping TextRequest = { prompt, systemPrompt, authorizationSnapshot in
      try await AIUserProfileService.performAuthorizedTextRequest(
        authorizationSnapshot: authorizationSnapshot
      ) {
        let gemini = try GeminiClient()
        return try await gemini.sendTextRequest(prompt: prompt, systemPrompt: systemPrompt)
      }
    },
    dataSourceLoader: DataSourceLoader? = nil
  ) {
    self.textRequest = textRequest
    self.dataSourceLoader = dataSourceLoader
  }

  /// The authorization check lives immediately around the outbound request,
  /// not only around prompt construction. Reauthenticating as the same UID
  /// advances the generation and therefore prevents stale private context
  /// from leaving the process.
  static func performAuthorizedTextRequest(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    request: @Sendable () async throws -> String
  ) async throws -> String {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    let response = try await request()
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    return response
  }

  /// Invalidate cached DB queue (called on user switch / sign-out)
  func invalidateCache() {
    _dbQueue = nil
  }

  // MARK: - Database Access

  private func ensureDB() async throws -> DatabasePool {
    if let db = _dbQueue, await RewindDatabase.shared.poolGeneration() == _dbGeneration { return db }
    try await RewindDatabase.shared.initialize()
    let (queue, generation) = await RewindDatabase.shared.getDatabaseQueueWithGeneration()
    guard let db = queue else {
      throw ProfileError.databaseNotAvailable
    }
    _dbQueue = db
    _dbGeneration = generation
    return db
  }

  // MARK: - Public Interface

  /// Check if we should generate a new profile (>24h since last generation)
  func shouldGenerate() async -> Bool {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return false }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      return try await authorization.withReadLease {
        try authorization.require()
        let db = try await self.ensureDB()
        try authorization.require()
        let latest = try await db.read { database in
          try authorization.require()
          return
            try AIUserProfileRecord
            .order(Column("generatedAt").desc)
            .fetchOne(database)
        }
        try authorization.require()
        guard let latest else { return true }
        return Date().timeIntervalSince(latest.generatedAt) > 86400
      }
    } catch {
      return RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
  }

  /// Get the latest stored profile
  func getLatestProfile() async -> AIUserProfileRecord? {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return nil }
    return await getLatestProfile(authorizationSnapshot: snapshot)
  }

  func getLatestProfile(
    authorizationSnapshot snapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> AIUserProfileRecord? {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      return try await authorization.withReadLease {
        try authorization.require()
        let db = try await self.ensureDB()
        try authorization.require()
        let profile = try await db.read { database in
          try authorization.require()
          return
            try AIUserProfileRecord
            .order(Column("generatedAt").desc)
            .fetchOne(database)
        }
        try authorization.require()
        return profile
      }
    } catch {
      return nil
    }
  }

  /// Delete a profile by ID and return the next latest profile
  func deleteProfile(id: Int64) async -> AIUserProfileRecord? {
    guard let authorization = currentOwnerAuthorization() else { return nil }
    guard let db = try? await ensureDB() else { return nil }
    do {
      let nextProfile = try await authorization.withCommitLease {
        try await db.write { database in
          try authorization.require()
          try database.execute(
            sql: "DELETE FROM ai_user_profiles WHERE id = ?",
            arguments: [id]
          )
          let next =
            try AIUserProfileRecord
            .order(Column("generatedAt").desc)
            .fetchOne(database)
          try authorization.require()
          return next
        }
      }
      try authorization.require()
      return nextProfile
    } catch {
      log("AIUserProfileService: Failed to delete profile: \(error.localizedDescription)")
      return nil
    }
  }

  /// Update the profile text of an existing local record.
  func updateProfileText(id: Int64, newText: String) async -> Bool {
    guard let authorization = currentOwnerAuthorization() else { return false }
    guard let db = try? await ensureDB() else { return false }
    do {
      try await authorization.withCommitLease {
        try await db.write { database in
          try authorization.require()
          try database.execute(
            sql: "UPDATE ai_user_profiles SET profileText = ? WHERE id = ?",
            arguments: [newText, id]
          )
          try authorization.require()
        }
      }
      try authorization.require()
      return true
    } catch {
      log("AIUserProfileService: Failed to update profile text: \(error.localizedDescription)")
      return false
    }
  }

  /// Save exploration text as a new profile record (when no profile exists yet)
  func saveExplorationAsProfile(text: String) async -> Bool {
    guard let authorization = currentOwnerAuthorization() else { return false }
    guard let db = try? await ensureDB() else {
      log("AIUserProfileService: DB not available for saving exploration profile")
      return false
    }
    let generatedAt = Date()
    let record = AIUserProfileRecord(
      profileText: String(text.prefix(maxProfileLength)),
      dataSourcesUsed: 1,
      generatedAt: generatedAt
    )
    do {
      _ = try await authorization.withCommitLease {
        try await db.write { database -> Int64? in
          try authorization.require()
          let mutableRecord = record
          try mutableRecord.insert(database)
          try authorization.require()
          return mutableRecord.id
        }
      }
      try authorization.require()
      log("AIUserProfileService: Saved exploration as new profile (\(record.profileText.count) chars)")

      return true
    } catch {
      log("AIUserProfileService: Failed to save exploration profile: \(error.localizedDescription)")
      return false
    }
  }

  /// Delete all stored profiles
  func deleteAllProfiles() async {
    guard let authorization = currentOwnerAuthorization() else { return }
    guard let db = try? await ensureDB() else { return }
    _ = try? await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(sql: "DELETE FROM ai_user_profiles")
        try authorization.require()
      }
    }
  }

  /// Get all stored profiles (newest first)
  func getAllProfiles(limit: Int = AIUserProfileInputPolicy.settingsHistoryLimit) async -> [AIUserProfileRecord] {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return [] }
    return await getAllProfiles(
      limit: limit,
      authorizationSnapshot: snapshot)
  }

  private func getAllProfiles(
    limit: Int,
    authorizationSnapshot snapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> [AIUserProfileRecord] {
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      return try await authorization.withReadLease {
        try authorization.require()
        let db = try await self.ensureDB()
        try authorization.require()
        let profiles = try await db.read { database in
          try authorization.require()
          return
            try AIUserProfileRecord
            .order(Column("generatedAt").desc)
            .limit(limit)
            .fetchAll(database)
        }
        try authorization.require()
        return profiles
      }
    } catch {
      return []
    }
  }

  /// Generate a new AI user profile from all available data sources
  func generateProfile() async throws -> AIUserProfileRecord {
    guard let ownerSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(ownerSnapshot)
    }
    guard !isGenerating else {
      throw ProfileError.alreadyGenerating
    }
    isGenerating = true
    defer { isGenerating = false }

    log("AIUserProfileService: Starting profile generation")

    // 1. Fetch all data sources in parallel
    let inputs =
      if let dataSourceLoader {
        await dataSourceLoader(ownerSnapshot)
      } else {
        await fetchDataSources(authorizationSnapshot: ownerSnapshot)
      }
    let memories = inputs.memories
    let tasks = inputs.tasks
    let goals = inputs.goals
    let conversations = inputs.conversations
    let journalMessages = inputs.journalMessages
    try authorization.require()

    // 2. Count total data items
    let dataSourcesUsed = memories.count + tasks.count + goals.count + conversations.count + journalMessages.count
    log(
      "AIUserProfileService: Fetched \(dataSourcesUsed) data items (memories=\(memories.count), tasks=\(tasks.count), goals=\(goals.count), convos=\(conversations.count))"
    )

    guard dataSourcesUsed > 0 else {
      throw ProfileError.insufficientData
    }

    // 3. Build prompt
    let prompt = buildPrompt(
      memories: memories,
      tasks: tasks,
      goals: goals,
      conversations: conversations,
      journalMessages: journalMessages)

    // 4. Call Gemini
    let systemPrompt = """
      You are generating a structured user profile that will be injected as context into AI pipelines \
      (task extraction, goal extraction, memory extraction) that analyze the user's screen and audio activity.

      OUTPUT FORMAT:
      - A flat list of factual statements, one per line, prefixed with "- "
      - Each statement must be a concrete fact directly supported by the provided data
      - No prose, no paragraphs, no headers, no markdown formatting
      - No adjectives like "passionate", "dedicated", "impressive"
      - Write in third person ("User works at...", not "You work at...")

      WHAT TO INCLUDE (only if clearly supported by the data):
      - Full name, role, company, industry
      - Current projects and what tools/apps they use for each
      - Key people they interact with (names, roles, relationship)
      - Active goals and their progress
      - Recurring meetings, deadlines, routines
      - Communication platforms they use (Slack, email, iMessage, etc.)
      - Technical stack, programming languages, frameworks
      - Topics they frequently discuss or research
      - Pending tasks and commitments to others
      - Time zone, work schedule patterns

      CRITICAL RULES:
      - ONLY include facts that are directly evidenced in the provided data
      - If a category has no supporting data, skip it entirely — do not guess or infer
      - Do NOT hallucinate names, roles, companies, or relationships not present in the data
      - Do NOT add personality descriptions or subjective assessments
      - When uncertain, omit rather than speculate
      - NEVER fabricate email addresses, phone numbers, URLs, or contact information
      - The provided data contains NO email addresses — do not invent any
      - If you cannot find a piece of information verbatim in the data, do not include it

      The output MUST be under 2000 characters total.
      """

    try authorization.require()
    let stageOneText = try await textRequest(prompt, systemPrompt, ownerSnapshot)
    try authorization.require()
    log("AIUserProfileService: Stage 1 complete (\(stageOneText.count) chars)")

    // 5. Stage 2 — Consolidate with past profiles for holistic view
    let pastProfiles = await getAllProfiles(
      limit: AIUserProfileInputPolicy.priorProfileLimit,
      authorizationSnapshot: ownerSnapshot)
    try authorization.require()
    let consolidationPrompt = buildConsolidationPrompt(
      newProfile: stageOneText,
      pastProfiles: pastProfiles
    )
    let consolidationSystemPrompt = """
        You are merging a newly generated user profile with historical profiles to create \
        one holistic, up-to-date user profile. This profile is injected as context into AI pipelines \
        (task extraction, goal extraction, memory extraction) that analyze the user's screen and audio activity.

        OUTPUT FORMAT:
        - A flat list of factual statements, one per line, prefixed with "- "
        - Each statement must be a concrete fact
        - No prose, no paragraphs, no headers, no markdown formatting
        - No adjectives or subjective assessments
        - Write in third person

        MERGE RULES:
        - The NEW profile reflects today's data and takes priority for current state
        - Past profiles provide historical context — retain facts that are still relevant
        - If a fact from the past contradicts the new profile, use the new one
        - Remove outdated information (completed tasks, past deadlines, old routines)
        - Keep stable facts (name, role, company, key relationships, tech stack)
        - Accumulate knowledge: if past profiles mention people, projects, or patterns \
          not in today's data, keep them if they seem ongoing
        - Do NOT hallucinate — only include facts present in the provided profiles
        - Do NOT add commentary about changes or evolution over time

        The output MUST be under 2000 characters total.
      """
    try authorization.require()
    let finalText = try await textRequest(
      consolidationPrompt,
      consolidationSystemPrompt,
      ownerSnapshot)
    try authorization.require()
    log("AIUserProfileService: Stage 2 consolidation complete (\(finalText.count) chars)")

    // 6. Truncate if needed
    let truncated = String(finalText.prefix(maxProfileLength))
    let generatedAt = Date()

    // 6. Save to database
    let db = try await ensureDB()
    let record = AIUserProfileRecord(
      profileText: truncated,
      dataSourcesUsed: dataSourcesUsed,
      generatedAt: generatedAt
    )
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try record.insert(database)
        try authorization.require()
      }
    }
    try authorization.require()

    log(
      "AIUserProfileService: Profile generated successfully (\(truncated.count) chars, \(dataSourcesUsed) data items)")
    return record
  }

  // MARK: - Data Fetching

  private func fetchDataSources(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> AIUserProfileInputs {
    async let memoriesTask = fetchMemories(authorizationSnapshot: authorizationSnapshot)
    async let tasksTask = fetchTasks(authorizationSnapshot: authorizationSnapshot)
    async let goalsTask = fetchGoals(authorizationSnapshot: authorizationSnapshot)
    async let conversationsTask = fetchConversations(
      authorizationSnapshot: authorizationSnapshot)
    async let journalTask = fetchJournalMessages(
      authorizationSnapshot: authorizationSnapshot)

    let memories = await memoriesTask
    let tasks = await tasksTask
    let goals = await goalsTask
    let conversations = await conversationsTask
    let journalMessages = await journalTask
    return AIUserProfileInputs(
      memories: memories,
      tasks: tasks,
      goals: goals,
      conversations: conversations,
      journalMessages: journalMessages)
  }

  private func fetchMemories(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> [String] {
    do {
      let memories = try await MemoryStorage.shared.list(
        limit: AIUserProfileInputPolicy.memoryLimit,
        authorizationSnapshot: authorizationSnapshot)
      return memories.map { "[\($0.category.rawValue)] \($0.content)" }
    } catch {
      log("AIUserProfileService: Failed to fetch memories: \(error.localizedDescription)")
      return []
    }
  }

  private func fetchTasks(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> [String] {
    do {
      let tasks = try await ActionItemStorage.shared.getLocalActionItems(
        limit: AIUserProfileInputPolicy.taskLimit,
        authorizationSnapshot: authorizationSnapshot)
      return tasks.map { item in
        let status = item.completed ? "done" : "todo"
        let priority = item.priority ?? "medium"
        return "[\(status)/\(priority)] \(item.description)"
      }
    } catch {
      log("AIUserProfileService: Failed to fetch tasks: \(error.localizedDescription)")
      return []
    }
  }

  private func fetchGoals(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> [String] {
    do {
      let goals = try await GoalStorage.shared.getLocalGoals(
        activeOnly: true,
        authorizationSnapshot: authorizationSnapshot)
      return goals.map(\.title)
    } catch {
      log("AIUserProfileService: Failed to fetch goals: \(error.localizedDescription)")
      return []
    }
  }

  private func fetchConversations(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> [String] {
    do {
      let conversations = try await TranscriptionStorage.shared.conversationPage(
        query: AIUserProfileInputPolicy.conversationQuery(),
        offset: 0,
        limit: AIUserProfileInputPolicy.conversationLimit,
        authorizationSnapshot: authorizationSnapshot)
      return conversations.compactMap { convo in
        let title = convo.title ?? ""
        let summary = convo.overview ?? ""
        guard !title.isEmpty else { return nil }
        return "\(title): \(summary)"
      }
    } catch {
      log("AIUserProfileService: Failed to fetch conversations: \(error.localizedDescription)")
      return []
    }
  }

  private func fetchJournalMessages(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> [String] {
    let session = AgentClient.makeSession()
    do {
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
        throw LocalMutationAuthorizationError.revoked
      }
      try await session.start()
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
        throw LocalMutationAuthorizationError.revoked
      }
      let surface = AgentSurfaceReference.mainChat(chatId: nil)
      let resolved = try await session.resolveSurfaceSession(surface)
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
        throw LocalMutationAuthorizationError.revoked
      }
      let snapshot = try await session.getContextSnapshot(
        sessionId: resolved.sessionId,
        surfaceKind: surface.surfaceKind)
      await session.stopAndWaitForExit()
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return [] }
      return snapshot.recentTurns
        .compactMap(AgentContextRecentTurn.init(dictionary:))
        .suffix(AIUserProfileInputPolicy.journalMessageLimit)
        .map { "[\($0.role)] \($0.content)" }
    } catch {
      await session.stopAndWaitForExit()
      log("AIUserProfileService: Failed to fetch local journal messages: \(error.localizedDescription)")
      return []
    }
  }

  // MARK: - Prompt Building

  private func buildPrompt(
    memories: [String],
    tasks: [String],
    goals: [String],
    conversations: [String],
    journalMessages: [String]
  ) -> String {
    var sections: [String] = []

    if !memories.isEmpty {
      sections.append("## Memories about the user\n\(memories.joined(separator: "\n"))")
    }

    if !tasks.isEmpty {
      sections.append("## Recent tasks\n\(tasks.joined(separator: "\n"))")
    }

    if !goals.isEmpty {
      sections.append("## Active goals\n\(goals.joined(separator: "\n"))")
    }

    if !conversations.isEmpty {
      sections.append("## Recent conversations (past 7 days)\n\(conversations.joined(separator: "\n"))")
    }

    if !journalMessages.isEmpty {
      sections.append("## Recent local chat messages\n\(journalMessages.joined(separator: "\n"))")
    }

    return """
      Generate a factual user profile from the following data. \
      Output a flat list of concrete facts (one per line, prefixed with "- "). \
      This profile will be used as context for AI pipelines that analyze the user's screen and audio activity \
      to extract tasks, goals, and memories. Focus on facts that help identify who is who, what projects are active, \
      and what the user's current priorities are. Under 2000 characters.

      \(sections.joined(separator: "\n\n"))
      """
  }

  private func buildConsolidationPrompt(
    newProfile: String,
    pastProfiles: [AIUserProfileRecord]
  ) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .none

    var pastSection = ""
    for profile in pastProfiles.reversed() {
      let dateStr = dateFormatter.string(from: profile.generatedAt)
      pastSection += "--- Profile from \(dateStr) ---\n\(profile.profileText)\n\n"
    }

    return """
      Merge the following into one holistic user profile. Under 2000 characters.

      === NEW PROFILE (generated today from latest data) ===
      \(newProfile)

      === PAST PROFILES (oldest to newest, up to 5) ===
      \(pastSection)
      """
  }

  // MARK: - Errors

  enum ProfileError: LocalizedError {
    case alreadyGenerating
    case insufficientData
    case databaseNotAvailable

    var errorDescription: String? {
      switch self {
      case .alreadyGenerating:
        return "Profile generation is already in progress"
      case .insufficientData:
        return "Not enough data to generate a profile"
      case .databaseNotAvailable:
        return "Database is not available"
      }
    }
  }

  private func currentOwnerAuthorization() -> LocalMutationAuthorization? {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return nil }
    return LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
  }
}
