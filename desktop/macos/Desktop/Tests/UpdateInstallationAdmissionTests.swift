import XCTest

@testable import Omi_Computer

@MainActor
final class UpdateInstallationAdmissionTests: XCTestCase {
  func testPublishedIdleDelegatePathInstallsImmediately() {
    let state = DelegateInstallationState()
    let delegate = UpdaterDelegate()

    XCTAssertTrue(
      delegate.handleScheduledInstallation(
        version: "1.2.3",
        isDevelopmentBuild: false,
        activitySnapshotProvider: { .idle },
        install: { state.installCount += 1 }
      )
    )
    XCTAssertEqual(state.installCount, 1)
  }

  func testPublishedDelegateDefersEveryRetainedActivityUntilIdleThenInstallsExactlyOnce() {
    let activeSnapshots: [(name: String, snapshot: UpdateInstallationActivitySnapshot)] = [
      ("ambient transcription", .init(ambientTranscriptionActive: true)),
      ("voice capture", .init(voiceCaptureActive: true)),
      ("voice provider", .init(voiceProviderActive: true)),
      ("voice playback", .init(voicePlaybackActive: true)),
      ("pending voice tool", .init(pendingVoiceToolCount: 1)),
      ("realtime token mint", .init(realtimeTokenMintActive: true)),
      ("voice turn", .init(voiceTurnActive: true)),
      ("chat send", .init(chatSendActive: true)),
      ("chat streaming", .init(chatStreamingActive: true)),
    ]

    for activity in activeSnapshots {
      let state = DelegateInstallationState(snapshot: activity.snapshot)
      let scheduler = ManualDelayedActionScheduler()
      let delegate = UpdaterDelegate()

      XCTAssertTrue(
        delegate.handleScheduledInstallation(
          version: "1.2.3",
          isDevelopmentBuild: false,
          scheduler: scheduler,
          activitySnapshotProvider: { state.snapshot },
          install: { state.installCount += 1 }
        ),
        activity.name
      )
      XCTAssertEqual(state.installCount, 0, activity.name)
      XCTAssertEqual(scheduler.activeCount, 1, activity.name)

      state.snapshot = .idle
      XCTAssertTrue(scheduler.fireNext(), activity.name)
      XCTAssertEqual(state.installCount, 1, activity.name)
      XCTAssertEqual(scheduler.activeCount, 0, activity.name)
      XCTAssertFalse(scheduler.fireNext(), activity.name)
      XCTAssertEqual(state.installCount, 1, activity.name)
    }
  }

  func testMaxDurationRotationOwnsAmbientFinalizationUntilAsyncWorkCompletes() async {
    let previousAppState = AppState.current
    defer { AppState.current = previousAppState }

    let appState = AppState()
    appState.isTranscribing = true

    await appState.handleMaxRecordingDurationReached {
      XCTAssertTrue(appState.isSavingConversation)
      XCTAssertTrue(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)

      appState.isTranscribing = false
      await Task.yield()

      XCTAssertTrue(appState.isSavingConversation)
      XCTAssertTrue(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)
    }

    XCTAssertFalse(appState.isSavingConversation)
    XCTAssertEqual(appState.activeAmbientFinalizationCount, 0)
    XCTAssertFalse(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)
  }

  func testOwnerTransitionQuiescenceOwnsAmbientFinalizationUntilAsyncWorkCompletes() async {
    let previousAppState = AppState.current
    defer { AppState.current = previousAppState }

    let appState = AppState()
    await appState.quiesceAmbientCaptureForOwnerTransition {
      XCTAssertTrue(appState.isSavingConversation)
      XCTAssertTrue(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)

      await Task.yield()

      XCTAssertTrue(appState.isSavingConversation)
      XCTAssertTrue(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)
    }

    XCTAssertFalse(appState.isSavingConversation)
    XCTAssertEqual(appState.activeAmbientFinalizationCount, 0)
    XCTAssertFalse(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)
  }

  func testOrdinaryTranscriptionStopTaskKeepsCurrentAmbientSnapshotActive() {
    let previousAppState = AppState.current
    defer { AppState.current = previousAppState }

    let appState = AppState()
    appState.isTranscribing = false
    appState.transcriptionStopTask = Task { @MainActor in }

    XCTAssertTrue(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)

    appState.transcriptionStopTask?.cancel()
    appState.transcriptionStopTask = nil
    XCTAssertFalse(UpdateInstallationActivitySnapshot.current().ambientTranscriptionActive)
  }

  func testDevelopmentDelegatePathLeavesInstallScheduledForQuit() {
    let state = DelegateInstallationState()
    let delegate = UpdaterDelegate()

    XCTAssertFalse(
      delegate.handleScheduledInstallation(
        version: "1.2.3",
        isDevelopmentBuild: true,
        activitySnapshotProvider: { .idle },
        install: { state.installCount += 1 }
      )
    )
    XCTAssertEqual(state.installCount, 0)
  }
}

@MainActor
private final class DelegateInstallationState {
  var snapshot: UpdateInstallationActivitySnapshot
  var installCount = 0

  init(snapshot: UpdateInstallationActivitySnapshot = .idle) {
    self.snapshot = snapshot
  }
}
