import XCTest

@testable import Omi_Computer

@MainActor
final class OnboardingCompletionBehaviorTests: XCTestCase {
  func testDefaultCompletionEnablesAllDayListeningOnlyOnce() async throws {
    let suiteName = "AllDayOnboarding-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let settings = AssistantSettings.shared
    let previousMode = settings.systemAudioCaptureMode
    let previousListening = settings.transcriptionEnabled
    let previousScreenAnalysis = settings.screenAnalysisEnabled
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      settings.systemAudioCaptureMode = previousMode
      settings.transcriptionEnabled = previousListening
      settings.screenAnalysisEnabled = previousScreenAnalysis
    }
    var captureStarts = 0
    var completionPublications = 0
    var screenMonitoringRequested = false
    var loginRequested = false
    var openerPresented = false
    let published = expectation(description: "completion published")
    published.assertForOverFulfill = true
    let executor = OnboardingExitExecutor(
      effects: .init(
        recordAnalytics: { _ in },
        persistOutcome: { OnboardingExitPersistence.persist($0, in: defaults) },
        setTranscriptionIntent: { settings.transcriptionEnabled = $0 },
        startTranscriptionSession: {
          captureStarts += 1
          XCTAssertEqual(settings.systemAudioCaptureMode, .always)
        },
        stopTranscriptionSession: { XCTFail("Completing setup must not stop listening") },
        setScreenAnalysisIntent: { settings.screenAnalysisEnabled = $0 },
        startScreenMonitoring: { screenMonitoringRequested = true },
        stopScreenMonitoring: { XCTFail("Completing setup must not stop monitoring") },
        requestLaunchAtLogin: { loginRequested = $0 },
        setJustCompleted: { _ in },
        prepareMainChat: {},
        presentOpener: { openerPresented = true },
        clearResumeState: {},
        finishJournal: {},
        publishCompletion: {
          completionPublications += 1
          published.fulfill()
        },
        setSystemAudioCaptureMode: { settings.systemAudioCaptureMode = $0 }))
    let model = SBOnboardingModel(
      appState: AppState(), chatProvider: ChatProvider(), exitExecutor: executor, onComplete: nil)

    model.complete()
    model.complete()
    model.skip()
    await fulfillment(of: [published], timeout: 1)

    XCTAssertEqual(OnboardingExitPersistence.outcome(in: defaults), .completed)
    XCTAssertEqual(settings.systemAudioCaptureMode, .always)
    XCTAssertTrue(settings.transcriptionEnabled)
    XCTAssertEqual(captureStarts, 1)
    XCTAssertEqual(completionPublications, 1)
    XCTAssertTrue(settings.screenAnalysisEnabled)
    XCTAssertTrue(screenMonitoringRequested)
    XCTAssertTrue(loginRequested)
    XCTAssertTrue(openerPresented)
  }

  func testMonitoringStartsOnlyWhenEveryExistingGateAllowsIt() {
    XCTAssertTrue(
      OnboardingScreenMonitoringStartPolicy.shouldStart(
        intentEnabled: true,
        isPaywalled: false,
        keysAvailable: true,
        permissionGranted: true,
        isMonitoring: false))

    let deniedInputs = [
      (false, false, true, true, false),
      (true, true, true, true, false),
      (true, false, false, true, false),
      (true, false, true, false, false),
      (true, false, true, true, true),
    ]
    for input in deniedInputs {
      XCTAssertFalse(
        OnboardingScreenMonitoringStartPolicy.shouldStart(
          intentEnabled: input.0,
          isPaywalled: input.1,
          keysAvailable: input.2,
          permissionGranted: input.3,
          isMonitoring: input.4))
    }
  }

  func testFinalChoiceDisclosesCompletionSideEffects() {
    let disclosure = SBOnboardingCompletionCopy.disclosure
    XCTAssertTrue(disclosure.contains("Launch at Login"))
    XCTAssertTrue(disclosure.contains("listening"))
    XCTAssertTrue(disclosure.contains("screen analysis"))
  }
}
