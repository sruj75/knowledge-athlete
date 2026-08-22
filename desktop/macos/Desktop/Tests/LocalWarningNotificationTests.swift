import Foundation
import XCTest

@testable import Omi_Computer

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
      deliver: { _, presentation, _ in
        deliveries.append(presentation)
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
      deliver: { _, presentation, _ in
        deliveries.append(presentation)
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
      deliver: { _, _, _ in
        deliveryCount += 1
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
      deliver: { _, _, _ in
        deliveryAttempts += 1
        return deliveryAttempts > 1
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
}
