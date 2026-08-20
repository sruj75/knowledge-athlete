import XCTest

@testable import Omi_Computer

/// Regression coverage for the local Focus identity boundary.
final class FocusStorageSessionIdTests: XCTestCase {
  func testStoredSessionUsesTheCommittedLocalRowID() {
    let session = StoredFocusSession(
      id: String(Int64(42)),
      status: .focused,
      appOrSite: "Xcode",
      description: "Local identity"
    )
    XCTAssertEqual(session.id, "42")
    XCTAssertEqual(Int64(session.id), 42)
  }
}
