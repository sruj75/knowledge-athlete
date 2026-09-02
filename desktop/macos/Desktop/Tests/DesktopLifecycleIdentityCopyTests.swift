import XCTest

@testable import Omi_Computer

final class DesktopLifecycleIdentityCopyTests: XCTestCase {
  func testLifecycleAndRecoveryCopyUsesTheFinalIdentity() {
    let copy = [
      DesktopLifecycleIdentityCopy.whatsNewTitle,
      DesktopLifecycleIdentityCopy.updateTitle,
      DesktopLifecycleIdentityCopy.updateMessage,
      DesktopLifecycleIdentityCopy.reachErrorTitle,
      DesktopLifecycleIdentityCopy.alreadyResponding,
      DesktopLifecycleIdentityCopy.microphoneStopped,
      DesktopLifecycleIdentityCopy.screenRecordingPermissionRequired,
      DesktopLifecycleIdentityCopy.accountDeletedSignOutFailed,
      DesktopLifecycleIdentityCopy.rewindBatteryDetail,
      DesktopLifecycleIdentityCopy.transcriptionLanguageDetail,
      DesktopLifecycleIdentityCopy.systemAudioMeetingDetail,
      DesktopLifecycleIdentityCopy.insightsEmptyState,
      DesktopLifecycleIdentityCopy.chatLimitDetail,
      DesktopLifecycleIdentityCopy.generalLimitDetail,
      DesktopLifecycleIdentityCopy.managedAIAuthenticationRequired,
    ].joined(separator: "\n")

    XCTAssertTrue(copy.contains("Intentive"))
    XCTAssertFalse(copy.localizedCaseInsensitiveContains("Omi"))
  }

  func testUpdateFallbackCopyIsSpecificAndActionable() {
    XCTAssertEqual(DesktopLifecycleIdentityCopy.whatsNewTitle, "Intentive updated")
    XCTAssertEqual(DesktopLifecycleIdentityCopy.updateTitle, "Update Intentive")
    XCTAssertEqual(
      DesktopLifecycleIdentityCopy.updateMessage,
      "Please install the latest Intentive desktop app to continue.")
  }

  func testPermissionRecoveryNamesIntentiveAndTheRequiredPermission() {
    XCTAssertEqual(
      DesktopLifecycleIdentityCopy.screenRecordingPermissionRequired,
      "Intentive needs Screen Recording permission to continue monitoring. Please re-enable it in System Settings.")
  }
}
