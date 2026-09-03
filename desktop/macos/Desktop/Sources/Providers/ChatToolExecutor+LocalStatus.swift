import Foundation

extension ChatToolExecutor {
  static let localAffordances = [
    "Rewind screen history and OCR search",
    "raw screenshot image retrieval by screenshot_id",
    "local transcription and conversation tables",
    "read-only SQL over the local Intentive Desktop database",
    "daily activity recaps",
    "indexed files and app/window activity",
    "local goals and progress data",
    "local task search, completion, and deletion",
  ]

  static func localAffordancesJSON() -> String {
    guard
      let data = try? JSONSerialization.data(withJSONObject: localAffordances, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return json
  }

  static func emptySemanticSearchMessage(
    query: String,
    days: Int,
    appFilter: String?,
    expectedOwnerID: String?
  ) async -> String {
    guard isExpectedOwnerCurrent(expectedOwnerID) else { return authorizedOwnerChangedResult() }
    guard let authorizationSnapshot = currentOwnerAuthorizationSnapshot else {
      return authorizedOwnerChangedResult()
    }
    do {
      let stats = try await RewindDatabase.shared.getStats(
        authorizationSnapshot: authorizationSnapshot)
      guard isExpectedOwnerCurrent(expectedOwnerID) else { return authorizedOwnerChangedResult() }
      if stats.total == 0 {
        return """
          No screen history is available yet. Intentive Desktop has not captured screenshots on this Mac, so there are no results for "\(query)".
          """
      }
      if stats.indexed == 0 {
        return """
          Intentive has \(stats.total) screenshot(s), but they are not ready to search yet. Keep Intentive Desktop running and try again in a bit, or use SQL for exact local checks.
          """
      }
      let appText = appFilter.map { " with app filter \"\($0)\"" } ?? ""
      return """
        No matching screen-history results for "\(query)" in the last \(days) day(s)\(appText). Local history exists (\(stats.total) screenshot(s), \(stats.indexed) indexed), so try a broader query, a wider days window, or use execute_sql for exact app/window/OCR filters.
        """
    } catch {
      return
        "No screenshots found matching \"\(query)\" in the last \(days) day(s). Local status could not be read: \(error.localizedDescription)"
    }
  }
}
