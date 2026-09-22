import XCTest

@testable import Omi_Computer

final class ConferencingAppsTests: XCTestCase {

  func testNativeCallAppMatchesOnOwnerNameAlone() {
    XCTAssertTrue(ConferencingApps.isCallWindow(ownerName: "zoom.us", title: nil))
    XCTAssertTrue(ConferencingApps.isCallWindow(ownerName: "Microsoft Teams", title: "anything"))
    XCTAssertTrue(ConferencingApps.isCallWindow(ownerName: "FaceTime", title: nil))
    XCTAssertTrue(ConferencingApps.isCallWindow(ownerName: "Webex", title: nil))
  }

  func testBrowserRequiresCallKeywordInTitle() {
    XCTAssertTrue(
      ConferencingApps.isCallWindow(ownerName: "Google Chrome", title: "Google Meet — Standup"))
    XCTAssertTrue(
      ConferencingApps.isCallWindow(ownerName: "Safari", title: "https://meet.google.com/abc-defg"))
    XCTAssertFalse(
      ConferencingApps.isCallWindow(ownerName: "Google Chrome", title: "GitHub - omi"))
    XCTAssertFalse(ConferencingApps.isCallWindow(ownerName: "Google Chrome", title: nil))
  }

  func testNonCallAppAndNilOwnerAreNotCalls() {
    // A non-browser, non-call app is never a call — even if its title mentions a meeting.
    XCTAssertFalse(ConferencingApps.isCallWindow(ownerName: "Finder", title: "Zoom Meeting"))
    XCTAssertFalse(ConferencingApps.isCallWindow(ownerName: nil, title: "Google Meet"))
  }

  // Regression: issue #10143 — Omi's periodic capture stopped an active screen share.
  // These signatures gate the capture pause; a match means "user is presenting now".
  func testShareIndicatorMatchesKnownPresentingWindows() {
    // Zoom floating share controls (internal window names, present only while sharing).
    XCTAssertTrue(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "zoom.us", title: "zoom share statusbar window"))
    XCTAssertTrue(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "zoom.us", title: "zoom share toolbar window"))
    // Teams presenting toolbar.
    XCTAssertTrue(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "Microsoft Teams", title: "Screen sharing toolbar"))
    XCTAssertTrue(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "MSTeams", title: "Screen sharing toolbar"))
    // Browser (Meet / Teams web) stop-sharing bubble.
    XCTAssertTrue(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "Google Chrome", title: "meet.google.com is sharing your screen."))
    XCTAssertTrue(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "Arc", title: "teams.microsoft.com is sharing a window."))
  }

  func testShareIndicatorIgnoresOrdinaryCallAndAppWindows() {
    // In a Zoom call but NOT sharing: main meeting window must not pause capture.
    XCTAssertFalse(
      ConferencingApps.isShareIndicatorWindow(ownerName: "zoom.us", title: "Zoom Meeting"))
    XCTAssertFalse(
      ConferencingApps.isShareIndicatorWindow(ownerName: "Microsoft Teams", title: "Standup | Microsoft Teams"))
    // A Teams chat about screen sharing is not the presenting toolbar.
    XCTAssertFalse(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "Microsoft Teams", title: "Screen sharing issues | Microsoft Teams"))
    // Ordinary browser tab, even one talking about screen sharing.
    XCTAssertFalse(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "Google Chrome", title: "How to stop sharing your screen - Google Meet Help"))
    // Non-conferencing app can never be a share indicator, whatever the title says.
    XCTAssertFalse(
      ConferencingApps.isShareIndicatorWindow(
        ownerName: "Finder", title: "zoom share statusbar window"))
    XCTAssertFalse(ConferencingApps.isShareIndicatorWindow(ownerName: "zoom.us", title: nil))
    XCTAssertFalse(ConferencingApps.isShareIndicatorWindow(ownerName: nil, title: "zoom share"))
    XCTAssertFalse(ConferencingApps.isShareIndicatorWindow(ownerName: "zoom.us", title: ""))
  }

  func testBrowserBundleIDPrefixMatchingCatchesHelpers() {
    // Browsers route call audio through helper processes — match by prefix.
    XCTAssertTrue(ConferencingApps.isBrowserBundleID("net.imput.helium.helper"))  // Helium (Meet)
    XCTAssertTrue(ConferencingApps.isBrowserBundleID("com.google.Chrome.helper"))
    XCTAssertTrue(ConferencingApps.isBrowserBundleID("company.thebrowser.Browser"))  // Arc
    XCTAssertTrue(ConferencingApps.isBrowserBundleID("com.apple.WebKit.GPU"))
    // Not browsers.
    XCTAssertFalse(ConferencingApps.isBrowserBundleID("com.omi.omi-mtg-sysaudio"))
    XCTAssertFalse(ConferencingApps.isBrowserBundleID("us.zoom.xos"))
  }
}
