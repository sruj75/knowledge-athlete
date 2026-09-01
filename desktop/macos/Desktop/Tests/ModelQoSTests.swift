import XCTest

@testable import Omi_Computer

final class ModelQoSTests: XCTestCase {
  func testChatUsesGemini37Flash() {
    XCTAssertEqual(ModelQoS.Gemini.chat, "gemini-3.7-flash")
  }

  func testGeminiModelsUseFixedRetainedRoutes() {
    XCTAssertEqual(ModelQoS.Gemini.proactive, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.taskExtraction, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.insight, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.suggestions, "gemini-2.5-flash-lite")
    XCTAssertEqual(ModelQoS.Gemini.embedding, "gemini-embedding-001")
  }

}
