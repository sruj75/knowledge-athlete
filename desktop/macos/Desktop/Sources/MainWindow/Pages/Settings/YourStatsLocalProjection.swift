import Foundation

struct YourStatsSnapshot: Equatable, Sendable {
  let conversations: Int
  let chatMessages: Int
  let screenshots: Int
  let memories: Int
}

@MainActor
enum YourStatsChatCatalogReader {
  typealias CatalogReader =
    @MainActor (RuntimeOwnerAuthorizationSnapshot) async throws -> LocalChatCatalogSnapshot

  private static let liveSession = AgentClient.makeSession()

  static func messageCount(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    catalogReader: CatalogReader? = nil
  ) async throws -> Int {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw BridgeError.authMissing
    }
    let catalog: LocalChatCatalogSnapshot
    if let catalogReader {
      catalog = try await catalogReader(authorizationSnapshot)
    } else {
      catalog = try await liveSession.listChatCatalog(
        authorizationSnapshot: authorizationSnapshot)
    }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw BridgeError.authMissing
    }
    return catalog.chats.reduce(0) { $0 + $1.messageCount }
  }
}

@MainActor
struct YourStatsLocalReaders {
  typealias CountReader = @MainActor (RuntimeOwnerAuthorizationSnapshot) async throws -> Int

  var conversations: CountReader
  var chatMessages: CountReader
  var screenshots: CountReader
  var memories: CountReader

  static let live = YourStatsLocalReaders(
    conversations: { snapshot in
      try await TranscriptionStorage.shared.conversationCount(
        query: .all,
        authorizationSnapshot: snapshot
      )
    },
    chatMessages: { snapshot in
      try await YourStatsChatCatalogReader.messageCount(authorizationSnapshot: snapshot)
    },
    screenshots: { snapshot in
      try await RewindDatabase.shared.getScreenshotCount(authorizationSnapshot: snapshot)
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
    async let memoriesRead = readers.memories(authorization)

    let conversations = try await conversationsRead
    guard isCurrent(authorization) else { return nil }

    let chatMessages = await chatMessagesRead ?? 0
    guard isCurrent(authorization) else { return nil }

    let screenshots = await screenshotsRead ?? 0
    guard isCurrent(authorization) else { return nil }

    let memories = try await memoriesRead
    guard isCurrent(authorization) else { return nil }

    return YourStatsSnapshot(
      conversations: conversations,
      chatMessages: chatMessages,
      screenshots: screenshots,
      memories: memories
    )
  }

  private static func isCurrent(_ authorization: RuntimeOwnerAuthorizationSnapshot) -> Bool {
    !Task.isCancelled && RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
  }
}
