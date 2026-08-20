import XCTest

@testable import Omi_Computer

/// Regression guard for cross-account data leaks: the surviving local task and
/// goal stores each cache a per-user `DatabasePool`
/// and expose `invalidateCache()`, but the sign-out flow only invalidated the
/// other per-user storages. The next signed-in user therefore read/wrote the
/// previous account's tasks and goals until relaunch.
///
/// The invalidation list now lives at the effective-owner transition boundary,
/// so it also covers automation and account switches rather than sign-out only.
final class SignOutStorageInvalidationTests: XCTestCase {

  func testSignOutInvalidatesAllPerUserTaskStorages() throws {
    // omi-test-quality: source-inspection -- static contract: sign-out must invalidate every per-user DatabasePool cache so a new user never reads the previous account's data
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Chat/RuntimeOwnerIdentity.swift"),
      encoding: .utf8
    )

    for storage in [
      "ActionItemStorage.shared.invalidateCache()",
      "GoalStorage.shared.invalidateCache()",
    ] {
      XCTAssertTrue(
        source.contains(storage),
        "sign-out must invalidate \(storage) or the next user reads the previous account's data")
    }
  }
}
