import XCTest

@testable import Omi_Computer

final class OnboardingOpenerComposerTests: XCTestCase {
  private var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .gmt
    return cal
  }

  private func date(hour: Int) -> Date {
    // 2026-01-15 at the given UTC hour.
    let components = DateComponents(year: 2026, month: 1, day: 15, hour: hour)
    guard let date = utcCalendar.date(from: components) else {
      fatalError("Failed to build fixed test date for hour \(hour)")
    }
    return date
  }

  // MARK: timeOfDay

  func testTimeOfDayBuckets() {
    XCTAssertEqual(OnboardingOpenerComposer.timeOfDay(date(hour: 8), calendar: utcCalendar), "Morning")
    XCTAssertEqual(OnboardingOpenerComposer.timeOfDay(date(hour: 14), calendar: utcCalendar), "Afternoon")
    XCTAssertEqual(OnboardingOpenerComposer.timeOfDay(date(hour: 21), calendar: utcCalendar), "Evening")
    // Boundary + pre-dawn fall into Evening.
    XCTAssertEqual(OnboardingOpenerComposer.timeOfDay(date(hour: 3), calendar: utcCalendar), "Evening")
  }

  // MARK: greeting (short headline)

  func testGreetingIsTimeOfDayPlusName() {
    let g = OnboardingOpenerComposer.greeting(name: "Archit", now: date(hour: 8), calendar: utcCalendar)
    XCTAssertEqual(g, "Morning, Archit")
  }

  func testGreetingEmptyNameDropsComma() {
    let g = OnboardingOpenerComposer.greeting(name: "   ", now: date(hour: 8), calendar: utcCalendar)
    XCTAssertEqual(g, "Morning")
  }

  // MARK: subline

  func testSublineAlways() {
    let s = OnboardingOpenerComposer.subline(mode: .always)
    XCTAssertEqual(s, "I'm set up and listening. Ask me anything to start.")
  }

  func testSublineMeetingsOnly() {
    let s = OnboardingOpenerComposer.subline(mode: .meetingsOnly)
    XCTAssertEqual(s, "I'm set up and I'll listen during your meetings. Ask me anything to start.")
  }

  // MARK: starters

  func testStartersUseBaseCappedAtThree() {
    let starters = OnboardingOpenerComposer.starters(
      baseStarters: ["What should I do today?", "How is Atlas going?", "What did I miss?", "Extra?"])
    XCTAssertEqual(starters, ["What should I do today?", "How is Atlas going?", "What did I miss?"])
  }

  func testStartersDedupIsCaseInsensitiveAndDropsEmpties() {
    let starters = OnboardingOpenerComposer.starters(
      baseStarters: ["What should I do today?", "  ", "what should i do today?", "Next step?"])
    XCTAssertEqual(starters, ["What should I do today?", "Next step?"])
  }

  func testComposeBundlesGreetingSublineAndStarters() {
    let content = OnboardingOpenerComposer.compose(
      name: "Archit", mode: .always,
      now: date(hour: 8), baseStarters: ["What should I do today?"], calendar: utcCalendar)
    XCTAssertEqual(content.greeting, "Morning, Archit")
    XCTAssertEqual(content.subline, "I'm set up and listening. Ask me anything to start.")
    XCTAssertEqual(content.starters, ["What should I do today?"])
  }

  func testRetiredSuggestionDefaultsCannotEnterTheOpener() throws {
    let suiteName = "OnboardingOpenerComposerTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let retiredQuestion = "Private onboarding suggestion that must stay retired"
    let retiredSuggestionsKey = "postOnboardingPromptSuggestions"
    let retiredPopupKey = "showPostOnboardingPromptPopup"
    let retiredDismissalKey = "dismissedPostOnboardingPromptSuggestions"
    defaults.set([retiredQuestion], forKey: retiredSuggestionsKey)
    defaults.set(true, forKey: retiredPopupKey)
    defaults.set(false, forKey: retiredDismissalKey)

    let baseStarters = HomeSuggestionComposer.compose(personalized: [])
    let content = OnboardingOpenerComposer.compose(
      name: "Archit", mode: .meetingsOnly,
      now: date(hour: 8), baseStarters: baseStarters, calendar: utcCalendar)

    XCTAssertFalse(content.greeting.contains(retiredQuestion))
    XCTAssertFalse(content.subline.contains(retiredQuestion))
    XCTAssertFalse(content.starters.contains(retiredQuestion))
  }
}
