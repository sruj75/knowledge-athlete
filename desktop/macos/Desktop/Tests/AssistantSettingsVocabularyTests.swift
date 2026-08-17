import XCTest

@testable import Omi_Computer

@MainActor
final class AssistantSettingsVocabularyTests: XCTestCase {
  func testVocabularyIsStoredLocallyWithoutHydrationState() {
    let settings = AssistantSettings.shared
    let original = settings.transcriptionVocabulary
    defer { settings.transcriptionVocabulary = original }

    settings.transcriptionVocabulary = ["[[MARKER:vocabulary-race]]"]

    XCTAssertEqual(settings.transcriptionVocabulary, ["[[MARKER:vocabulary-race]]"])
    XCTAssertEqual(
      UserDefaults.standard.stringArray(forKey: .transcriptionVocabulary),
      ["[[MARKER:vocabulary-race]]"])
  }
}
