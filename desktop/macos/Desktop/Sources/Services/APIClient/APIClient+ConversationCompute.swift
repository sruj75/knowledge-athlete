import Foundation

struct ConversationDiscardComputeRequest: Codable, Equatable, Sendable {
  let generationId: UUID
  let transcript: String
  let durationSeconds: Double

  enum CodingKeys: String, CodingKey {
    case generationId = "generation_id"
    case transcript
    case durationSeconds = "duration_seconds"
  }
}

struct ConversationDiscardComputeResponse: Codable, Equatable, Sendable {
  let generationId: UUID
  let discard: Bool

  enum CodingKeys: String, CodingKey {
    case generationId = "generation_id"
    case discard
  }
}

protocol ConversationDiscardComputing: Sendable {
  func computeDiscard(
    _ request: ConversationDiscardComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationDiscardComputeResponse
}

struct ConversationCommitmentComputeCandidate: Codable, Equatable, Sendable {
  let title: String
  let description: String
  let start: Date
  let durationMinutes: Int
  let created: Bool

  enum CodingKeys: String, CodingKey {
    case title, description, start, created
    case durationMinutes = "duration_minutes"
  }
}

struct ConversationStructureComputeRequest: Codable, Equatable, Sendable {
  let generationId: UUID
  let transcript: String
  let startedAt: Date
  let language: String
  let outputLanguage: String
  let timezone: String

  enum CodingKeys: String, CodingKey {
    case generationId = "generation_id"
    case transcript
    case startedAt = "started_at"
    case language
    case outputLanguage = "output_language"
    case timezone
  }
}

struct ConversationStructureComputeResponse: Codable, Equatable, Sendable {
  let generationId: UUID
  let title: String
  let overview: String
  let emoji: String
  let category: String
  let commitments: [ConversationCommitmentComputeCandidate]

  init(
    generationId: UUID,
    title: String,
    overview: String,
    emoji: String,
    category: String,
    commitments: [ConversationCommitmentComputeCandidate]
  ) {
    self.generationId = generationId
    self.title = title
    self.overview = overview
    self.emoji = emoji
    self.category = category
    self.commitments = commitments
  }

  enum CodingKeys: String, CodingKey {
    case generationId = "generation_id"
    case title, overview, emoji, category, commitments
  }
}

protocol ConversationStructureComputing: Sendable {
  func computeStructure(
    _ request: ConversationStructureComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationStructureComputeResponse
}

struct ConversationRelatedTaskComputeCandidate: Codable, Equatable, Sendable {
  let token: String
  let description: String
  let dueAt: Date?
  let completed: Bool

  enum CodingKeys: String, CodingKey {
    case token, description, completed
    case dueAt = "due_at"
  }
}

enum ConversationActionComputeKind: String, Codable, Equatable, Sendable {
  case create
  case update
  case complete
}

struct ConversationActionComputeCandidate: Codable, Equatable, Sendable {
  let action: ConversationActionComputeKind
  let description: String
  let targetTaskToken: String?
  let dueAt: Date?

  enum CodingKeys: String, CodingKey {
    case action, description
    case targetTaskToken = "target_task_token"
    case dueAt = "due_at"
  }
}

struct ConversationActionItemsComputeRequest: Codable, Equatable, Sendable {
  let generationId: UUID
  let transcript: String
  let startedAt: Date
  let language: String
  let outputLanguage: String
  let timezone: String
  let relatedTasks: [ConversationRelatedTaskComputeCandidate]

  enum CodingKeys: String, CodingKey {
    case generationId = "generation_id"
    case transcript
    case startedAt = "started_at"
    case language
    case outputLanguage = "output_language"
    case timezone
    case relatedTasks = "related_tasks"
  }
}

struct ConversationActionItemsComputeResponse: Codable, Equatable, Sendable {
  let generationId: UUID
  let candidates: [ConversationActionComputeCandidate]

  enum CodingKeys: String, CodingKey {
    case generationId = "generation_id"
    case candidates
  }
}

protocol ConversationActionItemsComputing: Sendable {
  func computeActionItems(
    _ request: ConversationActionItemsComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationActionItemsComputeResponse
}

extension APIClient: ConversationDiscardComputing {
  func computeDiscard(
    _ request: ConversationDiscardComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationDiscardComputeResponse {
    try await post(
      "/v1/conversation-compute/discard",
      body: request,
      authorizationSnapshot: authorizationSnapshot)
  }
}

extension APIClient: ConversationStructureComputing {
  func computeStructure(
    _ request: ConversationStructureComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationStructureComputeResponse {
    try await post(
      "/v1/conversation-compute/structure",
      body: request,
      authorizationSnapshot: authorizationSnapshot)
  }
}

extension APIClient: ConversationActionItemsComputing {
  func computeActionItems(
    _ request: ConversationActionItemsComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationActionItemsComputeResponse {
    try await post(
      "/v1/conversation-compute/action-items",
      body: request,
      authorizationSnapshot: authorizationSnapshot)
  }
}
