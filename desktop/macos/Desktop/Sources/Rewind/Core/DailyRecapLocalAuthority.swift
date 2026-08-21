import Foundation
@preconcurrency import GRDB

/// Owner-fenced six-section read model for the live local database. Conversation
/// and Task rows deliberately remain unbounded; the other presentation caps are
/// the reviewed realtime recap contract.
actor DailyRecapLocalAuthority {
  static let shared = DailyRecapLocalAuthority()

  private let injectedDatabasePool: DatabasePool?

  init(databasePool: DatabasePool? = nil) {
    injectedDatabasePool = databasePool
  }

  func recap(
    daysAgo: Int,
    now: Date = Date(),
    calendar: Calendar = .current,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> String {
    let boundedDays = max(0, daysAgo)
    let lowerReference = calendar.date(byAdding: .day, value: -boundedDays, to: now) ?? now
    let lowerBound = calendar.startOfDay(for: lowerReference)
    let upperBound = boundedDays == 0 ? now : calendar.startOfDay(for: now)
    let dateLabel = boundedDays == 0 ? "Today" : boundedDays == 1 ? "Yesterday" : "Past \(boundedDays) days"
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    let pool: DatabasePool
    if let injectedDatabasePool {
      pool = injectedDatabasePool
    } else {
      guard let current = await RewindDatabase.shared.getDatabaseQueue() else {
        throw DailyRecapLocalAuthorityError.databaseUnavailable
      }
      pool = current
    }

    return try await authorization.withReadLease {
      try await pool.read { db in
        try authorization.require()
        let bounds: StatementArguments = [lowerBound, upperBound]
        let apps = try Row.fetchAll(
          db,
          sql: """
            SELECT appName, COUNT(*) AS screenshots, ROUND(COUNT(*) * 10.0 / 60, 1) AS minutes,
                   MIN(time(timestamp, 'localtime')) AS first_seen,
                   MAX(time(timestamp, 'localtime')) AS last_seen
            FROM screenshots
            WHERE timestamp >= ? AND timestamp < ? AND appName != ''
            GROUP BY appName ORDER BY screenshots DESC, appName
            """,
          arguments: bounds)
        let conversations = try Row.fetchAll(
          db,
          sql: """
            SELECT title, overview, emoji, startedAt, finishedAt,
                   ROUND((julianday(finishedAt) - julianday(startedAt)) * 1440, 1) AS duration_min
            FROM transcription_sessions
            WHERE startedAt >= ? AND startedAt < ? AND status NOT IN ('recording', 'merging')
            ORDER BY startedAt DESC, id DESC
            """,
          arguments: bounds)
        let tasks = try Row.fetchAll(
          db,
          sql: """
            SELECT description, completed, priority, createdAt
            FROM action_items
            WHERE createdAt >= ? AND createdAt < ? AND deleted = 0
            ORDER BY createdAt DESC, id DESC
            """,
          arguments: bounds)
        let focus = try Row.fetchAll(
          db,
          sql: """
            SELECT status, appOrSite, description, durationSeconds
            FROM focus_sessions
            WHERE createdAt >= ? AND createdAt < ?
            ORDER BY createdAt DESC, id DESC
            """,
          arguments: bounds)
        let memories = try Row.fetchAll(
          db,
          sql: """
            SELECT content, category, source
            FROM memories
            WHERE createdAt >= ? AND createdAt < ?
              AND pendingDeleteDeadline IS NULL AND isDismissed = 0
            ORDER BY createdAt DESC, id DESC
            """,
          arguments: bounds)
        let observations = try Row.fetchAll(
          db,
          sql: """
            SELECT appName, currentActivity, contextSummary
            FROM observations
            WHERE createdAt >= ? AND createdAt < ?
            ORDER BY createdAt DESC, id DESC
            """,
          arguments: bounds)
        try authorization.require()
        return Self.format(
          dateLabel: dateLabel,
          apps: apps,
          conversations: conversations,
          tasks: tasks,
          focus: focus,
          memories: memories,
          observations: observations)
      }
    }
  }

  private nonisolated static func format(
    dateLabel: String,
    apps: [Row],
    conversations: [Row],
    tasks: [Row],
    focus: [Row],
    memories: [Row],
    observations: [Row]
  ) -> String {
    var output = "# \(dateLabel) Recap\n\n"
    output += "## Apps (\(apps.count) apps)\n"
    if apps.isEmpty {
      output += "No screen activity recorded.\n"
    } else {
      for app in apps.prefix(20) {
        let name: String = app["appName"]
        let minutes: Double = app["minutes"]
        let screenshots: Int = app["screenshots"]
        let firstSeen: String = app["first_seen"]
        let lastSeen: String = app["last_seen"]
        output += "- **\(name)**: \(minutes) min (\(screenshots) captures, \(firstSeen)–\(lastSeen))\n"
      }
      if apps.count > 20 { output += "- ...and \(apps.count - 20) more apps\n" }
    }

    output += "\n## Conversations (\(conversations.count))\n"
    if conversations.isEmpty {
      output += "No conversations recorded.\n"
    } else {
      for conversation in conversations {
        let title: String? = conversation["title"]
        let overview: String? = conversation["overview"]
        let emoji: String? = conversation["emoji"]
        let duration: Double? = conversation["duration_min"]
        let durationText = duration.flatMap { $0 > 0 ? " (\($0) min)" : nil } ?? ""
        output += "- \(emoji ?? "") **\(title ?? "Untitled")**\(durationText): \(overview ?? "No summary")\n"
      }
    }

    output += "\n## Tasks (\(tasks.count))\n"
    if tasks.isEmpty {
      output += "No tasks created.\n"
    } else {
      for task in tasks {
        let description: String = task["description"]
        let completed: Bool = task["completed"]
        let priority: String? = task["priority"]
        output += "- \(completed ? "[x]" : "[ ]") \(description)\(priority.map { " (\($0))" } ?? "")\n"
      }
    }

    let focused = focus.filter { ($0["status"] as String) == "focused" }
    let distracted = focus.filter { ($0["status"] as String) == "distracted" }
    output += "\n## Focus (\(focused.count) focused, \(distracted.count) distracted)\n"
    if focus.isEmpty {
      output += "No focus sessions recorded.\n"
    } else {
      for session in focus.prefix(10) {
        let status: String = session["status"]
        let app: String = session["appOrSite"]
        let description: String = session["description"]
        let duration: Int? = session["durationSeconds"]
        let durationText = duration.flatMap { $0 > 0 ? " (\($0 / 60)m)" : nil } ?? ""
        output += "- \(status == "focused" ? "+" : "-") \(app)\(durationText): \(description)\n"
      }
      if focus.count > 10 { output += "- ...and \(focus.count - 10) more sessions\n" }
    }

    output += "\n## Memories Learned (\(memories.count))\n"
    if memories.isEmpty {
      output += "No memories learned.\n"
    } else {
      for memory in memories.prefix(10) {
        let content: String = memory["content"]
        let category: String = memory["category"]
        output += "- \(content)\(category.isEmpty ? "" : " [\(category)]")\n"
      }
      if memories.count > 10 { output += "- ...and \(memories.count - 10) more\n" }
    }

    output += "\n## Screen Context (\(observations.count) observations)\n"
    if observations.isEmpty {
      output += "No screen context recorded.\n"
    } else {
      for observation in observations.prefix(20) {
        let app: String = observation["appName"]
        let activity: String = observation["currentActivity"]
        output += "- \(app): \(activity)\n"
      }
      if observations.count > 20 {
        output += "- ...and \(observations.count - 20) more observations\n"
      }
    }
    return output
  }
}

enum DailyRecapLocalAuthorityError: LocalizedError {
  case databaseUnavailable

  var errorDescription: String? { "database not available" }
}
