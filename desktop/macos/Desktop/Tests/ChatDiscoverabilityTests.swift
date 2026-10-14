import XCTest

@testable import Omi_Computer

final class ChatDiscoverabilityTests: XCTestCase {

  // MARK: - Schema Footer

  // MARK: - Column Annotations

  func testColumnAnnotationsExistForAllAnnotatedTables() {
    let annotatedTables = ChatPrompts.tableAnnotations.keys
    for table in annotatedTables {
      // Every table in tableAnnotations should have columnAnnotations
      // (except tables added without column docs — those are OK)
      if let cols = ChatPrompts.columnAnnotations[table] {
        XCTAssertFalse(cols.isEmpty, "Column annotations for \(table) should not be empty")
      }
    }
  }

  func testScreenshotsHasKeyColumnAnnotations() {
    let cols = ChatPrompts.columnAnnotations["screenshots"]!
    XCTAssertNotNil(cols["timestamp"])
    XCTAssertNotNil(cols["appName"])
    XCTAssertNotNil(cols["ocrText"])
  }

  func testActionItemsHasKeyColumnAnnotations() {
    let cols = ChatPrompts.columnAnnotations["action_items"]!
    XCTAssertNotNil(cols["description"])
    XCTAssertNotNil(cols["completed"])
    XCTAssertNotNil(cols["priority"])
    XCTAssertNotNil(cols["screenshotId"])
    XCTAssertEqual(cols["source"], "Origin: assistant | conversation | manual | recurring | screenshot | task")
    XCTAssertFalse(cols["source"]?.lowercased().contains("omi") ?? true)
  }

  func testMemoriesHasKeyColumnAnnotations() {
    let cols = ChatPrompts.columnAnnotations["memories"]!
    for retained in [
      "content", "category", "layer", "expiresAt", "revision", "sourceSegmentId",
      "pendingDeleteDeadline", "correctedAt",
    ] {
      XCTAssertNotNil(cols[retained], "Missing local Memory column \(retained)")
    }
    for retired in ["visibility", "reviewed", "userReview", "scoring", "deleted", "backendId"] {
      XCTAssertNil(cols[retired], "Retired hosted Memory column \(retired) must not be advertised")
    }
    XCTAssertNotNil(cols["source"])
    XCTAssertNotNil(cols["tagsJson"], "Tips Insights remain discoverable through canonical Memories")
    XCTAssertTrue(ChatPrompts.tableAnnotations["memories"]?.contains("Insights") == true)
    XCTAssertNil(ChatPrompts.tableAnnotations["proactive_extractions"])
    XCTAssertNil(ChatPrompts.columnAnnotations["proactive_extractions"])
  }

  func testConversationPromptSchemaMatchesLocalAuthority() throws {
    let sessions = try XCTUnwrap(ChatPrompts.columnAnnotations["transcription_sessions"])
    let segments = try XCTUnwrap(ChatPrompts.columnAnnotations["transcription_segments"])

    for retained in ["conversationId", "status", "contentGeneration", "isTitleManuallyEdited"] {
      XCTAssertNotNil(sessions[retained], "Missing local conversation column \(retained)")
    }
    for retired in ["backendId", "pendingUpload", "retryCount", "discarded", "deleted", "isLocked", "category"] {
      XCTAssertNil(sessions[retired], "Retired conversation column \(retired) must not be advertised")
    }
    XCTAssertNotNil(segments["speakerId"])
    XCTAssertNil(segments["speaker"])
    XCTAssertNil(segments["speakerLabel"])
    XCTAssertNil(segments["personId"])

  }

  // MARK: - Excluded Tables and Columns

  // MARK: - Tool Prompt

  private func readToolNames(from relativePath: String) throws -> Set<String> {
    let testFile = URL(fileURLWithPath: #filePath)
    let desktopDir = testFile.deletingLastPathComponent().deletingLastPathComponent()
    let macOSDir = desktopDir.deletingLastPathComponent()
    let file = macOSDir.appendingPathComponent(relativePath)
    let text = try String(contentsOf: file)
    let regex = try NSRegularExpression(pattern: #"name:\s*"([^"]+)""#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return Set(
      regex.matches(in: text, range: range).compactMap { match in
        guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[nameRange])
      })
  }

  func testTableAnnotationsIncludeAllExpectedTables() {
    let expected = [
      "screenshots", "action_items", "transcription_sessions", "transcription_segments",
      "focus_sessions", "live_notes", "memories", "ai_user_profiles",
      "goals", "observations",
    ]
    for table in expected {
      XCTAssertNotNil(
        ChatPrompts.tableAnnotations[table],
        "Missing tableAnnotation for \(table)")
    }
  }
}
