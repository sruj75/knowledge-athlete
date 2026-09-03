import XCTest

@testable import Omi_Computer

final class FairUseManagedCloudPresentationTests: XCTestCase {
  func testBlockedPresentationUsesApprovedResetSupportAndCaseCopy() {
    let presentation = FairUseManagedCloudPresentation.blocked(
      resetsAt: "2026-08-22T00:00:00Z", caseRef: "FU-ABC123DEF456")

    XCTAssertEqual(presentation.title, "Managed Transcription Paused")
    XCTAssertEqual(
      presentation.message,
      "Today's 30-minute managed cloud transcription allowance has been used. "
        + "On-device transcription is unavailable on this Mac, so transcription is paused until "
        + "2026-08-22T00:00:00Z. Save your case reference for the support channel when it is published. "
        + "Reference: FU-ABC123DEF456")
    XCTAssertFalse(presentation.message.contains("@"))
  }

  func testBlockedPresentationOmitsReferenceSuffixWhenNoCaseExists() {
    let presentation = FairUseManagedCloudPresentation.blocked(
      resetsAt: "2026-08-22T00:00:00Z", caseRef: "")

    XCTAssertFalse(presentation.message.contains("Reference:"))
  }
}
