import Foundation

extension TaskAssistant {
  /// Parse an inferred deadline string into a Date, or default to end of today.
  /// Tries ISO8601, then common natural language patterns.
  func parseDueDate(from inferredDeadline: String?) -> Date? {
    guard let deadline = inferredDeadline, !deadline.isEmpty else {
      return nil
    }
    let startOfToday = Calendar.current.startOfDay(for: Date())

    // Try ISO8601 first (e.g. "2025-10-04T14:00:00Z")
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: deadline) {
      if date < startOfToday {
        log(
          "Task: Rejected past due date '\(deadline)' → \(date). Today is \(Date()). Due dates must be today or in the future."
        )
        return nil
      }
      return date
    }
    // Try common date formats
    let formats = [
      "yyyy-MM-dd'T'HH:mm:ssZ",
      "yyyy-MM-dd'T'HH:mm:ss",
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd",
      "MM/dd/yyyy",
      "MMMM d, yyyy",
      "MMM d, yyyy",
      "MMMM d",
      "MMM d",
    ]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: deadline) {
        if date < startOfToday {
          log(
            "Task: Rejected past due date '\(deadline)' → \(date). Today is \(Date()). Due dates must be today or in the future."
          )
          return nil
        }
        return date
      }
    }

    // Fallback: try macOS natural language date parsing (handles "Thursday", "next week", etc.)
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    if let match = detector?.firstMatch(in: deadline, range: NSRange(deadline.startIndex..., in: deadline)),
      let date = match.date
    {
      // Validate that the parsed date is not in the past
      let startOfToday = Calendar.current.startOfDay(for: Date())
      if date < startOfToday {
        log(
          "Task: Rejected past due date '\(deadline)' → \(date). Today is \(Date()). Due dates must be today or in the future."
        )
        return nil
      }
      return date
    }

    log("Task: Could not parse inferred_deadline '\(deadline)', skipping deadline")
    return nil
  }

  /// Returns 11:59 PM today in the user's local timezone
  static func endOfToday() -> Date {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: Date())
    return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: startOfDay) ?? startOfDay
  }
}
