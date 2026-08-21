import Foundation
import XCTest

@testable import Omi_Computer

@MainActor
final class FocusAssistantOwnerFenceTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?
  private var savedEnabled = false
  private var savedNotifications = false

  override func setUp() async throws {
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    self.ownerFixture = ownerFixture
    await ownerFixture.establish(authOwnerID: "focus-owner")
    savedEnabled = FocusAssistantSettings.shared.isEnabled
    savedNotifications = FocusAssistantSettings.shared.notificationsEnabled
    FocusAssistantSettings.shared.isEnabled = true
    FocusAssistantSettings.shared.notificationsEnabled = true
  }

  override func tearDown() async throws {
    FocusAssistantSettings.shared.isEnabled = savedEnabled
    FocusAssistantSettings.shared.notificationsEnabled = savedNotifications
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
  }

  func testSameUIDReauthenticationDropsSuspendedAnalysisBeforePersistenceOrPublication() async throws {
    let ownerFixture = try XCTUnwrap(ownerFixture)
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
      onAlert: { _, _ in recorder.append("alert") },
      onStatusChange: { _, _ in recorder.append("status") },
      onDistraction: { _ in recorder.append("distraction") })
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    let processing = Task {
      await assistant.processFrame(
        CapturedFrame(
          jpegData: Data([0xFF, 0xD8, 0xFF]),
          appName: "Safari",
          frameNumber: 1),
        authorizationSnapshot: authorizationSnapshot)
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

  func testHistoryRunnerRejectsSuspendedSameUIDResultBeforeAppending() async throws {
    let ownerFixture = try XCTUnwrap(ownerFixture)
    let gate = FocusAnalysisGate(result: distractedAnalysis)
    let assistant = FocusAssistant(
      analysisOverride: { _, _ in try await gate.analyze() },
      focusSessionPersister: { record, _ in record })

    let analysis = Task {
      try await assistant.testAnalyzeWithHistory(
        jpegData: Data([0xFF, 0xD8, 0xFF]),
        appName: "Safari")
    }
    await gate.waitUntilEntered()
    await ownerFixture.establish(authOwnerID: nil)
    await ownerFixture.establish(authOwnerID: "focus-owner")
    await gate.release()

    do {
      _ = try await analysis.value
      XCTFail("a previous owner generation must not append to test history")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    let historyCount = await assistant.testAnalysisHistoryCountForTests
    XCTAssertEqual(historyCount, 0)
  }

  func testPersistenceFailurePublishesNoFocusStateOrCallbacks() async throws {
    let recorder = FocusEventRecorder()
    let analysis = ScreenAnalysis(
      status: .distracted,
      appOrSite: "Safari",
      description: "Browsing unrelated content",
      message: nil)
    let assistant = FocusAssistant(
      analysisOverride: { _, _ in analysis },
      focusSessionPersister: { _, _ in
        recorder.append("persist_attempt")
        throw FocusPersistenceFixtureError.failed
      },
      onAlert: { _, _ in recorder.append("alert") },
      onStatusChange: { _, _ in recorder.append("status") },
      onDistraction: { _ in recorder.append("distraction") })
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    await assistant.processFrame(
      CapturedFrame(
        jpegData: Data([0xFF, 0xD8, 0xFF]),
        appName: "Safari",
        frameNumber: 2),
      authorizationSnapshot: authorizationSnapshot)

    XCTAssertEqual(recorder.values, ["persist_attempt"])
    let historyCount = await assistant.analysisHistoryCount
    XCTAssertEqual(historyCount, 0)
  }

  func testParallelTransitionsSerializePersistenceAndPublication() async throws {
    let recorder = FocusEventRecorder()
    let persistenceGate = FocusPersistenceGate()
    let analysis = ScreenAnalysis(
      status: .distracted,
      appOrSite: "Safari",
      description: "Browsing unrelated content",
      message: nil)
    let assistant = FocusAssistant(
      analysisOverride: { _, _ in analysis },
      focusSessionPersister: { record, _ in
        try await persistenceGate.persist(record)
      },
      onAlert: { _, _ in recorder.append("alert") },
      onStatusChange: { _, _ in recorder.append("status") },
      onDistraction: { _ in recorder.append("distraction") })
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    let first = Task {
      await assistant.processFrame(
        CapturedFrame(
          jpegData: Data([0x01]),
          appName: "Safari",
          frameNumber: 1),
        authorizationSnapshot: authorizationSnapshot)
    }
    await persistenceGate.waitUntilFirstEntered()

    let second = Task {
      await assistant.processFrame(
        CapturedFrame(
          jpegData: Data([0x02]),
          appName: "Safari",
          frameNumber: 2),
        authorizationSnapshot: authorizationSnapshot)
    }
    await assistant.waitUntilCommitTurnQueuedForTests()
    let callsBeforeRelease = await persistenceGate.callCount
    XCTAssertEqual(callsBeforeRelease, 1)

    await persistenceGate.releaseFirst()
    await first.value
    await second.value

    let persistenceCalls = await persistenceGate.callCount
    XCTAssertEqual(persistenceCalls, 1)
    XCTAssertEqual(recorder.values.filter { $0 == "distraction" }.count, 1)
    XCTAssertEqual(recorder.values.filter { $0 == "alert" }.count, 0)
    XCTAssertEqual(recorder.values.filter { $0 == "status" }.count, 2)
    let historyCount = await assistant.analysisHistoryCount
    XCTAssertEqual(historyCount, 2)
    let lastFrame = await assistant.lastProcessedFrameNumberForTests
    XCTAssertEqual(lastFrame, 2)
  }

  func testBufferedFrameKeepsCaptureGenerationAcrossOwnerReset() async throws {
    let ownerFixture = try XCTUnwrap(ownerFixture)
    let recorder = FocusFrameRecorder()
    let assistant = FocusAssistant(
      analysisOverride: { jpegData, _ in
        await recorder.record(jpegData)
        return nil
      },
      focusSessionPersister: { record, _ in record })
    let originalSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    _ = await assistant.analyze(
      frame: CapturedFrame(
        jpegData: Data([0x0A]),
        appName: "Safari",
        frameNumber: 1),
      authorizationSnapshot: originalSnapshot)

    await ownerFixture.establish(authOwnerID: nil)
    await ownerFixture.establish(authOwnerID: "focus-owner")
    await assistant.resetForOwnerChange()
    let replacementSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    _ = await assistant.analyze(
      frame: CapturedFrame(
        jpegData: Data([0x0B]),
        appName: "Notes",
        frameNumber: 2),
      authorizationSnapshot: replacementSnapshot)

    await assistant.startProcessingForTests()
    await recorder.waitForFirstFrame()
    let processedBytes = await recorder.firstBytes
    XCTAssertEqual(processedBytes, [0x0B])
    await assistant.stop()
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

private actor FocusPersistenceGate {
  private var calls = 0
  private var firstEntered = false
  private var released = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  var callCount: Int { calls }

  func persist(_ record: FocusSessionRecord) async throws -> FocusSessionRecord {
    calls += 1
    if calls == 1 {
      firstEntered = true
      let waiters = enteredWaiters
      enteredWaiters.removeAll()
      waiters.forEach { $0.resume() }
      if !released {
        await withCheckedContinuation { releaseWaiters.append($0) }
      }
    }
    var inserted = record
    inserted.id = Int64(calls)
    return inserted
  }

  func waitUntilFirstEntered() async {
    if firstEntered { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func releaseFirst() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
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

private actor FocusFrameRecorder {
  private var bytes: [UInt8] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  var firstBytes: [UInt8] { bytes }

  func record(_ data: Data) {
    bytes.append(data.first ?? 0)
    let continuations = waiters
    waiters.removeAll()
    continuations.forEach { $0.resume() }
  }

  func waitForFirstFrame() async {
    if !bytes.isEmpty { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}
