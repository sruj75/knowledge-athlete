import XCTest

@testable import Omi_Computer

@MainActor
final class OnboardingCompletionBehaviorTests: XCTestCase {
  private enum Effect: Equatable {
    case analytics(OnboardingExitAnalyticsOutcome)
    case persisted(OnboardingPersistedExitOutcome)
    case mode(AssistantSettings.SystemAudioCaptureMode)
    case transcriptionIntent(Bool)
    case transcriptionStarted
    case transcriptionStopped
    case screenIntent(Bool)
    case monitoringStarted
    case monitoringStopped
    case launchAtLogin(Bool)
    case justCompleted(Bool)
    case mainChatPrepared
    case openerPresented
    case resumeCleared
    case journalFinishedAndMainReloaded
    case completionPublished
  }

  func testBothGenuineChoicesRouteThroughTheOrderedCompletionExecutor() async {
    for selection in [SBOnboardingModel.CaptureSelection.onlyDuringMeetings, .continuous] {
      var effects: [Effect] = []
      let published = expectation(description: "completion published for \(selection)")
      let executor = OnboardingExitExecutor(
        effects: .init(
          recordAnalytics: { effects.append(.analytics($0)) },
          persistOutcome: { effects.append(.persisted($0)) },
          setTranscriptionIntent: { effects.append(.transcriptionIntent($0)) },
          startTranscriptionSession: { effects.append(.transcriptionStarted) },
          stopTranscriptionSession: { effects.append(.transcriptionStopped) },
          setScreenAnalysisIntent: { effects.append(.screenIntent($0)) },
          startScreenMonitoring: { effects.append(.monitoringStarted) },
          stopScreenMonitoring: { effects.append(.monitoringStopped) },
          requestLaunchAtLogin: { effects.append(.launchAtLogin($0)) },
          setJustCompleted: { effects.append(.justCompleted($0)) },
          prepareMainChat: { effects.append(.mainChatPrepared) },
          presentOpener: { effects.append(.openerPresented) },
          clearResumeState: { effects.append(.resumeCleared) },
          finishJournal: { effects.append(.journalFinishedAndMainReloaded) },
          publishCompletion: {
            effects.append(.completionPublished)
            published.fulfill()
          },
          setSystemAudioCaptureMode: { effects.append(.mode($0)) }))
      let model = SBOnboardingModel(
        appState: AppState(),
        chatProvider: ChatProvider(),
        exitExecutor: executor,
        onComplete: nil)

      model.capture(selection)
      model.capture(selection)
      await fulfillment(of: [published], timeout: 1)

      XCTAssertEqual(effects.filter { $0 == .analytics(.completed) }.count, 1)
      XCTAssertFalse(effects.contains(.analytics(.skipped)))
      XCTAssertEqual(effects.filter { $0 == .persisted(.completed) }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .mode(selection.systemAudioCaptureMode) }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .transcriptionIntent(true) }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .transcriptionStarted }.count, 1)
      XCTAssertFalse(effects.contains(.transcriptionStopped))
      XCTAssertEqual(effects.filter { $0 == .screenIntent(true) }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .monitoringStarted }.count, 1)
      XCTAssertFalse(effects.contains(.monitoringStopped))
      XCTAssertEqual(effects.filter { $0 == .launchAtLogin(true) }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .justCompleted(true) }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .openerPresented }.count, 1)
      XCTAssertEqual(effects.filter { $0 == .journalFinishedAndMainReloaded }.count, 1)
      XCTAssertEqual(
        effects,
        [
          .analytics(.completed), .persisted(.completed),
          .mode(selection.systemAudioCaptureMode), .transcriptionIntent(true),
          .screenIntent(true), .launchAtLogin(true), .transcriptionStarted,
          .monitoringStarted, .resumeCleared, .journalFinishedAndMainReloaded,
          .mainChatPrepared, .openerPresented, .justCompleted(true),
          .completionPublished,
        ])
    }
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
