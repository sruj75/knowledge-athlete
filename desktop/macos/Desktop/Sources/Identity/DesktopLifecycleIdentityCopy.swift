import Foundation

/// Identity-bearing copy used by lifecycle, recovery, and retained settings surfaces.
/// Keeping these strings together prevents update or error paths from drifting back to
/// predecessor branding while their behavior remains owned by the existing policies.
enum DesktopLifecycleIdentityCopy {
  static let whatsNewTitle = "Intentive updated"
  static let updateTitle = "Update Intentive"
  static let updateMessage = "Please install the latest Intentive desktop app to continue."
  static let reachErrorTitle = "Couldn't reach Intentive"
  static let alreadyResponding = "Intentive is already responding in the app."
  static let microphoneStopped =
    "Intentive stopped recording because your microphone returned no audio. Check your input device and try again."
  static let screenRecordingPermissionRequired =
    "Intentive needs Screen Recording permission to continue monitoring. Please re-enable it in System Settings."
  static let accountDeletedSignOutFailed =
    "Your account was deleted, but Intentive couldn't sign you out. Quit and reopen Intentive."
  static let rewindBatteryDetail =
    "On battery, Intentive captures your screen less often to save power while keeping text recognition accurate."
  static let transcriptionLanguageDetail =
    "Languages you speak to Intentive over push-to-talk — the first is your primary. Intentive identifies which one you're speaking each turn."
  static let systemAudioMeetingDetail =
    "Intentive captures other apps' audio only while you're in a call (e.g. Zoom, Teams, FaceTime). Detecting browser-based calls like Google Meet requires Screen Recording permission."
  static let insightsEmptyState =
    "Proactive insights from Intentive will appear here as you work.\nEnable the Insight Assistant to start seeing them."
  static let chatLimitDetail =
    "You've hit your monthly limit. Upgrade to keep chatting with Intentive without restrictions."
  static let generalLimitDetail =
    "You've hit your monthly limit. Upgrade to keep using Intentive without restrictions."
  static let managedAIAuthenticationRequired =
    "Intentive authentication is required for managed AI. Sign in, then try again."
}
