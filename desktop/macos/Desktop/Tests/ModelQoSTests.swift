import XCTest

@testable import Omi_Computer

final class ModelQoSTests: XCTestCase {
  func testChatModelsUseSonnet() {
    XCTAssertEqual(ModelQoS.Claude.chat, "claude-sonnet-4-6")
    XCTAssertEqual(ModelQoS.Claude.floatingBar, "claude-sonnet-4-6")
  }

  func testGeminiModelsUseFixedRetainedRoutes() {
    XCTAssertEqual(ModelQoS.Gemini.proactive, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.taskExtraction, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.insight, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.suggestions, "gemini-2.5-flash-lite")
    XCTAssertEqual(ModelQoS.Gemini.embedding, "gemini-embedding-001")
  }

}
