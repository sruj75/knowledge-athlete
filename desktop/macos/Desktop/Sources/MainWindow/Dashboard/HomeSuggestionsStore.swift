import Foundation

// MARK: - Composition

/// Builds the three home ask-bar suggestion chips: a fixed universal first
/// question plus two personalized follow-ups generated from the user's own
/// memories, conversations, tasks, and goals.
enum HomeSuggestionComposer {
  static let universalFirstQuestion = "What should I do today?"

  /// Longest personalized question that still fits a single chip line.
  static let maxPersonalizedLength = 72

  /// Universal first-slot questions (current and legacy onboarding wording)
  /// that must not repeat in the personalized slots.
  private static let universalQuestions: Set<String> = [
    "what should i do today?",
    "what should i focus on today to achieve my goals?",
  ]

  static let staticFallbacks = [
    "What did I spend my time on this week?",
    "What's the highest-leverage thing I can do next?",
  ]

  /// Trim, drop empties/duplicates/universal repeats, and drop questions too
  /// long to render on one chip line.
  static func sanitize(_ questions: [String]) -> [String] {
    var seen = Set<String>()
    return
      questions
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { question in
        guard !question.isEmpty, question.count <= maxPersonalizedLength else { return false }
        let key = question.lowercased()
        guard !universalQuestions.contains(key), !seen.contains(key) else { return false }
        seen.insert(key)
        return true
      }
  }

  /// The three chips: universal first, then personalized questions, topped up
  /// from static fallbacks when fewer than two personalized questions are
  /// available.
  static func compose(personalized: [String]) -> [String] {
    let rest = sanitize(personalized + staticFallbacks)
    return [universalFirstQuestion] + rest.prefix(2)
  }
}

enum HomeSuggestionSelection: Equatable {
  case ignore
  case prefill(String)

  static func resolve(_ suggestion: String) -> Self {
    let text = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? .ignore : .prefill(text)
  }
}

// MARK: - Generation seam

protocol HomeSuggestionGenerating: Sendable {
  /// Returns personalized questions, or an empty array when the user's
  /// context is too thin to reference anything real. Throws on transport
  /// failure so the caller can retry later without burning the daily slot.
  /// Every context read must be bound to `snapshot` so a mid-generation
  /// account switch can never return another owner's data.
  func generatePersonalizedQuestions(
    snapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [String]
}

// MARK: - Store

/// Owns the two personalized home suggestion chips: generates them at most
/// once per day per account and caches them per owner so an account switch
/// never shows another account's questions.
@MainActor
final class HomeSuggestionsStore: ObservableObject {
  static let shared = HomeSuggestionsStore()

  @Published private(set) var personalizedQuestions: [String] = []

  private struct CacheEntry: Codable {
    let questions: [String]
    let dayStamp: String
  }

  private static let dayStampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private let defaults: UserDefaults
  private let generator: any HomeSuggestionGenerating
  private let now: () -> Date
  private var generatingOwnerID: String?
  private var generatingOwnerGeneration: UInt64?
  private var ownerGeneration: UInt64 = 0
  private nonisolated(unsafe) var ownerObserver: NSObjectProtocol?

  init(
    defaults: UserDefaults = .standard,
    generator: (any HomeSuggestionGenerating)? = nil,
    now: @escaping () -> Date = Date.init
  ) {
    self.defaults = defaults
    self.generator = generator ?? GeminiHomeSuggestionGenerator()
    self.now = now
    publishCache(for: RuntimeOwnerIdentity.currentOwnerId() ?? "signed-out")
    ownerObserver = NotificationCenter.default.addObserver(
      forName: .runtimeOwnerDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.ownerGeneration &+= 1
        self.generatingOwnerID = nil
        self.generatingOwnerGeneration = nil
        self.publishCache(for: RuntimeOwnerIdentity.currentOwnerId() ?? "signed-out")
        Task { @MainActor [weak self] in
          await self?.refreshIfNeeded()
        }
      }
    }
  }

  deinit {
    if let ownerObserver { NotificationCenter.default.removeObserver(ownerObserver) }
  }

  /// Publish the current owner's cached questions and generate fresh ones at
  /// most once per day per owner. The owner-authorization snapshot captured
  /// up front bounds every context fetch, the cache write, and the publish,
  /// so a mid-generation account switch drops the result entirely. Transport
  /// failures leave the cache untouched so a later call retries; a
  /// successful-but-empty generation is cached to hold one attempt per day.
  func refreshIfNeeded() async {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      // Signed out or mid account transition — never render a previous
      // owner's questions.
      personalizedQuestions = []
      return
    }
    let ownerID = snapshot.ownerID
    let generation = ownerGeneration
    publishCache(for: ownerID)

    let today = Self.dayStampFormatter.string(from: now())
    if let cache = loadCache(for: ownerID), cache.dayStamp == today { return }
    guard generatingOwnerID == nil else { return }

    generatingOwnerID = ownerID
    generatingOwnerGeneration = generation
    defer {
      if generatingOwnerID == ownerID, generatingOwnerGeneration == generation {
        generatingOwnerID = nil
        generatingOwnerGeneration = nil
      }
    }

    do {
      let generated = try await generator.generatePersonalizedQuestions(snapshot: snapshot)
      guard generation == ownerGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else {
        log("HomeSuggestions: dropped generation result after account switch")
        return
      }
      let questions = Array(HomeSuggestionComposer.sanitize(generated).prefix(2))
      let entry = CacheEntry(questions: questions, dayStamp: today)
      defaults.set(try? JSONEncoder().encode(entry), forKey: Self.cacheKey(ownerID: ownerID))
      personalizedQuestions = questions
      log("HomeSuggestions: generated \(questions.count) personalized questions for \(today)")
    } catch {
      log(
        "HomeSuggestions: generation failed (will retry on next visit): \(error.localizedDescription)"
      )
    }
  }

  static func cacheKey(ownerID: String) -> String {
    "homePersonalizedSuggestions.v1.\(ownerID)"
  }

  private func loadCache(for ownerID: String) -> CacheEntry? {
    guard let data = defaults.data(forKey: Self.cacheKey(ownerID: ownerID)) else { return nil }
    return try? JSONDecoder().decode(CacheEntry.self, from: data)
  }

  private func publishCache(for ownerID: String) {
    personalizedQuestions = loadCache(for: ownerID)?.questions ?? []
  }
}

// MARK: - Gemini generation

enum HomeSuggestionGenerationError: Error {
  /// Context fetches failed and nothing usable arrived — a transport or auth
  /// outage, not a thin-context account. Must not burn the daily slot.
  case contextUnavailable
}

protocol HomeSuggestionLocalSources: Sendable {
  func memoryContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String?
  func conversationContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String?
  func taskContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String?
  func goalContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String?
}

struct DefaultHomeSuggestionLocalSources: HomeSuggestionLocalSources {
  func memoryContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    guard let items = try? await MemoryStorage.shared.list(limit: 50) else { return nil }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    return GeminiHomeSuggestionGenerator.boundedContext(items.map(\.content))
  }

  func conversationContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    guard
      let items = try? await LocalAuthorityConversationDataSource().list(
        query: ConversationListQuery(starredOnly: false, date: nil, folderId: nil),
        offset: 0,
        limit: 30)
    else { return nil }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    return GeminiHomeSuggestionGenerator.boundedContext(
      items.compactMap { $0.structured.overview.isEmpty ? nil : $0.structured.overview }
    )
  }

  func taskContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    guard
      let items = try? await ActionItemStorage.shared.getLocalActionItems(
        limit: 50,
        completed: false
      )
    else { return nil }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    return GeminiHomeSuggestionGenerator.boundedContext(items.map(\.description))
  }

  func goalContext(snapshot: RuntimeOwnerAuthorizationSnapshot) async -> String? {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    guard let goals = try? await GoalStorage.shared.getLocalGoals(activeOnly: true) else { return nil }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) else { return nil }
    return GeminiHomeSuggestionGenerator.boundedContext(goals.prefix(50).map(\.title))
  }
}

struct GeminiHomeSuggestionGenerator: HomeSuggestionGenerating {
  static let systemPrompt =
    "You write the suggested questions shown under the ask bar of Intentive, the user's personal AI assistant. The questions are ones the user would tap to ask about their own life and work."

  private struct Response: Decodable {
    let questions: [String]
  }

  static let maxSourceCharacters = 6_000
  static let maxItemCharacters = 500

  let sources: any HomeSuggestionLocalSources

  init(sources: any HomeSuggestionLocalSources = DefaultHomeSuggestionLocalSources()) {
    self.sources = sources
  }

  /// Fence the actual transport dispatch with the generation-bearing owner
  /// snapshot. A post-read check alone is too late: stale private prompt data
  /// must never be transmitted after sign-out or same-UID reauthentication.
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

  static func boundedContext<S: Sequence>(_ values: S) -> String where S.Element == String {
    var result = ""
    for value in values {
      let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleaned.isEmpty else { continue }
      let item = String(cleaned.prefix(maxItemCharacters))
      let separator = result.isEmpty ? "" : "\n"
      let remaining = maxSourceCharacters - result.count
      guard remaining > separator.count else { break }
      result += String((separator + item).prefix(remaining))
      if result.count == maxSourceCharacters { break }
    }
    return result
  }

  /// Classifies the four context fetches (nil = that fetch failed) so an
  /// outage is distinguishable from an account that genuinely has no data.
  enum ContextClassification: Equatable {
    /// Every source is empty and at least one fetch failed: treat as an
    /// outage and throw so the store retries later instead of caching an
    /// empty day.
    case unavailable
    /// Every fetch succeeded and there is genuinely nothing to reference.
    case thin
    /// Enough real context arrived (partial fetch failures are tolerated).
    case available(memories: String, conversations: String, tasks: String, goals: String)
  }

  static func classifyContext(
    memories: String?,
    conversations: String?,
    tasks: String?,
    goals: String?
  ) -> ContextClassification {
    let sources = [memories, conversations, tasks, goals]
    let anyFailed = sources.contains(nil)
    let combined = sources.compactMap { $0 }.joined()
    if combined.isEmpty {
      return anyFailed ? .unavailable : .thin
    }
    return .available(
      memories: memories ?? "",
      conversations: conversations ?? "",
      tasks: tasks ?? "",
      goals: goals ?? ""
    )
  }

  private var responseSchema: GeminiRequest.GenerationConfig.ResponseSchema {
    GeminiRequest.GenerationConfig.ResponseSchema(
      type: "object",
      properties: [
        "questions": .init(
          type: "array",
          description: "Up to two short personalized questions, empty when context is too thin",
          items: .init(type: "string", properties: nil, required: nil)
        )
      ],
      required: ["questions"]
    )
  }

  func loadContext(
    snapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> ContextClassification {
    async let memoriesFetch = sources.memoryContext(snapshot: snapshot)
    async let conversationsFetch = sources.conversationContext(snapshot: snapshot)
    async let actionItemsFetch = sources.taskContext(snapshot: snapshot)
    async let goalsFetch = sources.goalContext(snapshot: snapshot)

    let (memories, conversations, actionItems, goals) = await (
      memoriesFetch, conversationsFetch, actionItemsFetch, goalsFetch
    )
    return Self.classifyContext(
      memories: memories,
      conversations: conversations,
      tasks: actionItems,
      goals: goals
    )
  }

  func generatePersonalizedQuestions(
    snapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [String] {
    // nil = that fetch failed (vs. succeeded with no data) — the distinction
    // drives outage-vs-thin classification below.
    let classification = await loadContext(snapshot: snapshot)

    let memoryContext: String
    let conversationContext: String
    let tasksContext: String
    let goalsContext: String
    switch classification {
    case .unavailable:
      throw HomeSuggestionGenerationError.contextUnavailable
    case .thin:
      return []
    case .available(let memories, let conversations, let tasks, let goals):
      memoryContext = memories
      conversationContext = conversations
      tasksContext = tasks
      goalsContext = goals
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"

    let prompt = """
      Today is \(dateFormatter.string(from: Date())).

      USER MEMORIES:
      \(memoryContext.isEmpty ? "None" : memoryContext)

      RECENT CONVERSATION SUMMARIES:
      \(conversationContext.isEmpty ? "None" : conversationContext)

      OPEN TASKS:
      \(tasksContext.isEmpty ? "None" : tasksContext)

      ACTIVE GOALS:
      \(goalsContext.isEmpty ? "None" : goalsContext)

      Write up to 2 suggested questions this user would genuinely want to ask right now.

      Rules:
      - Each question must reference something concrete and current from the context above by name — a project, person, goal, task, or topic.
      - Phrase them in first person, as the user asking their assistant (e.g. "How do I unblock the Atlas launch?").
      - Keep each under 48 characters so it fits on one line.
      - No generic productivity questions ("What should I focus on?", "How can I be more productive?") — the first suggestion slot already covers that.
      - Skip anything sensitive or awkward to show on a home screen.
      - Return an empty list if the context doesn't contain enough real, current material.
      """

    let client = try GeminiClient()
    let schema = responseSchema
    let responseText = try await Self.performAuthorizedTextRequest(
      authorizationSnapshot: snapshot
    ) {
      try await client.sendRequest(
        prompt: prompt,
        systemPrompt: Self.systemPrompt,
        responseSchema: schema
      )
    }

    guard let data = responseText.data(using: .utf8) else { return [] }
    return try JSONDecoder().decode(Response.self, from: data).questions
  }
}
