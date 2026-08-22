import Foundation

struct YourStatsTaskCounts: Equatable, Sendable {
  let todo: Int
  let done: Int
  let deleted: Int
}

struct YourStatsSnapshot: Equatable, Sendable {
  let conversations: Int
  let chatMessages: Int
  let screenshots: Int
  let focusSessions: Int
  let tasksTodo: Int
  let tasksDone: Int
  let tasksDeleted: Int
  let goals: Int
  let memories: Int
}

@MainActor
struct YourStatsLocalReaders {
  typealias CountReader = @MainActor (RuntimeOwnerAuthorizationSnapshot) async throws -> Int
  typealias TaskCountReader =
    @MainActor (RuntimeOwnerAuthorizationSnapshot) async throws -> YourStatsTaskCounts

  var conversations: CountReader
  var chatMessages: CountReader
  var screenshots: CountReader
  var focusSessions: CountReader
  var taskCounts: TaskCountReader
  var goals: CountReader
  var memories: CountReader

  static let live = YourStatsLocalReaders(
    conversations: { snapshot in
      try await TranscriptionStorage.shared.conversationCount(
        query: .all,
        authorizationSnapshot: snapshot
      )
    },
    chatMessages: { snapshot in
      guard let provider = ChatProvider.mainInstance else {
        throw BridgeError.agentError("Main Chat is unavailable")
      }
      return try await provider.localChatMessageCount(authorizationSnapshot: snapshot)
    },
    screenshots: { snapshot in
      try await RewindDatabase.shared.getScreenshotCount(authorizationSnapshot: snapshot)
    },
    focusSessions: { snapshot in
      try await ProactiveStorage.shared.getTotalFocusSessionCount(authorizationSnapshot: snapshot)
    },
    taskCounts: { snapshot in
      let counts = try await ActionItemStorage.shared.getFilterCounts(
        authorizationSnapshot: snapshot)
      return YourStatsTaskCounts(todo: counts.todo, done: counts.done, deleted: counts.deleted)
    },
    goals: { snapshot in
      try await GoalStorage.shared.getLocalGoals(
        activeOnly: false,
        authorizationSnapshot: snapshot
      ).count
    },
    memories: { snapshot in
      try await MemoryStorage.shared.getStats(authorizationSnapshot: snapshot).total
    }
  )
}

@MainActor
enum YourStatsLocalLoader {
  static func load() async throws -> YourStatsSnapshot? {
    try await load(readers: .live)
  }

  static func load(readers: YourStatsLocalReaders) async throws -> YourStatsSnapshot? {
    guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return nil }

    async let conversationsRead = readers.conversations(authorization)
    async let chatMessagesRead: Int? = try? await readers.chatMessages(authorization)
    async let screenshotsRead: Int? = try? await readers.screenshots(authorization)
    async let focusSessionsRead = readers.focusSessions(authorization)
    async let taskCountsRead = readers.taskCounts(authorization)
    async let goalsRead = readers.goals(authorization)
    async let memoriesRead = readers.memories(authorization)

    let conversations = try await conversationsRead
    guard isCurrent(authorization) else { return nil }

    let chatMessages = await chatMessagesRead ?? 0
    guard isCurrent(authorization) else { return nil }

    let screenshots = await screenshotsRead ?? 0
    guard isCurrent(authorization) else { return nil }

    let focusSessions = try await focusSessionsRead
    guard isCurrent(authorization) else { return nil }

    let tasks = try await taskCountsRead
    guard isCurrent(authorization) else { return nil }

    let goals = try await goalsRead
    guard isCurrent(authorization) else { return nil }

    let memories = try await memoriesRead
    guard isCurrent(authorization) else { return nil }

    return YourStatsSnapshot(
      conversations: conversations,
      chatMessages: chatMessages,
      screenshots: screenshots,
      focusSessions: focusSessions,
      tasksTodo: tasks.todo,
      tasksDone: tasks.done,
      tasksDeleted: tasks.deleted,
      goals: goals,
      memories: memories
    )
  }

  private static func isCurrent(_ authorization: RuntimeOwnerAuthorizationSnapshot) -> Bool {
    !Task.isCancelled && RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
  }
}
