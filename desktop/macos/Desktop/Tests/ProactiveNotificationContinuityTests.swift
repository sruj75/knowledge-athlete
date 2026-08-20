import XCTest

@testable import Omi_Computer

@MainActor
final class ProactiveNotificationContinuityTests: XCTestCase {
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func tearDown() async throws {
    await ownerFixture.restore()
  }

  func testCurrentOwnerNotificationIsAdmittedOnceWithCanonicalOrigin() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let authorizationSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var journalAdmissionCount = 0

    let admitted = await FloatingControlBarManager.performOwnerBoundNotificationAdmission(
      authorizationSnapshot: authorizationSnapshot
    ) {
      journalAdmissionCount += 1
      return "journal-assistant-turn"
    }

    XCTAssertEqual(admitted, "journal-assistant-turn")
    XCTAssertEqual(journalAdmissionCount, 1)
    XCTAssertEqual(ProactiveNotificationContinuityPolicy.journalOrigin, "proactive_notification")
  }

  func testClickOpensOnlyCurrentOwnerLocalChatContext() {
    XCTAssertEqual(
      ProactiveNotificationContinuityPolicy.effect(
        for: .click,
        notificationOwnerID: "owner-a",
        currentOwnerID: "owner-a"
      ),
      .openLocalChat
    )
    XCTAssertEqual(
      ProactiveNotificationContinuityPolicy.effect(
        for: .click,
        notificationOwnerID: "owner-a",
        currentOwnerID: "owner-b"
      ),
      .rejectOwnerChange
    )
  }

  func testDismissAndTimeoutArePresentationOnly() {
    for interaction in [ProactiveNotificationInteraction.dismiss, .timeout] {
      XCTAssertEqual(
        ProactiveNotificationContinuityPolicy.effect(
          for: interaction,
          notificationOwnerID: "owner-a",
          currentOwnerID: "owner-a"
        ),
        .presentationOnly,
        "dismissal and timeout must not read, dismiss, or delete the Insight"
      )
    }
  }

  func testOwnerSwitchDuringJournalAdmissionRejectsResult() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let authorizationSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let authorization = MutableNotificationAuthorization(true)

    let admitted = await FloatingControlBarManager.performOwnerBoundNotificationAdmission(
      authorizationSnapshot: authorizationSnapshot,
      isAuthorizationCurrent: { _ in authorization.isCurrent }
    ) {
      authorization.isCurrent = false
      return "owner-a-private-notification"
    }

    XCTAssertNil(admitted)
  }

  func testSameUIDReauthenticationRejectsOldJournalAdmissionBeforeWrite() async throws {
    await ownerFixture.establish(authOwnerID: "owner-a")
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await ownerFixture.establish(authOwnerID: "owner-a")
    var journalAdmissionCount = 0

    let admitted = await FloatingControlBarManager.performOwnerBoundNotificationAdmission(
      authorizationSnapshot: staleSnapshot
    ) {
      journalAdmissionCount += 1
      return "stale-owner-private-notification"
    }

    XCTAssertNil(admitted)
    XCTAssertEqual(journalAdmissionCount, 0)
  }

  func testImmediateClickWaitsForPendingJournalAdmission() async {
    let waiters = NotificationJournalAdmissionWaiters<String>()
    let click = Task { @MainActor in
      await waiters.wait(for: "notification-1", isAdmitted: false, isPending: true)
    }

    await Task.yield()
    waiters.resolve("notification-1", admitted: true)

    let admitted = await click.value
    XCTAssertTrue(admitted)
  }

  func testOwnerResetRejectsImmediateClickWaiter() async {
    let waiters = NotificationJournalAdmissionWaiters<String>()
    let click = Task { @MainActor in
      await waiters.wait(for: "notification-1", isAdmitted: false, isPending: true)
    }

    await Task.yield()
    waiters.cancelAll()

    let admitted = await click.value
    XCTAssertFalse(admitted)
  }
}

@MainActor
private final class MutableNotificationAuthorization {
  var isCurrent: Bool

  init(_ isCurrent: Bool) {
    self.isCurrent = isCurrent
  }
}
