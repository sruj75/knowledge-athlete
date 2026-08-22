import Foundation
import XCTest

@testable import Omi_Computer

private actor WarningDeliverySuspension {
  private var started = false
  private var allowed = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var deliveryWaiters: [CheckedContinuation<Void, Never>] = []

  func deliver() async -> Bool {
    started = true
    let pendingStarts = startWaiters
    startWaiters.removeAll()
    pendingStarts.forEach { $0.resume() }
    if !allowed {
      await withCheckedContinuation { continuation in
        deliveryWaiters.append(continuation)
      }
    }
    return true
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func allowDelivery() {
    guard !allowed else { return }
    allowed = true
    let pendingDeliveries = deliveryWaiters
    deliveryWaiters.removeAll()
    pendingDeliveries.forEach { $0.resume() }
  }
}

@MainActor
final class LocalWarningNotificationTests: XCTestCase {
  func testWarningUsesFixedCopyAndPersistsOwnerScopedDeduplication() async throws {
    let suite = "LocalWarningNotificationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var deliveries: [FairUseWarningPresentation] = []
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, presentation, _, _, _, _, commitInApp, commitSystem in
        deliveries.append(presentation)
        commitInApp()
        commitSystem()
        return true
      })
    let receipt = FairUseClassificationReceipt(
      reviewId: "11111111-1111-4111-8111-111111111111",
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-ABC123")

    let firstPresented = await presenter.present(receipt, authorization: authorization)
    let duplicatePresented = await presenter.present(receipt, authorization: authorization)
    XCTAssertTrue(firstPresented)
    XCTAssertFalse(duplicatePresented)
    let relaunchedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, presentation, _, _, _, _, commitInApp, commitSystem in
        deliveries.append(presentation)
        commitInApp()
        commitSystem()
        return true
      })
    let relaunchedDuplicatePresented = await relaunchedPresenter.present(
      receipt, authorization: authorization)
    XCTAssertFalse(relaunchedDuplicatePresented)

    XCTAssertEqual(deliveries.count, 1)
    XCTAssertEqual(deliveries[0].title, "Fair Use Notice")
    XCTAssertTrue(deliveries[0].message.contains("FU-ABC123"))
  }

  func testUnknownActionAndStaleOwnerNeverPresent() async throws {
    let suite = "LocalWarningNotificationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var deliveryCount = 0
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      isAuthorizationCurrent: { _ in false },
      deliver: { _, _, _, _, _, _, commitInApp, commitSystem in
        deliveryCount += 1
        commitInApp()
        commitSystem()
        return true
      })
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "none",
      stage: "none",
      caseRef: "")

    let presented = await presenter.present(receipt, authorization: authorization)
    XCTAssertFalse(presented)
    XCTAssertEqual(deliveryCount, 0)
  }

  func testDeniedSystemDeliveryReplaysAfterRelaunchWithoutDuplicatingInAppWarning() async throws {
    let suite = "LocalWarningNotificationRetryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var inAppFlags: [Bool] = []
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, _, commitInApp, _ in
        inAppFlags.append(deliverInApp)
        XCTAssertTrue(deliverSystem)
        if deliverInApp { commitInApp() }
        return false
      })
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-RETRY")

    let rejected = await presenter.present(receipt, authorization: authorization)
    let relaunchedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, _, commitInApp, commitSystem in
        inAppFlags.append(deliverInApp)
        XCTAssertTrue(deliverSystem)
        if deliverInApp { commitInApp() }
        commitSystem()
        return true
      })
    let replayed = await relaunchedPresenter.replayPending(authorization: authorization)
    let duplicate = await relaunchedPresenter.present(receipt, authorization: authorization)
    XCTAssertFalse(rejected)
    XCTAssertEqual(replayed, 1)
    XCTAssertFalse(duplicate)
    XCTAssertEqual(inAppFlags, [true, false])
  }

  func testUnavailableInAppSurfaceReplaysWithoutDuplicatingDeliveredSystemBanner() async throws {
    let suite = "LocalWarningNotificationInAppRetryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-IN-APP-RETRY")
    var deliveryFlags: [(Bool, Bool)] = []
    let unavailablePresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, _, _, commitSystem in
        deliveryFlags.append((deliverInApp, deliverSystem))
        commitSystem()
        return true
      })

    let incomplete = await unavailablePresenter.present(receipt, authorization: authorization)
    let relaunchedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, _, commitInApp, _ in
        deliveryFlags.append((deliverInApp, deliverSystem))
        commitInApp()
        return true
      })
    let replayed = await relaunchedPresenter.replayPending(authorization: authorization)
    let duplicate = await relaunchedPresenter.present(receipt, authorization: authorization)

    XCTAssertFalse(incomplete)
    XCTAssertEqual(replayed, 1)
    XCTAssertFalse(duplicate)
    XCTAssertEqual(deliveryFlags.map(\.0), [true, true])
    XCTAssertEqual(deliveryFlags.map(\.1), [true, false])
  }

  func testQueuedInAppSurfaceSurvivesRelaunchWithoutDuplicateQueueAdmission() async throws {
    let suite = "LocalWarningNotificationQueuedRetryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-QUEUED-RETRY")
    var deliveryFlags: [(Bool, Bool)] = []
    let queuedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, queueInApp, _, commitSystem in
        deliveryFlags.append((deliverInApp, deliverSystem))
        if deliverInApp { queueInApp() }
        if deliverSystem { commitSystem() }
        return true
      })

    let incomplete = await queuedPresenter.present(receipt, authorization: authorization)
    let sameProcessReplay = await queuedPresenter.replayPending(authorization: authorization)
    let relaunchedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, _, commitInApp, _ in
        deliveryFlags.append((deliverInApp, deliverSystem))
        if deliverInApp { commitInApp() }
        return true
      })
    let relaunchedReplay = await relaunchedPresenter.replayPending(authorization: authorization)

    XCTAssertFalse(incomplete)
    XCTAssertEqual(sameProcessReplay, 0)
    XCTAssertEqual(relaunchedReplay, 1)
    XCTAssertEqual(deliveryFlags.map(\.0), [true, true])
    XCTAssertEqual(deliveryFlags.map(\.1), [true, false])
  }

  func testQueuedInAppSurfaceIsReplayableAfterOwnerGenerationChange() async throws {
    let suite = "LocalWarningNotificationQueuedOwnerTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let firstAuthorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-QUEUED-OWNER")
    var deliveryFlags: [(Bool, Bool)] = []
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, queueInApp, commitInApp, commitSystem in
        deliveryFlags.append((deliverInApp, deliverSystem))
        if deliveryFlags.count == 1 {
          queueInApp()
          commitSystem()
        } else {
          commitInApp()
        }
        return true
      })

    let incomplete = await presenter.present(receipt, authorization: firstAuthorization)
    await fixture.establish(authOwnerID: "warning-owner-b")
    await fixture.establish(authOwnerID: "warning-owner-a")
    let replacementAuthorization = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let replayed = await presenter.replayPending(authorization: replacementAuthorization)

    XCTAssertFalse(incomplete)
    XCTAssertEqual(replayed, 1)
    XCTAssertEqual(deliveryFlags.map(\.0), [true, true])
    XCTAssertEqual(deliveryFlags.map(\.1), [true, false])
  }

  func testConcurrentReplayAttemptsAdmitOnlyOnePhysicalDelivery() async throws {
    let suite = "LocalWarningNotificationConcurrentReplayTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-CONCURRENT-REPLAY")
    let suspension = WarningDeliverySuspension()
    var deliveryAttempts = 0
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, _, _, _, commitInApp, commitSystem in
        deliveryAttempts += 1
        _ = await suspension.deliver()
        commitInApp()
        commitSystem()
        return true
      })

    let firstAttempt = Task { @MainActor in
      await presenter.accept(receipt, authorization: authorization)
    }
    await suspension.waitUntilStarted()
    let overlappingReplay = Task { @MainActor in
      await presenter.replayPending(authorization: authorization)
    }

    let overlappingReplayCount = await overlappingReplay.value
    XCTAssertEqual(overlappingReplayCount, 0)
    await suspension.allowDelivery()
    let accepted = await firstAttempt.value
    XCTAssertTrue(accepted)
    XCTAssertEqual(deliveryAttempts, 1)
  }

  func testSnoozedAttemptSurvivesRestartAndPresentsBothSurfaces() async throws {
    let suite = "LocalWarningNotificationSnoozeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-SNOOZE")
    let snoozedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, _, _, _, _, _ in false })

    let acceptedForReplay = await snoozedPresenter.accept(
      receipt, authorization: authorization)
    var replayedInApp = false
    let relaunchedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, deliverInApp, deliverSystem, _, commitInApp, commitSystem in
        replayedInApp = deliverInApp
        XCTAssertTrue(deliverSystem)
        commitInApp()
        commitSystem()
        return true
      })
    let replayed = await relaunchedPresenter.replayPending(authorization: authorization)

    XCTAssertTrue(acceptedForReplay)
    XCTAssertEqual(replayed, 1)
    XCTAssertTrue(replayedInApp)
  }

  func testOwnerTransitionWaitsForNotificationDeliveryAndDedupCommit() async throws {
    let suite = "LocalWarningNotificationOwnerFenceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let suspension = WarningDeliverySuspension()
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, authorization, _, _, _, commitInApp, commitSystem in
        let mutationAuthorization = LocalMutationAuthorization {
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
        }
        do {
          return try await mutationAuthorization.withCommitLease { @MainActor in
            try mutationAuthorization.require()
            let delivered = await suspension.deliver()
            try mutationAuthorization.require()
            if delivered {
              commitInApp()
              commitSystem()
            }
            return delivered
          }
        } catch {
          return false
        }
      })
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-OWNER-FENCE")

    let presentation = Task { @MainActor in
      await presenter.present(receipt, authorization: authorization)
    }
    await suspension.waitUntilStarted()
    let transition = Task { @MainActor in
      await fixture.establish(authOwnerID: "warning-owner-b")
    }
    await EffectiveOwnerTransitionFence.shared.waitUntilTransitionIsPending()

    XCTAssertEqual(RuntimeOwnerIdentity.currentOwnerId(), "warning-owner-a")
    await suspension.allowDelivery()
    let presented = await presentation.value
    XCTAssertTrue(presented)
    await transition.value
    XCTAssertEqual(RuntimeOwnerIdentity.currentOwnerId(), "warning-owner-b")
  }
}
