import Foundation

protocol ConversationArchiveReader: Sendable {
  func conversationArchivePage(after conversationId: String?, limit: Int) async throws -> [ConversationArchiveRecord]
}

struct ConversationArchiveRecord: Codable, Equatable, Sendable {
  let conversationId: String
  let startedAt: Date
  let finishedAt: Date?
  let language: String
  let timezone: String
  let inputDeviceName: String?
  let status: String
  let title: String?
  let overview: String?
  let emoji: String?
  let commitmentsJson: String?
  let geolocationJson: String?
  let starred: Bool
  let folderId: String?
  let createdAt: Date
  let updatedAt: Date
  let contentGeneration: Int
  let segments: [ConversationArchiveSegment]
}

struct ConversationArchiveSegment: Codable, Equatable, Sendable {
  let segmentId: String
  let speakerId: Int
  let text: String
  let startTime: Double
  let endTime: Double
  let segmentOrder: Int
  let isUser: Bool
  let translationsJson: String?
  let createdAt: Date
  let updatedAt: Date
}

extension TranscriptionStorage: ConversationArchiveReader {}
