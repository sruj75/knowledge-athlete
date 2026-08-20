import Foundation

enum ConversationLifecycleState: String, Codable, CaseIterable, Sendable {
  case recording
  case finalizing
  case processing
  case completed
  case merging
  case failed
}

struct ConversationLocationSnapshot: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let label: String?
}

struct ConversationCaptureConfiguration: Equatable, Sendable {
  var language: String
  var autoDetectLanguage: Bool
  var vocabulary: [String]
  var timezone: String
  var inputDeviceName: String?
  var location: ConversationLocationSnapshot?

  static let testDefault = ConversationCaptureConfiguration(
    language: "en",
    autoDetectLanguage: false,
    vocabulary: [],
    timezone: "UTC",
    inputDeviceName: nil,
    location: nil)
}

struct ConversationCaptureHandle: Equatable, Sendable {
  let sessionId: Int64
  let conversationId: String
}

struct ConversationSegmentTranslation: Codable, Equatable, Sendable {
  let language: String
  let text: String
}

struct ConversationSegmentInput: Equatable, Sendable {
  var segmentId: String?
  var speakerId: Int
  var text: String
  var startTime: Double
  var endTime: Double
  var isUser: Bool
  var translations: [ConversationSegmentTranslation]
}

struct LocalTranscriptSegment: Codable, Equatable, Sendable {
  var segmentId: String
  var speakerId: Int
  var text: String
  var startTime: Double
  var endTime: Double
  var segmentOrder: Int
  var isUser: Bool
  var translations: [ConversationSegmentTranslation]
}

struct LocalConversationDetail: Codable, Equatable, Sendable, Identifiable {
  var id: String { conversationId }

  let conversationId: String
  let startedAt: Date
  let finishedAt: Date?
  let language: String
  let autoDetectLanguage: Bool
  let vocabulary: [String]
  let timezone: String
  let inputDeviceName: String?
  let location: ConversationLocationSnapshot?
  let status: ConversationLifecycleState
  let lastError: String?
  let finalizationReason: TranscriptionFinalizationReason?
  let finalizationStartedAt: Date?
  let finalizationCompletedAt: Date?
  let title: String?
  let isTitleManuallyEdited: Bool
  let overview: String?
  let emoji: String?
  let commitmentsJson: String?
  let starred: Bool
  let folderId: String?
  let createdAt: Date
  let updatedAt: Date
  let contentGeneration: Int
  let segments: [LocalTranscriptSegment]
  let speakerLabels: [Int: ConversationSpeakerLabel]
}

struct ConversationSpeakerLabel: Codable, Equatable, Sendable {
  let speakerId: Int
  let name: String
  let isUser: Bool
}

struct LocalConversationSummary: Codable, Equatable, Sendable, Identifiable {
  var id: String { conversationId }

  let conversationId: String
  let startedAt: Date
  let finishedAt: Date?
  let status: ConversationLifecycleState
  let title: String?
  let overview: String?
  let emoji: String?
  let starred: Bool
  let folderId: String?
  let segmentCount: Int
  let createdAt: Date
  let updatedAt: Date
  let contentGeneration: Int
}

struct ConversationLocalQuery: Equatable, Sendable {
  let starredOnly: Bool
  let startDate: Date?
  let endDate: Date?
  let folderId: String?
  let statuses: [ConversationLifecycleState]?

  init(
    starredOnly: Bool,
    startDate: Date?,
    endDate: Date?,
    folderId: String?,
    statuses: [ConversationLifecycleState]? = nil
  ) {
    self.starredOnly = starredOnly
    self.startDate = startDate
    self.endDate = endDate
    self.folderId = folderId
    self.statuses = statuses
  }

  static let all = ConversationLocalQuery(
    starredOnly: false, startDate: nil, endDate: nil, folderId: nil, statuses: nil)
}

struct ConversationFolderRecord: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let name: String
  let color: String
  let createdAt: Date
  var conversationCount: Int = 0
}

enum ConversationEnrichmentKind: String, Codable, CaseIterable, Sendable {
  case discard
  case structure
  case actionItems
}

enum ConversationEnrichmentState: String, Codable, CaseIterable, Sendable {
  case pending
  case running
  case succeeded
  case failed
  case superseded
}

struct ConversationEnrichmentWork: Codable, Equatable, Sendable {
  let conversationId: String
  let contentGeneration: Int
  let kind: ConversationEnrichmentKind
  let state: ConversationEnrichmentState
  let attemptCount: Int
  let lastError: String?
  let createdAt: Date
  let updatedAt: Date
}

struct ConversationRecoveryReport: Equatable, Sendable {
  let finalizedConversationIds: [String]
  let deletedEmptyConversationIds: [String]
}

struct ConversationDiscardWorkClaim: Sendable {
  let conversation: LocalConversationDetail
  let contentGeneration: Int
  let attemptCount: Int
}

enum ConversationDiscardCommitResult: Equatable, Sendable {
  case deleted
  case kept
  case stale
  case missing
}

enum ConversationDiscardAdmissionResult: Equatable, Sendable {
  case deleted
  case kept
  case failedKeep
  case stale
  case noPendingWork
}

enum ConversationStructureCommitResult: Equatable, Sendable {
  case applied
  case stale
  case missing
}

struct ConversationTaskSimilarityMatch: Equatable, Sendable {
  let localRowId: Int64
  let similarity: Float
}

struct ConversationRelatedLocalTask: Equatable, Sendable {
  let localRowId: Int64
  let description: String
  let dueAt: Date?
}

struct ConversationActionTaskToken: Equatable, Sendable {
  let token: String
  let localRowId: Int64
}

struct LocalConversationActionItem: Equatable, Sendable {
  let localRowId: Int64
  let description: String
  let completed: Bool
  let deleted: Bool
  let dueAt: Date?
}

enum ConversationEnrichmentProcessResult: Equatable, Sendable {
  case applied
  case failed
  case stale
  case noPendingWork
}
