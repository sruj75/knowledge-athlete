import Foundation

enum LocalUserDataExportError: LocalizedError, Equatable {
  case notAuthenticated
  case ownerChanged
  case invalidPage(String)
  case readFailed(String)
  case writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Sign in before exporting your data."
    case .ownerChanged:
      return "Your account changed while the export was being prepared. Nothing was written."
    case .invalidPage(let collection):
      return "The local \(collection) export could not be completed. Nothing was written."
    case .readFailed:
      return "Your local data could not be read. Nothing was written."
    case .writeFailed:
      return "The export file could not be saved. No partial file was left behind."
    }
  }
}

enum LocalUserDataSettingValue: Codable, Equatable, Sendable {
  case bool(Bool)
  case integer(Int)
  case double(Double)
  case string(String)
  case strings([String])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else {
      self = .strings(try container.decode([String].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .strings(let value): try container.encode(value)
    }
  }
}

struct LocalUserDataMemory: Codable, Equatable, Sendable {
  let id: String
  let content: String
  let category: String
  let layer: String
  let expiresAt: Date?
  let revision: Int
  let createdAt: Date
  let updatedAt: Date
  let correctedAt: Date?
  let conversationId: String?
  let sourceSegmentId: String?
  let manuallyAdded: Bool
  let source: String?
  let confidence: Double?
  let sourceApp: String?
  let contextSummary: String?
  let isRead: Bool
  let isDismissed: Bool
  let tags: [String]
  let reasoning: String?
  let currentActivity: String?
  let inputDeviceName: String?
  let windowTitle: String?
  let screenshotId: Int64?
  let evidenceTokens: [String]
  let sensitivityLabels: [String]
  let subject: String?
  let predicate: String?
  let arguments: [String: String]

  init(_ item: MemoryItem) {
    id = item.id
    content = item.content
    category = item.category.rawValue
    layer = item.layer.rawValue
    expiresAt = item.expiresAt
    revision = item.revision
    createdAt = item.createdAt
    updatedAt = item.updatedAt
    correctedAt = item.correctedAt
    conversationId = item.conversationId
    sourceSegmentId = item.sourceSegmentId
    manuallyAdded = item.manuallyAdded
    source = item.source?.rawValue
    confidence = item.confidence
    sourceApp = item.sourceApp
    contextSummary = item.contextSummary
    isRead = item.isRead
    isDismissed = item.isDismissed
    tags = item.tags
    reasoning = item.reasoning
    currentActivity = item.currentActivity
    inputDeviceName = item.inputDeviceName
    windowTitle = item.windowTitle
    screenshotId = item.screenshotId
    evidenceTokens = item.evidenceTokens
    sensitivityLabels = item.sensitivityLabels
    subject = item.subject
    predicate = item.predicate
    arguments = item.arguments
  }
}

struct LocalUserDataGoal: Codable, Equatable, Sendable {
  let id: String
  let title: String
  let description: String?
  let isActive: Bool
  let completedAt: Date?
  let createdAt: Date
  let updatedAt: Date

  init(_ goal: LocalGoal) {
    id = goal.id
    title = goal.title
    description = goal.description
    isActive = goal.isActive
    completedAt = goal.completedAt
    createdAt = goal.createdAt
    updatedAt = goal.updatedAt
  }
}

struct LocalUserDataFocusSession: Codable, Equatable, Sendable {
  let id: Int64?
  let screenshotId: Int64?
  let status: String
  let appOrSite: String
  let windowTitle: String?
  let description: String
  let message: String?
  let durationSeconds: Int?
  let createdAt: Date

  init(_ session: FocusSessionRecord) {
    id = session.id
    screenshotId = session.screenshotId
    status = session.status
    appOrSite = session.appOrSite
    windowTitle = session.windowTitle
    description = session.description
    message = session.message
    durationSeconds = session.durationSeconds
    createdAt = session.createdAt
  }
}

struct LocalUserDataChatSummary: Codable, Equatable, Sendable {
  let chatId: String
  let title: String
  let titleOrigin: String
  let preview: String?
  let messageCount: Int
  let createdAt: Date
  let lastActivityAt: Date
  let starred: Bool

  init(_ chat: LocalChatSummary) {
    chatId = chat.chatID
    title = chat.title
    titleOrigin = chat.titleOrigin.rawValue
    preview = chat.preview
    messageCount = chat.messageCount
    createdAt = chat.createdAt
    lastActivityAt = chat.lastActivityAt
    starred = chat.starred
  }
}

struct LocalUserDataChatTurn: Codable, Equatable, Sendable {
  let conversationId: String
  let turnId: String
  let turnSequence: Int
  let role: String
  let content: String
  let origin: String
  let status: String
  let contentBlocksJson: String
  let resourcesJson: String
  let metadataJson: String
  let createdAtMilliseconds: Int
  let updatedAtMilliseconds: Int
  let completedAtMilliseconds: Int?

  init(_ turn: KernelJournalTurn) {
    conversationId = turn.conversationId
    turnId = turn.turnId
    turnSequence = turn.turnSeq
    role = turn.role
    content = turn.content
    origin = turn.origin
    status = turn.status.rawValue
    contentBlocksJson = turn.contentBlocksJSON
    resourcesJson = turn.resourcesJSON
    metadataJson = turn.metadataJSON
    createdAtMilliseconds = turn.createdAtMs
    updatedAtMilliseconds = turn.updatedAtMs
    completedAtMilliseconds = turn.completedAtMs
  }
}

struct LocalUserDataChat: Codable, Equatable, Sendable {
  let summary: LocalUserDataChatSummary
  let turns: [LocalUserDataChatTurn]
}

struct LocalUserDataExportDocument: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let exportedAt: Date
  let conversations: [ConversationArchiveRecord]
  let memories: [LocalUserDataMemory]
  let tasks: [TaskActionItem]
  let goals: [LocalUserDataGoal]
  let chatHistory: [LocalUserDataChat]
  let focusData: [LocalUserDataFocusSession]
  let settings: [String: LocalUserDataSettingValue]
}

protocol LocalUserDataExportReading: Sendable {
  func conversationPage(
    after conversationID: String?, limit: Int,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationArchiveRecord]
  func memoryPage(
    offset: Int, limit: Int, authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataMemory]
  func taskPage(
    offset: Int, limit: Int, authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [TaskActionItem]
  func goalPage(
    offset: Int, limit: Int, authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataGoal]
  func focusData(
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataFocusSession]
  func chatCatalog(
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataChatSummary]
  func chatTurnPage(
    chatID: String, after sequence: Int, limit: Int,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataChatTurn]
  func settings() -> [String: LocalUserDataSettingValue]
}

protocol LocalUserDataExportFileWriting: Sendable {
  func writeAtomically(_ data: Data, to destination: URL) throws
}

struct LocalUserDataAtomicFileWriter: LocalUserDataExportFileWriting {
  func writeAtomically(_ data: Data, to destination: URL) throws {
    let fileManager = FileManager.default
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".intentive-export-\(UUID().uuidString).tmp")
    do {
      try data.write(to: temporary, options: .atomic)
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error
    }
  }
}

struct LocalUserDataExport: Sendable {
  static let pageSize = 100

  private let reader: any LocalUserDataExportReading
  private let writer: any LocalUserDataExportFileWriting
  private let now: @Sendable () -> Date
  private let captureAuthorization: @Sendable (String) -> RuntimeOwnerAuthorizationSnapshot?
  private let isAuthorizationCurrent: @Sendable (RuntimeOwnerAuthorizationSnapshot) -> Bool

  init(
    reader: any LocalUserDataExportReading = LocalUserDataExportLiveReader.shared,
    writer: any LocalUserDataExportFileWriting = LocalUserDataAtomicFileWriter(),
    now: @escaping @Sendable () -> Date = Date.init,
    captureAuthorization: @escaping @Sendable (String) -> RuntimeOwnerAuthorizationSnapshot? = {
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: $0)
    },
    isAuthorizationCurrent: @escaping @Sendable (RuntimeOwnerAuthorizationSnapshot) -> Bool = {
      RuntimeOwnerIdentity.isAuthorizationCurrent($0)
    }
  ) {
    self.reader = reader
    self.writer = writer
    self.now = now
    self.captureAuthorization = captureAuthorization
    self.isAuthorizationCurrent = isAuthorizationCurrent
  }

  func export(ownerID: String, to destination: URL) async throws {
    guard let authorization = captureAuthorization(ownerID) else {
      throw LocalUserDataExportError.notAuthenticated
    }
    do {
      let document = try await buildDocument(authorization: authorization)
      try requireCurrent(authorization)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.keyEncodingStrategy = .convertToSnakeCase
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(document)
      try requireCurrent(authorization)
      let commitAuthorization = LocalMutationAuthorization {
        isAuthorizationCurrent(authorization)
      }
      do {
        try await commitAuthorization.withCommitLease {
          try requireCurrent(authorization)
          try writer.writeAtomically(data, to: destination)
        }
      } catch LocalMutationAuthorizationError.revoked {
        throw LocalUserDataExportError.ownerChanged
      } catch let error as LocalUserDataExportError {
        throw error
      } catch {
        throw LocalUserDataExportError.writeFailed(String(describing: error))
      }
    } catch let error as LocalUserDataExportError {
      throw error
    } catch {
      throw LocalUserDataExportError.readFailed(String(describing: error))
    }
  }

  private func buildDocument(
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> LocalUserDataExportDocument {
    let conversations = try await collectConversations(authorization)
    let memories = try await collectOffsetPages(authorization, name: "memories") {
      try await reader.memoryPage(offset: $0, limit: $1, authorization: authorization)
    }
    let tasks = try await collectOffsetPages(authorization, name: "tasks") {
      try await reader.taskPage(offset: $0, limit: $1, authorization: authorization)
    }
    let goals = try await collectOffsetPages(authorization, name: "goals") {
      try await reader.goalPage(offset: $0, limit: $1, authorization: authorization)
    }
    try requireCurrent(authorization)
    let focusData = try await reader.focusData(authorization: authorization)
      .sorted { lhs, rhs in
        lhs.createdAt == rhs.createdAt ? (lhs.id ?? 0) < (rhs.id ?? 0) : lhs.createdAt < rhs.createdAt
      }
    try requireCurrent(authorization)
    let summaries = try await reader.chatCatalog(authorization: authorization)
      .sorted { $0.chatId < $1.chatId }
    var chats: [LocalUserDataChat] = []
    for summary in summaries {
      chats.append(
        LocalUserDataChat(
          summary: summary,
          turns: try await collectChatTurns(summary.chatId, authorization)))
    }
    try requireCurrent(authorization)
    return LocalUserDataExportDocument(
      schemaVersion: 1,
      exportedAt: now(),
      conversations: conversations.sorted {
        $0.startedAt == $1.startedAt
          ? $0.conversationId < $1.conversationId : $0.startedAt < $1.startedAt
      },
      memories: memories.sorted {
        $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
      },
      tasks: tasks,
      goals: goals,
      chatHistory: chats,
      focusData: focusData,
      settings: reader.settings())
  }

  private func collectConversations(
    _ authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationArchiveRecord] {
    var result: [ConversationArchiveRecord] = []
    var cursor: String?
    while true {
      try requireCurrent(authorization)
      let page = try await reader.conversationPage(
        after: cursor, limit: Self.pageSize, authorization: authorization)
      try requireCurrent(authorization)
      result.append(contentsOf: page)
      guard page.count == Self.pageSize else { return result }
      let next = page.last?.conversationId
      guard next != nil, next != cursor else {
        throw LocalUserDataExportError.invalidPage("conversations")
      }
      cursor = next
    }
  }

  private func collectOffsetPages<Element: Sendable>(
    _ authorization: RuntimeOwnerAuthorizationSnapshot,
    name: String,
    page: (Int, Int) async throws -> [Element]
  ) async throws -> [Element] {
    var result: [Element] = []
    var offset = 0
    while true {
      try requireCurrent(authorization)
      let next = try await page(offset, Self.pageSize)
      try requireCurrent(authorization)
      result.append(contentsOf: next)
      guard next.count == Self.pageSize else { return result }
      guard !next.isEmpty else { throw LocalUserDataExportError.invalidPage(name) }
      offset += next.count
    }
  }

  private func collectChatTurns(
    _ chatID: String,
    _ authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataChatTurn] {
    var result: [LocalUserDataChatTurn] = []
    var after = 0
    while true {
      try requireCurrent(authorization)
      let page = try await reader.chatTurnPage(
        chatID: chatID, after: after, limit: Self.pageSize, authorization: authorization
      )
      .sorted {
        $0.turnSequence == $1.turnSequence
          ? $0.turnId < $1.turnId : $0.turnSequence < $1.turnSequence
      }
      try requireCurrent(authorization)
      result.append(contentsOf: page)
      guard page.count == Self.pageSize else { return result }
      guard let next = page.last?.turnSequence, next > after else {
        throw LocalUserDataExportError.invalidPage("chat history")
      }
      after = next
    }
  }

  private func requireCurrent(
    _ authorization: RuntimeOwnerAuthorizationSnapshot
  ) throws {
    guard isAuthorizationCurrent(authorization) else {
      throw LocalUserDataExportError.ownerChanged
    }
  }
}

actor LocalUserDataExportLiveReader: LocalUserDataExportReading {
  static let shared = LocalUserDataExportLiveReader()

  private let bridge = AgentClient.makeBridge()

  func conversationPage(
    after conversationID: String?, limit: Int,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [ConversationArchiveRecord] {
    try await TranscriptionStorage.shared.conversationArchivePage(
      after: conversationID, limit: limit, authorizationSnapshot: authorization)
  }

  func memoryPage(
    offset: Int, limit: Int, authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataMemory] {
    try await MemoryStorage.shared.list(
      scope: .allIncludingArchive,
      includeDismissed: true,
      limit: limit,
      offset: offset,
      authorizationSnapshot: authorization
    ).map(LocalUserDataMemory.init)
  }

  func taskPage(
    offset: Int, limit: Int, authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [TaskActionItem] {
    try await ActionItemStorage.shared.getLocalExportPage(
      limit: limit, offset: offset, authorizationSnapshot: authorization)
  }

  func goalPage(
    offset: Int, limit: Int, authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataGoal] {
    try await GoalStorage.shared.getLocalExportPage(
      limit: limit, offset: offset, authorizationSnapshot: authorization
    ).map(LocalUserDataGoal.init)
  }

  func focusData(
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataFocusSession] {
    try await ProactiveStorage.shared.getFocusSessions(
      from: .distantPast,
      to: .distantFuture,
      limit: 500,
      authorizationSnapshot: authorization
    ).map(LocalUserDataFocusSession.init)
  }

  func chatCatalog(
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataChatSummary] {
    try await bridge.listChatCatalog(authorizationSnapshot: authorization)
      .chats.map(LocalUserDataChatSummary.init)
  }

  func chatTurnPage(
    chatID: String, after sequence: Int, limit: Int,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [LocalUserDataChatTurn] {
    try await bridge.listJournalTurns(
      surface: .mainChat(chatId: chatID),
      ownerID: authorization.ownerID,
      afterTurnSeq: sequence,
      limit: limit,
      authorizationSnapshot: authorization
    ).turns.map(LocalUserDataChatTurn.init)
  }

  nonisolated func settings() -> [String: LocalUserDataSettingValue] {
    LocalUserDataExportSettings.snapshot()
  }
}

enum LocalUserDataExportSettings {
  // Privacy-reviewed allowlist: product preferences only. Auth credentials,
  // provider secrets, diagnostics, prompts, caches, and rollout state are not exported.
  private static let keys = [
    "multiChatEnabled",
    "askModeEnabled",
    "chatScreenshotSharingEnabled",
    "notifications_enabled",
    "notification_frequency",
    "transcriptionEnabled",
    "transcriptionLanguage",
    "transcriptionAutoDetect",
    "voiceAssistantLanguages",
    "transcriptionVocabulary",
    "conversationLocationEnabled",
    "vadGateEnabled",
    "batchTranscriptionEnabled",
    "systemAudioCaptureMode",
    "screenAnalysisEnabled",
    "suggestionAssistantEnabled",
    "focusAssistantEnabled",
    "focusNotificationsEnabled",
    "taskAssistantEnabled",
    "taskNotificationsEnabled",
    "adviceAssistantEnabled",
    "adviceNotificationsEnabled",
    "memoryAssistantEnabled",
    "memoryNotificationsEnabled",
  ]

  static func snapshot(defaults: UserDefaults = .standard) -> [String: LocalUserDataSettingValue] {
    var result: [String: LocalUserDataSettingValue] = [:]
    for key in keys {
      guard let value = defaults.object(forKey: key) else { continue }
      switch value {
      case let value as Bool: result[key] = .bool(value)
      case let value as Int: result[key] = .integer(value)
      case let value as Double: result[key] = .double(value)
      case let value as String: result[key] = .string(value)
      case let value as [String]: result[key] = .strings(value)
      default: continue
      }
    }
    return result
  }
}
