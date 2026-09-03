import XCTest

@testable import Omi_Computer

@MainActor
final class OmiAppWindowTitleTests: XCTestCase {
  func testNamedBuildIncludesVersion() {
    XCTAssertEqual(
      OMIApp.windowTitle(
        displayName: "Intentive Beta",
        version: "0.12.73",
        launchMode: .full,
        isNonProduction: true),
      "Intentive Beta v0.12.73")
  }

  func testNamedRewindBuildIncludesVersion() {
    XCTAssertEqual(
      OMIApp.windowTitle(
        displayName: "Intentive Dev",
        version: "0.12.73",
        launchMode: .rewind,
        isNonProduction: true),
      "Intentive Dev Rewind v0.12.73")
  }

  func testEmptyVersionFallsBackToName() {
    XCTAssertEqual(
      OMIApp.windowTitle(
        displayName: "Intentive Beta",
        version: "",
        launchMode: .full,
        isNonProduction: true),
      "Intentive Beta")
  }

  func testProductionTitleRemainsUnchanged() {
    XCTAssertEqual(
      OMIApp.windowTitle(
        displayName: "ignored",
        version: "0.12.70",
        launchMode: .full,
        isNonProduction: false),
      "Intentive v0.12.70")
  }

  func testProductionRewindTitleUsesIntentiveIdentity() {
    XCTAssertEqual(
      OMIApp.windowTitle(
        displayName: "ignored",
        version: "0.12.70",
        launchMode: .rewind,
        isNonProduction: false),
      "Intentive Rewind v0.12.70")
  }

  func testNamedBundleTitleIsRecognizedByMainWindowBehaviors() {
    XCTAssertTrue(OMIApp.isMainAppWindowTitle("omi-wave6-s30 v0.12.73"))
  }
}
