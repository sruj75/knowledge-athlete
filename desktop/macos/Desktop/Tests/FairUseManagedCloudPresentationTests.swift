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
        + "2026-08-22T00:00:00Z. Contact support@heyintentive.com to discuss your usage. "
        + "Quote your case reference when contacting support. Reference: FU-ABC123DEF456")
  }

  func testBlockedPresentationOmitsReferenceSuffixWhenNoCaseExists() {
    let presentation = FairUseManagedCloudPresentation.blocked(
      resetsAt: "2026-08-22T00:00:00Z", caseRef: "")

    XCTAssertFalse(presentation.message.contains("Reference:"))
  }
}
