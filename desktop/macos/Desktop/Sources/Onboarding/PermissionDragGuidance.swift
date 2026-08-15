import AppKit

@MainActor
enum PermissionDragGuidance {
  private static var lastPresentedAt: Date?

  /// Remove the drag card immediately — the permission was granted or the user
  /// skipped, so the floating icon should not linger.
  static func dismiss() {
    lastPresentedAt = nil
    PermissionGuidanceOverlay.shared.dismiss()
  }

  static func presentDragToGrantHelper(settingsPID: pid_t? = nil) async {
    if let lastPresentedAt, Date().timeIntervalSince(lastPresentedAt) < 2 { return }
    lastPresentedAt = Date()

    let appURL = Bundle.main.bundleURL
    let appName =
      (Bundle.main.infoDictionary?["CFBundleName"] as? String)
      ?? (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
      ?? "Omi"
    let icon = NSApp.applicationIconImage ?? NSWorkspace.shared.icon(forFile: appURL.path)

    // System Settings launches asynchronously (100s of ms). Wait for its window to
    // exist before presenting, so the card anchors to the real window from its first
    // paint instead of flashing in the detached bottom-of-screen fallback and
    // pointing at nothing (the reported "drag card appeared before Settings, arrow
    // pointing straight up" bug). Mirrors the screen-recording instruction overlay.
    var anchor: CGRect?
    for _ in 0..<12 {  // ~2.4s
      if let frame = PermissionSystemSettingsWindow.frame(pid: settingsPID) {
        anchor = frame
        break
      }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    guard let anchor else {
      lastPresentedAt = nil
      return
    }

    // The overlay owns the System Settings lifecycle from here: it re-anchors over
    // the window as it moves and dismisses the card when the user closes it.
    PermissionGuidanceOverlay.shared.presentDragToGrantCard(
      appIcon: icon, appName: appName, appURL: appURL, near: anchor)
  }
}

enum PermissionSystemSettingsWindow {
  static func frame(pid: pid_t? = nil) -> CGRect? {
    let settingsPID =
      pid
      ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
      .first?.processIdentifier
    guard let settingsPID,
      let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    return frame(pid: settingsPID, windows: windows)
  }

  static func frame(pid: pid_t, windows: [[String: Any]]) -> CGRect? {
    windows
      .compactMap { window -> CGRect? in
        guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
          (window[kCGWindowLayer as String] as? Int) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          let x = bounds["X"],
          let y = bounds["Y"],
          let width = bounds["Width"],
          let height = bounds["Height"],
          min(width, height) > 100
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
      }
      .max(by: { $0.width * $0.height < $1.width * $1.height })
      .map(SpatialOverlayGeometry.globalAppKitFrame(topLeftFrame:))
  }
}
