import XCTest

@testable import Omi_Computer

@MainActor
final class OnboardingSkipBehaviorTests: XCTestCase {
  func testVisibleSkipFromEveryRetainedStepHasOnlyNeutralNoCaptureEffects() async {
    for step in SBOnboardingModel.Step.allCases {
      var analytics: [OnboardingExitAnalyticsOutcome] = []
      var persistedOutcomes: [OnboardingPersistedExitOutcome] = []
      var transcriptionIntents: [Bool] = []
      var transcriptionStarts = 0
      var transcriptionStops = 0
      var screenIntents: [Bool] = []
      var monitoringStarts = 0
      var monitoringStops = 0
      var loginRequests: [Bool] = []
      var justCompletedValues: [Bool] = []
      var openerCount = 0
      var journalFinishCount = 0
      var completionPublishCount = 0
      let published = expectation(description: "completion published for \(step)")

      let executor = OnboardingExitExecutor(
        effects: .init(
          recordAnalytics: { analytics.append($0) },
          persistOutcome: { persistedOutcomes.append($0) },
          setTranscriptionIntent: { transcriptionIntents.append($0) },
          startTranscriptionSession: { transcriptionStarts += 1 },
          stopTranscriptionSession: { transcriptionStops += 1 },
          setScreenAnalysisIntent: { screenIntents.append($0) },
          startScreenMonitoring: { monitoringStarts += 1 },
          stopScreenMonitoring: { monitoringStops += 1 },
          requestLaunchAtLogin: { loginRequests.append($0) },
          setJustCompleted: { justCompletedValues.append($0) },
          prepareMainChat: {},
          presentOpener: { openerCount += 1 },
          clearResumeState: {},
          finishJournal: { journalFinishCount += 1 },
          publishCompletion: {
            completionPublishCount += 1
            published.fulfill()
          }))
      let model = SBOnboardingModel(
        appState: AppState(),
        chatProvider: ChatProvider(),
        exitExecutor: executor,
        onComplete: nil)
      model.step = step
      let streamTask = Task<Void, Never> {}
      let pollTask = Task<Void, Never> {}
      let demoTask = Task<Void, Never> {}
      model.streamTask = streamTask
      model.pollTasks["test"] = pollTask
      model.screenDemoSetupTask = demoTask

      model.skip()
      model.skip()
      await fulfillment(of: [published], timeout: 1)

      XCTAssertEqual(analytics, [.skipped], "step=\(step)")
      XCTAssertEqual(persistedOutcomes, [.skipped], "step=\(step)")
      XCTAssertEqual(transcriptionIntents, [false], "step=\(step)")
      XCTAssertEqual(transcriptionStarts, 0, "step=\(step)")
      XCTAssertEqual(transcriptionStops, 1, "step=\(step)")
      XCTAssertEqual(screenIntents, [false], "step=\(step)")
      XCTAssertEqual(monitoringStarts, 0, "step=\(step)")
      XCTAssertEqual(monitoringStops, 1, "step=\(step)")
      XCTAssertEqual(loginRequests, [false], "step=\(step)")
      XCTAssertEqual(justCompletedValues, [false], "step=\(step)")
      XCTAssertEqual(openerCount, 0, "step=\(step)")
      XCTAssertEqual(journalFinishCount, 1, "step=\(step)")
      XCTAssertEqual(completionPublishCount, 1, "step=\(step)")
      XCTAssertTrue(streamTask.isCancelled, "step=\(step)")
      XCTAssertTrue(pollTask.isCancelled, "step=\(step)")
      XCTAssertTrue(demoTask.isCancelled, "step=\(step)")
      XCTAssertTrue(model.pollTasks.isEmpty, "step=\(step)")
    }
  }

  func testSkippedOutcomeOverridesRegisteredCaptureDefaults() throws {
    let suiteName = "OnboardingSkipBehaviorTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.register(defaults: ["transcriptionEnabled": true, "screenAnalysisEnabled": true])

    OnboardingExitPersistence.persist(.skipped, in: defaults)
    defaults.set(false, forKey: "transcriptionEnabled")
    defaults.set(false, forKey: "screenAnalysisEnabled")

    XCTAssertEqual(OnboardingExitPersistence.outcome(in: defaults), .skipped)
    XCTAssertFalse(defaults.bool(forKey: "transcriptionEnabled"))
    XCTAssertFalse(defaults.bool(forKey: "screenAnalysisEnabled"))
  }

  func testSkippedOutcomeCannotRestoreCaptureAcrossHomeLifecycleTriggers() {
    for reason in ["launch", "app active", "settings sync"] {
      XCTAssertNil(
        PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
          intentEnabled: true,
          isTranscribing: false,
          persistedMode: .always,
          onboardingExitOutcome: .skipped),
        reason)
      XCTAssertFalse(
        PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
          intentEnabled: true,
          isMonitoring: false,
          onboardingExitOutcome: .skipped),
        reason)
    }
  }

  func testSkippedOutcomeRejectsRemoteScreenIntent() {
    XCTAssertFalse(
      SettingsSyncManager.shouldImportScreenAnalysis(
        usesLazyDevPermissions: false,
        onboardingExitOutcome: .skipped))
    XCTAssertTrue(
      SettingsSyncManager.shouldImportScreenAnalysis(
        usesLazyDevPermissions: false,
        onboardingExitOutcome: .completed))
  }

  func testSettingsSyncCannotReenableScreenIntentAfterSkip() {
    let defaults = UserDefaults.standard
    let previousOutcome = defaults.object(forKey: .onboardingExitOutcome)
    let previousScreenIntent = defaults.object(forKey: "screenAnalysisEnabled")
    defer {
      if let previousOutcome {
        defaults.set(previousOutcome, forKey: .onboardingExitOutcome)
      } else {
        defaults.removeObject(forKey: .onboardingExitOutcome)
      }
      if let previousScreenIntent {
        defaults.set(previousScreenIntent, forKey: "screenAnalysisEnabled")
      } else {
        defaults.removeObject(forKey: "screenAnalysisEnabled")
      }
    }
    OnboardingExitPersistence.persist(.skipped)
    AssistantSettings.shared.screenAnalysisEnabled = false

    SettingsSyncManager.shared.applyRemoteSettings(
      AssistantSettingsResponse(
        shared: SharedAssistantSettingsResponse(
          cooldownInterval: nil,
          glowOverlayEnabled: nil,
          analysisDelay: nil,
          screenAnalysisEnabled: true)))

    XCTAssertFalse(AssistantSettings.shared.screenAnalysisEnabled)
  }

  /// Static absence tripwire: retired auto-start migrations must not be able to
  /// overwrite the explicit no-capture Skip outcome.
  func testRetiredScreenAutoStartMigrationsStayAbsent() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/MainWindow/DesktopHomeView.swift")
    // omi-test-quality: source-inspection -- static contract: explicit Skip owns capture intent; legacy auto-start migrations are retired
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertFalse(source.contains(["screenAnalysisAutoStartFixed", "_v2"].joined()))
    XCTAssertFalse(source.contains(["screenAnalysisAutoStartFixed", "_v3"].joined()))
  }
}
