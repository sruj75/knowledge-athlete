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
      deliver: { _, presentation, _ in deliveries.append(presentation) })
    let receipt = FairUseClassificationReceipt(
      reviewId: "11111111-1111-4111-8111-111111111111",
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-ABC123")

    XCTAssertTrue(presenter.present(receipt, authorization: authorization))
    XCTAssertFalse(presenter.present(receipt, authorization: authorization))
    let relaunchedPresenter = FairUseWarningNotificationPresenter(
      defaults: defaults,
      deliver: { _, presentation, _ in deliveries.append(presentation) })
    XCTAssertFalse(relaunchedPresenter.present(receipt, authorization: authorization))

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
      deliver: { _, _, _ in deliveryCount += 1 })
    let receipt = FairUseClassificationReceipt(
      reviewId: UUID().uuidString,
      accepted: true,
      idempotent: false,
      action: "none",
      stage: "none",
      caseRef: "")

    XCTAssertFalse(presenter.present(receipt, authorization: authorization))
    XCTAssertEqual(deliveryCount, 0)
  }
}
