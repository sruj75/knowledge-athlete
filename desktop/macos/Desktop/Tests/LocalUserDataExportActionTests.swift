import Foundation
import XCTest

@testable import Omi_Computer

@MainActor
final class LocalUserDataExportActionTests: XCTestCase {
  func testCancelDoesNotStartExport() async throws {
    var exportCount = 0
    let action = LocalUserDataExportAction(
      chooseDestination: { nil },
      performExport: { _, _ in exportCount += 1 })

    let outcome = try await action.perform(ownerID: "owner")

    XCTAssertEqual(outcome, .cancelled)
    XCTAssertEqual(exportCount, 0)
  }

  func testSelectedDestinationRunsLocalExportAndReportsSavedURL() async throws {
    let destination = URL(fileURLWithPath: "/tmp/omi-data-export.json")
    var receivedOwner: String?
    var receivedDestination: URL?
    let action = LocalUserDataExportAction(
      chooseDestination: { destination },
      performExport: { ownerID, url in
        receivedOwner = ownerID
        receivedDestination = url
      })

    let outcome = try await action.perform(ownerID: "owner")

    XCTAssertEqual(outcome, .saved(destination))
    XCTAssertEqual(receivedOwner, "owner")
    XCTAssertEqual(receivedDestination, destination)
  }

  func testDefaultFilenameIsStableAndJson() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    XCTAssertTrue(LocalUserDataExportAction.defaultFilename(now: date).hasSuffix(".json"))
    XCTAssertTrue(LocalUserDataExportAction.defaultFilename(now: date).hasPrefix("intentive-data-export-"))
  }
}
