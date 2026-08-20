import XCTest

@testable import Omi_Computer

final class PersistedCaptureLaunchPolicyTests: XCTestCase {
  func testRestoresListeningFromPersistedIntentWithoutWaitingForRemoteKeys() {
    XCTAssertEqual(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: true,
        isTranscribing: false,
        persistedMode: .onlyDuringMeetings,
        onboardingExitOutcome: .completed
      ),
      .onlyDuringMeetings
    )
  }

  func testDoesNotRestartListeningWhenUserDisabledItOrItIsAlreadyRunning() {
    XCTAssertNil(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: false,
        isTranscribing: false,
        persistedMode: .always,
        onboardingExitOutcome: .completed
      )
    )
    XCTAssertNil(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: true,
        isTranscribing: true,
        persistedMode: .always,
        onboardingExitOutcome: .completed
      )
    )
  }

  func testRestoresContinuousListeningWithItsPersistedMode() {
    XCTAssertEqual(
      PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
        intentEnabled: true,
        isTranscribing: false,
        persistedMode: .always,
        onboardingExitOutcome: .completed
      ),
      .always
    )
  }

  func testRestoresCaptureWhenSettingsSyncFinishesAfterLaunch() {
    XCTAssertTrue(
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: true,
        isMonitoring: false,
        onboardingExitOutcome: .completed
      )
    )
  }

  func testDoesNotRestartCaptureWhenUserDisabledItOrItIsAlreadyRunning() {
    XCTAssertFalse(
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: false,
        isMonitoring: false,
        onboardingExitOutcome: .completed
      )
    )
    XCTAssertFalse(
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: true,
        isMonitoring: true,
        onboardingExitOutcome: .completed
      )
    )
  }
}

@MainActor
final class LocalSettingsCaptureRestorationTests: XCTestCase {
  func testChangingLocalSettingsNotifiesCaptureRuntimeToReconcile() {
    let previous = AssistantSettings.shared.screenAnalysisEnabled
    defer { AssistantSettings.shared.screenAnalysisEnabled = previous }
    let notification = expectation(description: "capture runtime reconciliation notification")
    let observer = NotificationCenter.default.addObserver(
      forName: .assistantSettingsDidChange,
      object: nil,
      queue: nil
    ) { _ in
      notification.fulfill()
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    AssistantSettings.shared.screenAnalysisEnabled.toggle()

    XCTAssertEqual(XCTWaiter().wait(for: [notification], timeout: 0), .completed)
  }
}
