import XCTest

@testable import Omi_Computer

@MainActor
final class ExplicitSignOutActionTests: XCTestCase {
  func testActionDelegatesAllCleanupToTheSharedSignOutBoundary() async {
    var events: [String] = []
    let action = ExplicitSignOutAction(
      signOut: { events.append("sign_out") })

    await action.perform().value

    XCTAssertEqual(events, ["sign_out"])
  }
}
