import XCTest

@testable import Omi_Computer

final class HomeRetainedContextProjectionTests: XCTestCase {
  func testProjectionKeepsFocusLatestVisibleInsightAndDailyQuestions() {
    let older = makeInsight(id: "older", text: "Older", createdAt: Date(timeIntervalSince1970: 10))
    let dismissed = makeInsight(
      id: "dismissed",
      text: "Do not surface",
      createdAt: Date(timeIntervalSince1970: 30),
      dismissed: true
    )
    let latest = makeInsight(id: "latest", text: "Protect deep work", createdAt: Date(timeIntervalSince1970: 20))

    let projection = HomeRetainedContextProjection.make(
      focusStatus: .focused,
      currentApp: "Xcode",
      detectedApp: nil,
      insights: [older, dismissed, latest],
      personalizedQuestions: ["How should I sequence Geneva today?"]
    )

    XCTAssertEqual(projection.focusTitle, "Focused")
    XCTAssertEqual(projection.focusDetail, "Working in Xcode")
    XCTAssertEqual(projection.latestInsight, .init(id: "latest", text: "Protect deep work"))
    XCTAssertEqual(projection.questions.first, HomeSuggestionComposer.universalFirstQuestion)
    XCTAssertTrue(projection.questions.contains("How should I sequence Geneva today?"))
  }

  func testProjectionRetainsUsefulFocusFallbackWithoutAnActiveJudgment() {
    let projection = HomeRetainedContextProjection.make(
      focusStatus: nil,
      currentApp: nil,
      detectedApp: "Safari",
      insights: [],
      personalizedQuestions: []
    )

    XCTAssertEqual(projection.focusTitle, "Focus is ready")
    XCTAssertEqual(projection.focusDetail, "Watching Safari")
    XCTAssertNil(projection.latestInsight)
    XCTAssertEqual(projection.questions, HomeSuggestionComposer.compose(personalized: []))
  }

  private func makeInsight(
    id: String,
    text: String,
    createdAt: Date,
    dismissed: Bool = false
  ) -> StoredInsight {
    StoredInsight(
      id: id,
      insight: ExtractedInsight(
        insight: text,
        headline: nil,
        reasoning: nil,
        category: .productivity,
        sourceApp: "Xcode",
        confidence: 0.9
      ),
      contextSummary: "",
      currentActivity: "",
      createdAt: createdAt,
      isRead: false,
      isDismissed: dismissed
    )
  }
}
