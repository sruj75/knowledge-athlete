import Foundation

enum TaskPriority: String, Codable {
  case high
  case medium
  case low
}

/// The capture facts returned by Gemini. Approved captures preserve these
/// policy facts inside typed local provenance for auditability.
struct ExtractedTask: Codable {
  let title: String
  let description: String?
  let priority: TaskPriority
  let sourceApp: String
  let inferredDeadline: String?
  let confidence: Double
  let captureKind: String?
  let owner: String?
  let concreteDeliverable: Bool?
  let publicBroadcast: Bool?
  let directMention: Bool?
  let alreadyDone: Bool?
  let duplicateOf: String?
  let refinesTask: String?
  let ownershipConfidence: Double?

  enum CodingKeys: String, CodingKey {
    case title
    case description
    case priority
    case sourceApp = "source_app"
    case inferredDeadline = "inferred_deadline"
    case confidence
    case captureKind = "capture_kind"
    case owner
    case concreteDeliverable = "concrete_deliverable"
    case publicBroadcast = "public_broadcast"
    case directMention = "direct_mention"
    case alreadyDone = "already_done"
    case duplicateOf = "duplicate_of"
    case refinesTask = "refines_task"
    case ownershipConfidence = "ownership_confidence"
  }

  func toDictionary() -> [String: Any] {
    var dictionary: [String: Any] = [
      "title": title,
      "priority": priority.rawValue,
      "sourceApp": sourceApp,
      "confidence": confidence,
      "captureKind": captureKind ?? "direct_request",
      "owner": owner ?? "unknown",
    ]
    if let description { dictionary["description"] = description }
    if let inferredDeadline { dictionary["inferredDeadline"] = inferredDeadline }
    return dictionary
  }
}

struct TaskExtractionResult: Codable, AssistantResult {
  let hasNewTask: Bool
  let task: ExtractedTask?
  let contextSummary: String
  let currentActivity: String

  enum CodingKeys: String, CodingKey {
    case hasNewTask = "has_new_task"
    case task
    case contextSummary = "context_summary"
    case currentActivity = "current_activity"
  }

  func toDictionary() -> [String: Any] {
    var dictionary: [String: Any] = [
      "hasNewTask": hasNewTask,
      "contextSummary": contextSummary,
      "currentActivity": currentActivity,
    ]
    if let task { dictionary["task"] = task.toDictionary() }
    return dictionary
  }
}

/// Local evidence supplied to Gemini for duplicate and refinement decisions.
struct TaskExtractionContext {
  let activeTasks: [(id: String, description: String, priority: String?)]
  let completedTasks: [(id: Int64, description: String)]
  let deletedTasks: [(id: Int64, description: String)]
  let goals: [LocalGoal]
}

struct TaskSearchResult: Codable {
  let taskID: String?
  let description: String
  let status: String
  let similarity: Double?
  let matchType: String

  enum CodingKeys: String, CodingKey {
    case taskID = "task_id"
    case description, status, similarity
    case matchType = "match_type"
  }
}
