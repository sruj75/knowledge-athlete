import XCTest

@testable import Omi_Computer

final class PersistedCaptureLaunchPolicyTests: XCTestCase {
  func testRestoresListeningFromPersistedIntentWithoutWaitingForRemoteKeys() {
    XCTAssertEqual(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: true,
        isTranscribing: false,
        persistedMode: .onlyDuringMeetings
      ),
      .onlyDuringMeetings
    )
  }

  func testDoesNotRestartListeningWhenUserDisabledItOrItIsAlreadyRunning() {
    XCTAssertNil(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: false,
        isTranscribing: false,
        persistedMode: .always
      )
    )
    XCTAssertNil(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: true,
        isTranscribing: true,
        persistedMode: .always
      )
    )
  }

  func testRestoresContinuousListeningWithItsPersistedMode() {
    XCTAssertEqual(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: true,
        isTranscribing: false,
        persistedMode: .always
      ),
      .always
    )
  }

  func testRestoresCaptureWhenSettingsSyncFinishesAfterLaunch() {
    XCTAssertTrue(
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: true,
        isMonitoring: false
      )
    )
  }

  func testDoesNotRestartCaptureWhenUserDisabledItOrItIsAlreadyRunning() {
    XCTAssertFalse(
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: false,
        isMonitoring: false
      )
    )
    XCTAssertFalse(
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: true,
        isMonitoring: true
      )
    )
  }
}

@MainActor
final class SettingsSyncCaptureRestorationTests: XCTestCase {
  func testApplyingServerSettingsNotifiesCaptureRuntimeToReconcile() {
    let notification = expectation(description: "capture runtime reconciliation notification")
    let observer = NotificationCenter.default.addObserver(
      forName: .assistantSettingsDidSyncFromServer,
      object: nil,
      queue: nil
    ) { _ in
      notification.fulfill()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    SettingsSyncManager.shared.applyRemoteSettings(AssistantSettingsResponse())

    XCTAssertEqual(XCTWaiter().wait(for: [notification], timeout: 0), .completed)
  }
}
