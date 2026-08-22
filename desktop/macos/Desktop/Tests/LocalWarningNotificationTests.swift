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
      deliver: { _, presentation, _, commit in
        deliveries.append(presentation)
        commit()
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
      deliver: { _, presentation, _, commit in
        deliveries.append(presentation)
        commit()
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
      deliver: { _, _, _, commit in
        deliveryCount += 1
        commit()
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

  func testRejectedDeliveryIsRetriedAndOnlyAcceptedDeliveryIsDeduplicated() async throws {
    let suite = "LocalWarningNotificationRetryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "warning-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let authorization = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var deliveryAttempts = 0
    let presenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, _, _, commit in
        deliveryAttempts += 1
        let delivered = deliveryAttempts > 1
        if delivered { commit() }
        return delivered
      })
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-RETRY")

    let rejected = await presenter.present(receipt, authorization: authorization)
    let accepted = await presenter.present(receipt, authorization: authorization)
    let duplicate = await presenter.present(receipt, authorization: authorization)
    XCTAssertFalse(rejected)
    XCTAssertTrue(accepted)
    XCTAssertFalse(duplicate)
    XCTAssertEqual(deliveryAttempts, 2)
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
      deliver: { _, _, authorization, commit in
        let mutationAuthorization = LocalMutationAuthorization {
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorization)
        }
        do {
          return try await mutationAuthorization.withCommitLease { @MainActor in
            try mutationAuthorization.require()
            let delivered = await suspension.deliver()
            try mutationAuthorization.require()
            if delivered { commit() }
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
