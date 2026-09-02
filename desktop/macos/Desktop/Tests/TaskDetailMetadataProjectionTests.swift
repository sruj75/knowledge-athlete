import XCTest

@testable import Omi_Computer

final class TaskDetailMetadataProjectionTests: XCTestCase {
  func testDetailsExposeOnlyExplicitRetainedFacts() {
    let task = TaskActionItem(
      id: "local_7",
      description: "Send the launch note",
      completed: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      conversationId: "raw-source-session-id",
      source: "screenshot",
      priority: "high",
      screenshotId: 9,
      confidence: 0.91,
      sourceApp: "Mail",
      windowTitle: "Launch",
      contextSummary: "Preparing the announcement",
      currentActivity: "Writing"
    )

    XCTAssertTrue(task.hasDetailMetadata)
    XCTAssertTrue(task.chatContext.contains("Source app: Mail"))
    XCTAssertTrue(task.chatContext.contains("Extraction confidence: 91%"))
    XCTAssertFalse(task.chatContext.contains("raw-source-session-id"))
    XCTAssertFalse(task.chatContext.lowercased().contains("metadata"))
    XCTAssertFalse(task.chatContext.lowercased().contains("goal id"))
  }

  func testManualTaskWithoutProvenanceHasNoDetailMetadata() {
    let task = TaskActionItem(
      id: "local_8",
      description: "Buy tea",
      completed: false,
      createdAt: Date(),
      source: "manual"
    )
    XCTAssertFalse(task.hasDetailMetadata)
  }

  func testRetiredOmiTranscriptionSourceRendersAsGenericTaskProvenance() {
    let task = TaskActionItem(
      id: "local_9",
      description: "Review notes",
      completed: false,
      createdAt: Date(),
      source: "transcription:omi"
    )

    XCTAssertEqual(task.sourceLabel, "Task")
    XCTAssertEqual(task.sourceIcon, "list.bullet")
  }
}
