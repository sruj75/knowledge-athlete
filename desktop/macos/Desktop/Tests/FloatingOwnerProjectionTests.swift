import XCTest

@testable import Omi_Computer

private actor FloatingOwnerPauseGate {
  private var started = false
  private var released = false

  func pause() async {
    started = true
    while !released { await Task.yield() }
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func release() {
    released = true
  }
}

@MainActor
private final class FloatingOwnerBox {
  var value: String?

  init(_ value: String?) {
    self.value = value
  }
}

@MainActor
private final class FloatingOwnerAuthorizationBox {
  var isCurrent: Bool

  init(_ isCurrent: Bool) {
    self.isCurrent = isCurrent
  }
}

private enum SpawnOutcome: Sendable, Equatable {
  case rejectedBeforeDispatch
  case staleReceipt(String)
  case accepted(String)
}

@MainActor
final class FloatingOwnerProjectionTests: XCTestCase {
  @MainActor
  func testLateNotificationWorkflowCannotPresentOrScheduleJournalForReplacementOwner() async throws {
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    let manager = FloatingControlBarManager.shared
    defer {
      manager.resetOwnerProjection()
    }
    await ownerFixture.establish(authOwnerID: "owner-a")
    let authorizationSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    manager.resetOwnerProjection()
    let baseline = manager.notificationProjectionSnapshot
    let gate = FloatingOwnerPauseGate()

    let workflow = Task { @MainActor in
      await gate.pause()
      return manager.showNotification(
        ownerID: "owner-a",
        authorizationSnapshot: authorizationSnapshot,
        title: "owner A private title",
        message: "owner A private content",
        assistantId: "insight",
        sound: .none)
    }
    await gate.waitUntilStarted()
    await ownerFixture.establish(authOwnerID: "owner-b")
    await gate.release()

    let result = await workflow.value
    XCTAssertEqual(result, .rejectedOwnerChange)
    XCTAssertEqual(manager.notificationProjectionSnapshot, baseline)
    await ownerFixture.restore()
  }

  @MainActor
  func testDelayedTrialPublisherCannotDeliverOrMarkNudgeAfterOwnerSwitch() {
    let defaults = UserDefaults.standard
    let previousOwner = defaults.object(forKey: .authUserId)
    let previousOverride = defaults.object(forKey: .automationOwnerOverride)
    let ownerA = "trial-owner-a"
    let ownerB = "trial-owner-b"
    let service = TrialBannerService()
    defer {
      service.stop()
      TrialBannerService.clearRecordedNudges(ownerID: ownerA)
      TrialBannerService.clearRecordedNudges(ownerID: ownerB)
      restore(previousOwner, key: .authUserId, defaults: defaults)
      restore(previousOverride, key: .automationOwnerOverride, defaults: defaults)
    }
    defaults.removeObject(forKey: .automationOwnerOverride)
    defaults.set(ownerA, forKey: .authUserId)
    TrialBannerService.clearRecordedNudges(ownerID: ownerA)
    TrialBannerService.clearRecordedNudges(ownerID: ownerB)

    let appState = AppState()
    var presentedOwners: [String] = []
    service.start(appState: appState) { ownerID, _, _, _ in
      presentedOwners.append(ownerID)
      return .presented
    }

    defaults.set(ownerB, forKey: .authUserId)
    appState.trialMetadata = TrialMetadataResponse(
      trialStartedAt: 1,
      trialEndsAt: 2,
      trialRemainingSeconds: 0,
      trialExpired: true,
      trialDurationSeconds: 1,
      trialFeatures: [],
      planAfterTrial: "free")

    XCTAssertTrue(presentedOwners.isEmpty)
    XCTAssertFalse(TrialBannerService.hasRecordedNudge(.expired, ownerID: ownerA))
    XCTAssertFalse(TrialBannerService.hasRecordedNudge(.expired, ownerID: ownerB))

    TrialBannerService.recordNudge(.oneHour, ownerID: ownerA)
    XCTAssertTrue(TrialBannerService.hasRecordedNudge(.oneHour, ownerID: ownerA))
    XCTAssertFalse(TrialBannerService.hasRecordedNudge(.oneHour, ownerID: ownerB))
  }

  @MainActor
  func testNotificationAdmissionSuspendedAcrossOwnerSwitchReturnsNoMessage() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "owner-a")
    defer { Task { await fixture.restore() } }
    let authorizationSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let authorization = FloatingOwnerAuthorizationBox(true)
    let gate = FloatingOwnerPauseGate()

    let admission = Task { @MainActor in
      await FloatingControlBarManager.performOwnerBoundNotificationAdmission(
        authorizationSnapshot: authorizationSnapshot,
        isAuthorizationCurrent: { _ in authorization.isCurrent },
        record: {
          await gate.pause()
          return "owner-a-private-notification"
        })
    }
    await gate.waitUntilStarted()
    authorization.isCurrent = false
    await gate.release()

    let admitted = await admission.value
    XCTAssertNil(admitted)
  }

  @MainActor
  func testPillTerminalSuspendedAcrossOwnerSwitchCannotAttachToReplacementOwner() async {
    let owner = FloatingOwnerBox("owner-a")
    let gate = FloatingOwnerPauseGate()

    let terminal = Task { @MainActor in
      await FloatingControlBarManager.performOwnerBoundPillTerminalAdmission(
        ownerID: "owner-a",
        currentOwnerID: { owner.value },
        record: {
          await gate.pause()
          return "owner-a-terminal-turn"
        })
    }
    await gate.waitUntilStarted()
    owner.value = "owner-b"
    await gate.release()

    let admitted = await terminal.value
    XCTAssertNil(admitted)
  }

  @MainActor
  func testSpawnReceiptSuspendedAcrossOwnerSwitchIsRejectedAsStale() async {
    let owner = FloatingOwnerBox("owner-a")
    let gate = FloatingOwnerPauseGate()

    let operation = Task { @MainActor in
      let result = await AgentPillsManager.performOwnerBoundSpawn(
        ownerID: "owner-a",
        currentOwnerID: { owner.value },
        dispatch: {
          await gate.pause()
          return "owner-a-run"
        })
      switch result {
      case .rejectedBeforeDispatch:
        return SpawnOutcome.rejectedBeforeDispatch
      case .staleReceipt(let runID):
        return .staleReceipt(runID)
      case .accepted(let runID):
        return .accepted(runID)
      }
    }
    await gate.waitUntilStarted()
    owner.value = "owner-b"
    await gate.release()

    switch await operation.value {
    case .staleReceipt(let runID):
      XCTAssertEqual(runID, "owner-a-run")
    case .accepted, .rejectedBeforeDispatch:
      XCTFail("owner A's late receipt must not enter owner B's pill projection")
    }
  }

  @MainActor
  func testOwnerTransitionPurgesRenderedPills() {
    let manager = AgentPillsManager.shared
    _ = manager.replaceWithAutomationPills(count: 2)
    XCTAssertEqual(manager.pills.count, 2)

    NotificationCenter.default.post(name: .runtimeOwnerDidChange, object: nil)

    XCTAssertTrue(manager.pills.isEmpty)
  }

  @MainActor
  private func restore(_ value: Any?, key: DefaultsKey, defaults: UserDefaults) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }
}
