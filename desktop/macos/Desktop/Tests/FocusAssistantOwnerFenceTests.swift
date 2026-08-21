import Foundation
import XCTest

@testable import Omi_Computer

@MainActor
final class FocusAssistantOwnerFenceTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture!
  private var savedEnabled = false
  private var savedNotifications = false

  override func setUp() async throws {
    ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: "focus-owner")
    savedEnabled = FocusAssistantSettings.shared.isEnabled
    savedNotifications = FocusAssistantSettings.shared.notificationsEnabled
    FocusAssistantSettings.shared.isEnabled = true
    FocusAssistantSettings.shared.notificationsEnabled = true
  }

  override func tearDown() async throws {
    FocusAssistantSettings.shared.isEnabled = savedEnabled
    FocusAssistantSettings.shared.notificationsEnabled = savedNotifications
    await ownerFixture.restore()
    ownerFixture = nil
  }

  func testSameUIDReauthenticationDropsSuspendedAnalysisBeforePersistenceOrPublication() async {
    let gate = FocusAnalysisGate(result: distractedAnalysis)
    let recorder = FocusEventRecorder()
    let assistant = FocusAssistant(
      analysisOverride: { _, _ in try await gate.analyze() },
      focusSessionPersister: { record, _ in
        recorder.append("persist")
        var inserted = record
        inserted.id = 1
        return inserted
      },
      onAlert: { _ in recorder.append("alert") },
      onStatusChange: { _ in recorder.append("status") },
      onDistraction: { recorder.append("distraction") })

    let processing = Task {
      await assistant.processFrame(
        CapturedFrame(
          jpegData: Data([0xFF, 0xD8, 0xFF]),
          appName: "Safari",
          frameNumber: 1))
    }
    await gate.waitUntilEntered()
    await ownerFixture.establish(authOwnerID: nil)
    await ownerFixture.establish(authOwnerID: "focus-owner")
    await gate.release()
    await processing.value

    XCTAssertEqual(recorder.values, [])
    let historyCount = await assistant.analysisHistoryCount
    XCTAssertEqual(historyCount, 0)
  }

  func testPersistenceFailurePublishesNoFocusStateOrCallbacks() async {
    let recorder = FocusEventRecorder()
    let analysis = distractedAnalysis
    let assistant = FocusAssistant(
      analysisOverride: { _, _ in analysis },
      focusSessionPersister: { _, _ in
        recorder.append("persist_attempt")
        throw FocusPersistenceFixtureError.failed
      },
      onAlert: { _ in recorder.append("alert") },
      onStatusChange: { _ in recorder.append("status") },
      onDistraction: { recorder.append("distraction") })

    await assistant.processFrame(
      CapturedFrame(
        jpegData: Data([0xFF, 0xD8, 0xFF]),
        appName: "Safari",
        frameNumber: 2))

    XCTAssertEqual(recorder.values, ["persist_attempt"])
    let historyCount = await assistant.analysisHistoryCount
    XCTAssertEqual(historyCount, 0)
  }

  private var distractedAnalysis: ScreenAnalysis {
    ScreenAnalysis(
      status: .distracted,
      appOrSite: "Safari",
      description: "Browsing unrelated content",
      message: "Return to your task")
  }
}

private enum FocusPersistenceFixtureError: Error {
  case failed
}

private final class FocusEventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  func append(_ value: String) {
    lock.withLock { storage.append(value) }
  }

  var values: [String] {
    lock.withLock { storage }
  }
}

private actor FocusAnalysisGate {
  private let result: ScreenAnalysis
  private var entered = false
  private var released = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  init(result: ScreenAnalysis) {
    self.result = result
  }

  func analyze() async throws -> ScreenAnalysis {
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
