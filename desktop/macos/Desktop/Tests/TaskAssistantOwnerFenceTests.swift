import XCTest

@testable import Omi_Computer

@MainActor
final class TaskAssistantOwnerFenceTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture!
  private var rewindFixture: RewindStorageTestIsolation.Fixture!
  private var authSnapshot: RewindStorageTestIsolation.AuthSnapshot!
  private var savedEnabled = false

  override func setUp() async throws {
    try await super.setUp()
    authSnapshot = RewindStorageTestIsolation.captureAuthSnapshot()
    rewindFixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "task-assistant-owner")
    ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: rewindFixture.testUserId)
    savedEnabled = TaskAssistantSettings.shared.isEnabled
    TaskAssistantSettings.shared.isEnabled = true
  }

  override func tearDown() async throws {
    TaskAssistantSettings.shared.isEnabled = savedEnabled
    await ownerFixture.restore()
    ownerFixture = nil
    RewindStorageTestIsolation.restoreAuthSnapshot(authSnapshot)
    authSnapshot = nil
    await RewindStorageTestIsolation.tearDown(userDir: rewindFixture.userDir)
    rewindFixture = nil
    try await super.tearDown()
  }

  func testSameUIDReauthenticationDropsSuspendedTaskAnalysis() async throws {
    let result = TaskExtractionResult(
      hasNewTask: true,
      task: ExtractedTask(
        title: "Send Alice the completed quarterly project report",
        description: nil,
        priority: .high,
        sourceApp: "Messages",
        inferredDeadline: nil,
        confidence: 0.95,
        captureKind: "direct_request",
        owner: "user",
        concreteDeliverable: true,
        publicBroadcast: false,
        directMention: true,
        alreadyDone: false,
        duplicateOf: nil,
        refinesTask: nil,
        ownershipConfidence: 0.95),
      contextSummary: "private context",
      currentActivity: "messaging")
    let gate = TaskExtractionGate(result: ([result], 0))
    let assistant = TaskAssistant { _, _, _ in try await gate.extract() }

    let processing = Task {
      await assistant.processFrame(
        CapturedFrame(
          jpegData: Data([0xFF, 0xD8, 0xFF]),
          appName: "Messages",
          frameNumber: 1))
    }
    await gate.waitUntilEntered()
    await ownerFixture.establish(authOwnerID: nil)
    await ownerFixture.establish(authOwnerID: rewindFixture.testUserId)
    await gate.release()
    await processing.value

    let tasks = try await ActionItemStorage.shared.getLocalActionItems(limit: 100)
    XCTAssertTrue(tasks.isEmpty)
  }
}

private actor TaskExtractionGate {
  private let result: ([TaskExtractionResult], Int)
  private var entered = false
  private var released = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  init(result: ([TaskExtractionResult], Int)) {
    self.result = result
  }

  func extract() async throws -> ([TaskExtractionResult], Int) {
    entered = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if !released {
      await withCheckedContinuation { releaseWaiters.append($0) }
    }
    return result
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func release() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
