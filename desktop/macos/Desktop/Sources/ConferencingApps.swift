import CoreGraphics
import Foundation

/// Shared catalog of conferencing / video-call apps plus the logic for deciding whether a
/// window (or the whole screen) indicates an active call ("meeting").
///
/// Used by proactive assistants to throttle screen capture during calls and pause while sharing.
enum ConferencingApps {

  /// Apps whose primary purpose is video/audio calls. Matched by app/owner name, which is
  /// available from `NSRunningApplication` and `CGWindowList` **without** Screen Recording
  /// permission.
  static let nativeCallApps: Set<String> = [
    "Microsoft Teams",
    "zoom.us",
    "FaceTime",
    "Webex",
    "Cisco Webex Meetings",
    "GoTo Meeting",
    "GoToMeeting",
  ]

  /// Browser app names. Browser-based calls are matched by window title.
  static let browserApps: Set<String> = [
    "Google Chrome",
    "Arc",
    "Safari",
    "Firefox",
    "Microsoft Edge",
    "Brave Browser",
    "Opera",
  ]

  /// Window-title keywords that indicate a browser-based call.
  static let browserCallKeywords: [String] = [
    "Google Meet",
    "meet.google.com",
    "Teams - Microsoft",  // Teams web app
  ]

  /// Bundle-ID prefixes (lowercased) of browsers and their helper processes, used by
  /// proactive assistant orchestration to recognize browser activity.
  static let browserBundleIDPrefixes: [String] = [
    "com.google.chrome",
    "company.thebrowser",  // Arc
    "net.imput.helium",  // Helium
    "org.mozilla.firefox",
    "com.microsoft.edgemac",
    "com.brave.browser",
    "com.operasoftware.opera",
    "com.vivaldi.vivaldi",
    "com.apple.safari",
    "com.apple.webkit.gpu",  // Safari / WebKit media process
  ]

  /// Whether a bundle ID belongs to a web browser (or one of its helpers), by prefix match.
  static func isBrowserBundleID(_ bundleID: String) -> Bool {
    let lower = bundleID.lowercased()
    return browserBundleIDPrefixes.contains { lower.hasPrefix($0) }
  }

  /// True if a single window — identified by its owner app and (optional) title — indicates a call.
  /// - Native call app: true on the owner name alone (no title / Screen Recording permission needed).
  /// - Browser app: true iff the title contains a call keyword (the title requires Screen Recording
  ///   permission; without it browser-based calls are not detected).
  static func isCallWindow(ownerName: String?, title: String?) -> Bool {
    guard let ownerName = ownerName else { return false }

    if nativeCallApps.contains(ownerName) {
      return true
    }

    if browserApps.contains(ownerName), let title = title {
      let lowercaseTitle = title.lowercased()
      for keyword in browserCallKeywords where lowercaseTitle.contains(keyword.lowercased()) {
        return true
      }
    }

    return false
  }

  // MARK: - Active outgoing screen share detection

  /// True if a single window — identified by owner app and title — is a share-indicator
  /// window: the floating toolbar/status chrome a conferencing app shows **only while the
  /// user is actively sharing their screen** in a call.
  ///
  /// Known signatures (window names are internal identifiers, not localized UI strings,
  /// except the browser bubble which is English-locale best effort):
  /// - Zoom: "zoom share statusbar window" / "zoom share toolbar window" floating controls
  /// - Microsoft Teams: "Screen sharing toolbar" window while presenting
  /// - Browsers (Google Meet / Teams web): the "<site> is sharing your screen/a tab/a window"
  ///   stop-sharing bubble window
  static func isShareIndicatorWindow(ownerName: String?, title: String?) -> Bool {
    guard let ownerName = ownerName, let title = title, !title.isEmpty else { return false }
    let lowerTitle = title.lowercased()

    if ownerName == "zoom.us" {
      return lowerTitle.contains("zoom share")
    }

    if ownerName.contains("Microsoft Teams") || ownerName == "MSTeams" {
      return lowerTitle.contains("sharing toolbar")
    }

    if browserApps.contains(ownerName) {
      return lowerTitle.contains("is sharing your screen")
        || lowerTitle.contains("is sharing a tab")
        || lowerTitle.contains("is sharing a window")
    }

    return false
  }

  /// True if any on-screen window indicates an active outgoing screen share (the user is
  /// presenting in Zoom/Teams/Meet/etc.). Window titles require Screen Recording permission;
  /// without it only windows with readable names are considered.
  ///
  /// Used to pause Intentive's periodic capture: a one-shot ScreenCaptureKit capture while another
  /// app streams the screen contends in WindowServer capture arbitration and has been observed
  /// to stop the other app's share (issue #10143).
  static func activeScreenSharePresent() -> Bool {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else {
      return false
    }
    for window in windows {
      let owner = window[kCGWindowOwnerName as String] as? String
      let title = window[kCGWindowName as String] as? String
      if isShareIndicatorWindow(ownerName: owner, title: title) {
        return true
      }
    }
    return false
  }
}
