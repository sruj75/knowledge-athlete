import Foundation
@preconcurrency import GRDB

struct LocalGoal: Identifiable, Equatable, Sendable {
  let id: String
  let rowID: Int64
  var title: String
  var description: String?
  var isActive: Bool
  var completedAt: Date?
  let createdAt: Date
  var updatedAt: Date
}

struct GoalRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  var id: Int64?
  var title: String
  var goalDescription: String?
  var isActive: Bool
  var completedAt: Date?
  var createdAt: Date
  var updatedAt: Date

  static let databaseTableName = "goals"

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }

  func toLocalGoal() -> LocalGoal? {
    guard let id else { return nil }
    return LocalGoal(
      id: "local_\(id)",
      rowID: id,
      title: title,
      description: goalDescription,
      isActive: isActive,
      completedAt: completedAt,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}

extension GoalRecord: TableDocumented {
  static var tableDescription: String { "Simple goals stored only in the current owner's local database." }
  static var columnDescriptions: [String: String] {
    [
      "id": "Stable local goal row ID.",
      "title": "Goal title.",
      "goalDescription": "Optional goal description.",
      "isActive": "Whether the goal is active rather than completed.",
      "completedAt": "Local completion timestamp.",
      "createdAt": "Local creation timestamp.",
      "updatedAt": "Local update timestamp.",
    ]
  }
}
