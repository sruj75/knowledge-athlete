import XCTest

@testable import Omi_Computer

final class OnboardingPermissionToolTests: XCTestCase {
  func testPermissionStatusPayloadContainsOnlyRetainedPermissions() {
    let statuses = ChatToolExecutor.onboardingPermissionStatusPayload(
      screenRecording: false,
      microphone: false,
      notifications: false,
      accessibility: false
    )

    XCTAssertEqual(Set(statuses.keys), Set(ChatToolExecutor.onboardingPermissionTypes))
    XCTAssertEqual(
      ChatToolExecutor.onboardingPermissionTypes,
      ["screen_recording", "microphone", "notifications", "accessibility"])
  }

  @MainActor
  func testRetainedOnboardingGraphOmitsExternalAndBroadAccessStages() {
    XCTAssertEqual(
      SBOnboardingModel.Step.allCases,
      [
        .promise, .name, .howHeard, .language,
        .mic, .systemAudio, .screen, .accessibility,
        .shortcutOpen, .shortcutTalk, .screenDemo, .capture,
      ])
  }

  @MainActor
  func testPregrantedScreenRecordingDoesNotSkipSeparateSystemAudioConsent() {
    let appState = AppState()
    appState.hasScreenRecordingPermission = true
    appState.recordSystemAudioCaptureOutcome(.unknown)
    let model = SBOnboardingModel(appState: appState, chatProvider: ChatProvider(), onComplete: nil)

    XCTAssertFalse(model.isGranted("system_audio"))
    XCTAssertEqual(model.firstUnaskedStep(from: .systemAudio), .systemAudio)

    appState.recordSystemAudioCaptureOutcome(.denied)
    XCTAssertEqual(model.firstUnaskedStep(from: .systemAudio), .systemAudio)
  }

  @MainActor
  func testRepeatedSystemAudioPollingCancelsTheOlderConsentTask() throws {
    let model = SBOnboardingModel(appState: AppState(), chatProvider: ChatProvider(), onComplete: nil)

    model.pollPermission("system_audio")
    let first = try XCTUnwrap(model.pollTasks["system_audio"])
    model.pollPermission("system_audio")
    let second = try XCTUnwrap(model.pollTasks["system_audio"])
    defer { second.cancel() }

    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(second.isCancelled)
  }
}
