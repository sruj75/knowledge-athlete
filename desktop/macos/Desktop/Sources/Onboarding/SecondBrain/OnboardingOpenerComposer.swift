import Foundation

/// The personalized first beat shown in the Chat tab the instant onboarding
/// finishes: a greeting addressed to the user by name + tappable starter
/// questions that fire real Intentive queries.
struct OnboardingOpenerContent: Equatable {
  /// Short headline: time of day + name ("Afternoon, Nik").
  let greeting: String
  /// Muted detail line under the headline: the chosen listening state.
  let subline: String
  let starters: [String]
}

/// Pure, deterministic composer for the post-onboarding opener. Kept free of
/// any live service or `@MainActor` state so it renders instantly at the
/// fragile handoff moment and is fully unit-testable. The caller supplies the
/// live inputs (name, listening mode, and normal Home starter chips).
enum OnboardingOpenerComposer {
  enum ListeningMode: Equatable { case always, meetingsOnly }

  static let maxStarters = 3

  static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
    switch calendar.component(.hour, from: date) {
    case 5..<12: return "Morning"
    case 12..<17: return "Afternoon"
    default: return "Evening"
    }
  }

  static func compose(
    name: String,
    mode: ListeningMode,
    now: Date,
    baseStarters: [String],
    calendar: Calendar = .current
  ) -> OnboardingOpenerContent {
    OnboardingOpenerContent(
      greeting: greeting(name: name, now: now, calendar: calendar),
      subline: subline(mode: mode),
      starters: starters(baseStarters: baseStarters)
    )
  }

  /// Short headline only — the detail moved to `subline` so the headline can
  /// render large without wrapping into a paragraph.
  static func greeting(name: String, now: Date, calendar: Calendar = .current) -> String {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let tod = timeOfDay(now, calendar: calendar)
    return trimmedName.isEmpty ? tod : "\(tod), \(trimmedName)"
  }

  static func subline(mode: ListeningMode) -> String {
    let setup = mode == .always ? "I'm set up and listening." : "I'm set up and I'll listen during your meetings."
    return "\(setup) Ask me anything to start."
  }

  /// Normal Home chips (universal + personalized), de-duplicated and capped.
  static func starters(baseStarters: [String]) -> [String] {
    var out: [String] = []
    for candidate in baseStarters {
      let q = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !q.isEmpty, out.count < maxStarters else { continue }
      if !out.contains(where: { $0.lowercased() == q.lowercased() }) {
        out.append(q)
      }
    }
    return Array(out.prefix(maxStarters))
  }
}
