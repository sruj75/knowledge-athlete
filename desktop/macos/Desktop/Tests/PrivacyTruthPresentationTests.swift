import XCTest

@testable import Omi_Computer

final class PrivacyTruthPresentationTests: XCTestCase {
  func testLocalDataCopySeparatesDurableLocalStateFromManagedProcessing() {
    XCTAssertEqual(PrivacyTruthPresentation.dataLocationTitle, "Local data on this Mac")
    XCTAssertTrue(PrivacyTruthPresentation.dataLocationDetail.contains("saved in local app storage on this Mac"))
    XCTAssertTrue(PrivacyTruthPresentation.dataLocationDetail.contains("managed providers for processing"))
  }

  func testTrackingCopyNamesTheActualBoundaryWithoutAbsolutes() {
    XCTAssertEqual(PrivacyTruthPresentation.analyticsControlTitle, "Share product analytics")
    XCTAssertTrue(PrivacyTruthPresentation.analyticsControlDetail.contains("PostHog"))
    XCTAssertTrue(PrivacyTruthPresentation.analyticsControlDetail.contains("Sentry"))
    XCTAssertTrue(PrivacyTruthPresentation.analyticsControlDetail.contains("Enhanced Diagnostics"))
    XCTAssertTrue(
      PrivacyTruthPresentation.trackingCategories.contains("App lifecycle, release, update, and feature use"))
    XCTAssertTrue(PrivacyTruthPresentation.trackingBoundary.contains("account ID, email address, and display name"))
    XCTAssertTrue(PrivacyTruthPresentation.trackingBoundary.contains("app names or record identifiers"))
    XCTAssertTrue(PrivacyTruthPresentation.trackingBoundary.contains("does not include transcript text"))

    let copy = PrivacyTruthPresentation.allText.joined(separator: " ")
    XCTAssertFalse(copy.contains("Active"))
    XCTAssertFalse(copy.contains("Privacy Guarantees"))
    XCTAssertFalse(copy.contains("only yours"))
    XCTAssertFalse(copy.contains("never sold"))
  }

  func testManagedProviderInventoryMatchesTheApprovedRetainedPortfolio() {
    XCTAssertEqual(
      PrivacyTruthPresentation.managedServices.map(\.name),
      ["Firebase", "Google Gemini", "Modulate", "OpenAI", "Langfuse", "PostHog", "Sentry"])
    XCTAssertEqual(
      PrivacyTruthPresentation.managedServices.first(where: { $0.name == "OpenAI" })?.purpose,
      "Text-to-speech only")
    XCTAssertEqual(
      PrivacyTruthPresentation.billingStatus,
      "Billing is disabled. Dodo Payments is not called by the current product.")
  }
}
