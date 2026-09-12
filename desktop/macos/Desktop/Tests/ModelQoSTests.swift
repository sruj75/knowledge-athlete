import XCTest

@testable import Omi_Computer

final class ModelQoSTests: XCTestCase {
  func testChatUsesGemini37Flash() {
    XCTAssertEqual(ModelQoS.Gemini.chat, "gemini-3.7-flash")
  }

  // #102: the owned account returns 404 for 2.5 Flash and Flash-Lite. The
  // already-working managed Chat model must also serve background inference.
  func testBackgroundModelsUseTheAccountAvailableFlashRoute() {
    XCTAssertEqual(ModelQoS.Gemini.proactive, "gemini-3.7-flash")
    XCTAssertEqual(ModelQoS.Gemini.taskExtraction, "gemini-3.7-flash")
    XCTAssertEqual(ModelQoS.Gemini.insight, "gemini-3.7-flash")
    XCTAssertEqual(ModelQoS.Gemini.suggestions, "gemini-3.7-flash")
    XCTAssertEqual(ModelQoS.Gemini.embedding, "gemini-embedding-001")
  }

}
