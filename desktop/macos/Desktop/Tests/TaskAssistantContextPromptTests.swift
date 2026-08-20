import XCTest

@testable import Omi_Computer

final class TaskAssistantContextPromptTests: XCTestCase {
  func testActiveTasksExposeOnlyStableLocalIDs() {
    let context = TaskExtractionContext(
      activeTasks: [(id: "local_42", description: "Review the PR", priority: "high")],
      completedTasks: [],
      deletedTasks: [],
      goals: []
    )

    let prompt = TaskAssistant.contextEvidencePrompt(context)

    XCTAssertTrue(prompt.contains("[id:local_42] Review the PR [high]"))
    XCTAssertFalse(prompt.contains("STAGED"))
    XCTAssertFalse(prompt.contains("relevance"))
    XCTAssertFalse(prompt.contains("backend"))
  }

  func testSearchResultSerializesLocalTaskIDWithoutRank() throws {
    let result = TaskSearchResult(
      taskID: "local_42",
      description: "Local task",
      status: "active",
      similarity: 0.9,
      matchType: "vector"
    )
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )

    XCTAssertEqual(payload["task_id"] as? String, "local_42")
    XCTAssertNil(payload["relevance_score"])
  }

  func testEmptyContextRendersNothing() {
    let context = TaskExtractionContext(
      activeTasks: [], completedTasks: [], deletedTasks: [], goals: [])
    XCTAssertEqual(TaskAssistant.contextEvidencePrompt(context), "")
  }

  func testDirectAdmissionRequiresOwnedConcreteNonBroadcastCapture() {
    let accepted = makeTask(
      captureKind: "clear_commitment",
      owner: "user",
      concreteDeliverable: true,
      publicBroadcast: false,
      directMention: false,
      confidence: 0.86,
      ownershipConfidence: 0.9
    )
    XCTAssertTrue(TaskAssistant.shouldAdmit(accepted, minimumConfidence: 0.3))
    XCTAssertFalse(
      TaskAssistant.shouldAdmit(
        makeTask(
          captureKind: "clear_commitment", owner: "user", concreteDeliverable: true,
          publicBroadcast: true, directMention: true, confidence: 0.99,
          ownershipConfidence: 0.99),
        minimumConfidence: 0.3
      ))
    XCTAssertFalse(
      TaskAssistant.shouldAdmit(
        makeTask(
          captureKind: "direct_request", owner: "user", concreteDeliverable: true,
          publicBroadcast: false, directMention: false, confidence: 0.99,
          ownershipConfidence: 0.99),
        minimumConfidence: 0.3
      ))
  }

  func testStoredProvenanceRetainsCapturePolicyAndTypedEvidence() throws {
    let task = makeTask(
      captureKind: "explicit_command", owner: "user", concreteDeliverable: true,
      publicBroadcast: false, directMention: true, confidence: 0.92,
      ownershipConfidence: 0.95)
    let json = try XCTUnwrap(TaskAssistant.storedProvenance(for: task, screenshotId: 42))
    let provenance = try JSONDecoder().decode(
      StoredTaskProvenance.self,
      from: try XCTUnwrap(json.data(using: .utf8))
    )

    XCTAssertEqual(provenance.evidence.first?.id, "screenshot:42")
    XCTAssertEqual(provenance.evidence.first?.kind, .localScreen)
    XCTAssertEqual(provenance.capturePolicy?.captureKind, "explicit_command")
    XCTAssertEqual(provenance.capturePolicy?.ownershipConfidence, 0.95)
  }

  private func makeTask(
    captureKind: String,
    owner: String,
    concreteDeliverable: Bool,
    publicBroadcast: Bool,
    directMention: Bool,
    confidence: Double,
    ownershipConfidence: Double
  ) -> ExtractedTask {
    ExtractedTask(
      title: "Send the signed project brief to Mina",
      description: nil,
      priority: .medium,
      sourceApp: "Messages",
      inferredDeadline: nil,
      confidence: confidence,
      captureKind: captureKind,
      owner: owner,
      concreteDeliverable: concreteDeliverable,
      publicBroadcast: publicBroadcast,
      directMention: directMention,
      alreadyDone: false,
      duplicateOf: nil,
      refinesTask: nil,
      ownershipConfidence: ownershipConfidence
    )
  }
}
