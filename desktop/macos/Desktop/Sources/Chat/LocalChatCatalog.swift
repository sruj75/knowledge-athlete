import Foundation

enum LocalChatTitleOrigin: String, Equatable, Sendable {
  case defaultTitle = "default"
  case automatic
  case manual
}

enum ChatCatalogOperation: String, Equatable, Sendable {
  case list
  case create
  case update
  case delete

  var wireType: String { "chat_catalog_\(rawValue)" }
}

struct LocalChatCatalogSnapshot: Equatable, Sendable {
  let chats: [LocalChatSummary]
  let retainedAttachmentURIs: Set<String>
}

struct LocalChatSummary: Equatable, Sendable {
  let chatID: String
  let title: String
  let titleOrigin: LocalChatTitleOrigin
  let preview: String?
  let messageCount: Int
  let createdAt: Date
  let lastActivityAt: Date
  let starred: Bool

  init?(dictionary: [String: Any]) {
    guard
      let chatID = dictionary["chatId"] as? String,
      let title = dictionary["title"] as? String,
      let titleOriginRaw = dictionary["titleOrigin"] as? String,
      let titleOrigin = LocalChatTitleOrigin(rawValue: titleOriginRaw),
      let messageCount = Self.integer(dictionary["messageCount"]),
      let createdAtMs = Self.integer(dictionary["createdAtMs"]),
      let lastActivityAtMs = Self.integer(dictionary["lastActivityAtMs"]),
      let starred = dictionary["starred"] as? Bool
    else { return nil }

    self.chatID = chatID
    self.title = title
    self.titleOrigin = titleOrigin
    self.preview = dictionary["preview"] as? String
    self.messageCount = messageCount
    self.createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1_000)
    self.lastActivityAt = Date(timeIntervalSince1970: TimeInterval(lastActivityAtMs) / 1_000)
    self.starred = starred
  }

  var chatSession: ChatSession {
    ChatSession(
      id: chatID,
      title: title,
      preview: preview,
      createdAt: createdAt,
      updatedAt: lastActivityAt,
      messageCount: messageCount,
      starred: starred
    )
  }

  private static func integer(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    return nil
  }
}
