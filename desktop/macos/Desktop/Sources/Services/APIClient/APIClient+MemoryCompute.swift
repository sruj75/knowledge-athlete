import Foundation

struct MemoryNormalizeComputeRequest: Codable, Equatable, Sendable {
  let requestId: UUID
  let revision: Int
  let assertion: String
  let source: String
  let sourceAttribution: String
  let provenanceTokens: [String]

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case revision, assertion, source
    case sourceAttribution = "source_attribution"
    case provenanceTokens = "provenance_tokens"
  }
}

struct MemoryNormalizeComputeResponse: Codable, Equatable, Sendable {
  let requestId: UUID
  let revision: Int
  let normalizedContent: String
  let subject: String
  let predicate: String
  let arguments: [String: String]
  let sensitivityLabels: [String]
  let rationale: String

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case revision
    case normalizedContent = "normalized_content"
    case subject, predicate, arguments
    case sensitivityLabels = "sensitivity_labels"
    case rationale
  }
}

struct MemoryTranscriptComputeSegment: Codable, Equatable, Sendable {
  let token: String
  let speakerLabel: String
  let text: String
  let isUser: Bool

  enum CodingKeys: String, CodingKey {
    case token
    case speakerLabel = "speaker_label"
    case text
    case isUser = "is_user"
  }
}

struct MemoryExtractComputeRequest: Codable, Equatable, Sendable {
  let requestId: UUID
  let generation: Int
  let segments: [MemoryTranscriptComputeSegment]
  let language: String

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case generation, segments, language
  }
}

struct MemoryExtractComputeCandidate: Codable, Equatable, Sendable {
  let content: String
  let category: String
  let quote: String
  let segmentToken: String
  let speakerLabel: String
  let subject: String
  let about: String
  let archiveClass: String
  let riskFlags: [String]
  let sensitivityLabels: [String]
  let confidence: Double

  enum CodingKeys: String, CodingKey {
    case content, category, quote
    case segmentToken = "segment_token"
    case speakerLabel = "speaker_label"
    case subject, about
    case archiveClass = "archive_class"
    case riskFlags = "risk_flags"
    case sensitivityLabels = "sensitivity_labels"
    case confidence
  }
}

struct MemoryExtractComputeResponse: Codable, Equatable, Sendable {
  let requestId: UUID
  let generation: Int
  let candidates: [MemoryExtractComputeCandidate]

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case generation, candidates
  }
}

struct MemoryConsolidateComputeCandidate: Codable, Equatable, Sendable {
  let token: String
  let content: String
  let evidenceTokens: [String]
  let sensitivityLabels: [String]
  let subject: String
  let predicate: String?
  let arguments: [String: String]

  enum CodingKeys: String, CodingKey {
    case token, content
    case evidenceTokens = "evidence_tokens"
    case sensitivityLabels = "sensitivity_labels"
    case subject, predicate, arguments
  }
}

struct MemoryConsolidateComputeActiveMemory: Codable, Equatable, Sendable {
  let token: String
  let content: String
  let layer: String
  let revision: Int
  let subject: String
  let predicate: String?
  let arguments: [String: String]
  let sensitivityLabels: [String]

  enum CodingKeys: String, CodingKey {
    case token, content, layer, revision, subject, predicate, arguments
    case sensitivityLabels = "sensitivity_labels"
  }
}

struct MemoryConsolidateComputeRequest: Codable, Equatable, Sendable {
  let requestId: UUID
  let generation: Int
  let candidates: [MemoryConsolidateComputeCandidate]
  let activeMemories: [MemoryConsolidateComputeActiveMemory]

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case generation, candidates
    case activeMemories = "active_memories"
  }
}

struct MemoryConsolidateComputeDecision: Codable, Equatable, Sendable {
  let candidateToken: String
  let action: String
  let reconciliation: String
  let targetMemoryTokens: [String]
  let memoryText: String?
  let evidenceTokens: [String]
  let subject: String
  let predicate: String?
  let arguments: [String: String]
  let sensitivityLabels: [String]
  let relationshipToUser: String
  let aboutness: String
  let basisForMemory: String
  let confidence: String
  let rationale: String

  enum CodingKeys: String, CodingKey {
    case candidateToken = "candidate_token"
    case action, reconciliation
    case targetMemoryTokens = "target_memory_tokens"
    case memoryText = "memory_text"
    case evidenceTokens = "evidence_tokens"
    case subject, predicate, arguments
    case sensitivityLabels = "sensitivity_labels"
    case relationshipToUser = "relationship_to_user"
    case aboutness
    case basisForMemory = "basis_for_memory"
    case confidence
    case rationale
  }
}

struct MemoryConsolidateComputeResponse: Codable, Equatable, Sendable {
  let requestId: UUID
  let generation: Int
  let decisions: [MemoryConsolidateComputeDecision]

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case generation, decisions
  }
}

protocol MemoryComputing: Sendable {
  func normalizeMemory(
    _ request: MemoryNormalizeComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryNormalizeComputeResponse

  func extractMemories(
    _ request: MemoryExtractComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryExtractComputeResponse

  func consolidateMemories(
    _ request: MemoryConsolidateComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryConsolidateComputeResponse
}

extension APIClient: MemoryComputing {
  func normalizeMemory(
    _ request: MemoryNormalizeComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryNormalizeComputeResponse {
    try await post(
      "/v1/memory/compute/normalize", body: request,
      authorizationSnapshot: authorizationSnapshot)
  }

  func extractMemories(
    _ request: MemoryExtractComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryExtractComputeResponse {
    try await post(
      "/v1/memory/compute/extract", body: request,
      authorizationSnapshot: authorizationSnapshot)
  }

  func consolidateMemories(
    _ request: MemoryConsolidateComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryConsolidateComputeResponse {
    try await post(
      "/v1/memory/compute/consolidate", body: request,
      authorizationSnapshot: authorizationSnapshot)
  }
}
