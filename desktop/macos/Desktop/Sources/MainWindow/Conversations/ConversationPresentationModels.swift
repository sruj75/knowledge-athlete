import Foundation

struct ConversationListEmptyPresentation: Equatable, Sendable {
  let title: String
  let message: String

  static func resolve(hasActiveFilters: Bool) -> Self {
    if hasActiveFilters {
      return Self(
        title: "No conversations found",
        message: "Try a different search term")
    }
    return Self(
      title: "No Conversations",
      message: "Start recording to capture your first conversation")
  }
}

enum ConversationSearchPresentation {
  static let failureMessage = "Couldn't search conversations. Try again."
}

enum ConversationLoadPresentation {
  static let failureMessage = "Unable to load conversations. Try again."
}

enum ConversationStatus: String, Codable, Sendable {
  case inProgress = "in_progress"
  case processing
  case merging
  case completed
  case failed
}

enum ConversationEnrichmentFailureKind: String, Codable, Equatable, Sendable {
  case summary
  case actionItems
}

enum ConversationEnrichmentFailurePresentation {
  static func message(for failures: [ConversationEnrichmentFailureKind]) -> String? {
    let kinds = Set(failures)
    switch (kinds.contains(.summary), kinds.contains(.actionItems)) {
    case (true, true): return "Summary and action items couldn't be generated."
    case (true, false): return "Summary couldn't be generated."
    case (false, true): return "Action items couldn't be generated."
    case (false, false): return nil
    }
  }
}

enum TranscriptPresenceState: Equatable, Sendable {
  case omitted
  case includedEmpty
  case includedNonEmpty
}

struct LocalConversation: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let createdAt: Date
  let updatedAt: Date
  let startedAt: Date
  let finishedAt: Date?
  var structured: Structured
  var transcriptSegments: [TranscriptSegment]
  var transcriptSegmentsIncluded: Bool
  let location: ConversationLocationSnapshot?
  let language: String
  let status: ConversationStatus
  var starred: Bool
  var folderId: String?
  let inputDeviceName: String?
  var enrichmentFailures: [ConversationEnrichmentFailureKind] = []

  var title: String {
    structured.title.isEmpty ? "Untitled Conversation" : structured.title
  }

  var overview: String { structured.overview }

  var durationInSeconds: Int {
    if let finishedAt {
      return max(0, Int(finishedAt.timeIntervalSince(startedAt)))
    }
    return max(0, Int(transcriptSegments.last?.end ?? 0))
  }

  var formattedDuration: String {
    let minutes = durationInSeconds / 60
    let seconds = durationInSeconds % 60
    return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
  }

  var transcript: String {
    transcriptSegments.map { segment in
      let label: String
      if segment.isUser {
        label = "You"
      } else if let name = segment.speaker, !name.hasPrefix("SPEAKER_") {
        label = name
      } else {
        label = "Speaker \(segment.speakerId)"
      }
      return "\(label): \(segment.text)"
    }.joined(separator: "\n\n")
  }

  var transcriptPresenceState: TranscriptPresenceState {
    guard transcriptSegmentsIncluded else { return .omitted }
    return transcriptSegments.isEmpty ? .includedEmpty : .includedNonEmpty
  }

  var shouldFetchDetailForTranscript: Bool {
    transcriptPresenceState == .omitted
  }
}

struct Structured: Codable, Equatable, Sendable {
  var title: String
  let overview: String
  let emoji: String
  let actionItems: [ActionItem]
  let events: [Event]
}

struct ActionItem: Codable, Identifiable, Equatable, Sendable {
  var id: String { localRowId.map(String.init) ?? description }
  let description: String
  let completed: Bool
  let deleted: Bool
  var localRowId: Int64? = nil
}

struct Event: Codable, Identifiable, Equatable, Sendable {
  var id: String { title + startsAt.description }
  let title: String
  let startsAt: Date
  let duration: Int
  let description: String
  let created: Bool
}

struct TranscriptTranslation: Codable, Equatable, Sendable {
  let lang: String
  let text: String
}

struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let text: String
  let speaker: String?
  let speakerId: Int
  let isUser: Bool
  let start: Double
  let end: Double
  let translations: [TranscriptTranslation]

  init(
    id: String,
    text: String,
    speaker: String?,
    speakerId: Int,
    isUser: Bool,
    start: Double,
    end: Double,
    translations: [TranscriptTranslation] = []
  ) {
    self.id = id
    self.text = text
    self.speaker = speaker
    self.speakerId = speakerId
    self.isUser = isUser
    self.start = start
    self.end = end
    self.translations = translations
  }

  var timestampString: String {
    "\(formatTime(start)) - \(formatTime(end))"
  }

  private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds)
    return String(
      format: "%02d:%02d:%02d",
      totalSeconds / 3600,
      (totalSeconds % 3600) / 60,
      totalSeconds % 60)
  }
}

struct Folder: Codable, Identifiable, Equatable, Sendable {
  let id: String
  var name: String
  var color: String
  let createdAt: Date
  let conversationCount: Int

  init(
    id: String,
    name: String,
    color: String,
    createdAt: Date,
    conversationCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.createdAt = createdAt
    self.conversationCount = conversationCount
  }

  init(local value: ConversationFolderRecord, conversationCount: Int = 0) {
    self.init(
      id: value.id,
      name: value.name,
      color: value.color,
      createdAt: value.createdAt,
      conversationCount: max(conversationCount, value.conversationCount))
  }
}
