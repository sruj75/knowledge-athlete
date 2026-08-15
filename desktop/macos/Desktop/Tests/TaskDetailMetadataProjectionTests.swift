import XCTest

@testable import Omi_Computer

final class TaskDetailMetadataProjectionTests: XCTestCase {
  func testBridgeOnlyMetadataIsHiddenWhileGenericTaskMetadataRemains() {
    let entries = TaskDetailMetadataProjection.entries(
      from: [
        "sentry_issue_id": "issue-42",
        "sentry_issue_url": "https://example.invalid/issues/42",
        "sentry_short_id": "APP-42",
        "reporter_name": "Reporter",
        "reporter_email": "reporter@example.invalid",
        "feedback_type": "bug",
        "app_version": "1.2.3",
        "app_build": "123",
        "os": "macOS",
        "device_model": "Mac",
        "project": "Launch",
        "estimate": 3,
        "owners": ["Ada", "Lin"],
      ],
      excluding: []
    )

    XCTAssertEqual(entries.map(\.key), ["estimate", "owners", "project"])
    XCTAssertEqual(entries.map(\.value), ["3", "Ada, Lin", "Launch"])
  }
}
