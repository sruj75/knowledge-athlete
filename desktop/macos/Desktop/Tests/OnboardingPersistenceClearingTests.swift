import XCTest

@testable import Omi_Computer

private actor OnboardingStopGate {
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation = $0 }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private actor OnboardingStopFlag {
  private var value = false
  func mark() { value = true }
  func read() -> Bool { value }
}

private actor OnboardingRestorationGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var entered = false

  func suspend() async {
    entered = true
    entryWaiters.forEach { $0.resume() }
    entryWaiters.removeAll()
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilSuspended() async {
    if entered { return }
    await withCheckedContinuation { entryWaiters.append($0) }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class OnboardingAuthorityFlag {
  var isCurrent = true
}

@MainActor
final class OnboardingPersistenceClearingTests: XCTestCase {
  private enum Effect: Equatable {
    case transcriptionIntent(Bool)
    case transcriptionStopped
    case screenIntent(Bool)
    case monitoringStopped
    case completionReset
    case defaultsCleared
    case onboardingJournalCleared
    case onboardingProjectionReset
  }

  func testPersistedStateKeysContainOnlyRetainedSetupState() {
    XCTAssertEqual(
      Set(OnboardingFlow.persistedStateKeys),
      [
        DefaultsKey.onboardingHowDidYouHearSource.rawValue,
        DefaultsKey.onboardingResumeStep.rawValue,
        DefaultsKey.onboardingJustCompleted.rawValue,
        DefaultsKey.onboardingExitOutcome.rawValue,
      ])
  }

  func testClearPersistedStateRemovesRetainedSetupStateWithoutBroadeningDeletion() throws {
    let suiteName = "OnboardingPersistenceClearingTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    for key in OnboardingFlow.persistedStateKeys {
      defaults.set("retained-setup-value", forKey: key)
    }
    let retiredKeys = [
      "onboardingStep", "onboardingFurthestStep", "onboardingRole",
      "onboardingGoalDraft", "hasSeenRewindIntro", "hasTriggeredAccessibility",
    ]
    for key in retiredKeys {
      defaults.set("ignored-retired-value", forKey: key)
    }
    let normalMainChatKey = "mainChatUserData"
    defaults.set("normal-main-chat-value", forKey: normalMainChatKey)

    OnboardingFlow.clearPersistedState(in: defaults)

    for key in OnboardingFlow.persistedStateKeys {
      XCTAssertNil(defaults.object(forKey: key), "\(key) must be cleared")
    }
    for key in retiredKeys {
      XCTAssertEqual(defaults.string(forKey: key), "ignored-retired-value")
    }
    XCTAssertEqual(defaults.string(forKey: normalMainChatKey), "normal-main-chat-value")
  }

  func testEveryReplayEntryPointUsesTheSameCaptureSafePreparation() async {
    for source in OnboardingReplaySource.allCases {
      var effects: [Effect] = []
      let preparation = OnboardingReplayPreparation(
        effects: .init(
          setTranscriptionIntent: { effects.append(.transcriptionIntent($0)) },
          stopTranscription: { effects.append(.transcriptionStopped) },
          setScreenAnalysisIntent: { effects.append(.screenIntent($0)) },
          stopScreenMonitoring: { effects.append(.monitoringStopped) },
          resetCompletion: { effects.append(.completionReset) },
          clearPersistedState: { effects.append(.defaultsCleared) },
          clearOnboardingJournal: { effects.append(.onboardingJournalCleared) },
          resetOnboardingProjection: { effects.append(.onboardingProjectionReset) }))

      let plan = await preparation.execute(source: source)

      let expected: [Effect] = [
        .transcriptionIntent(false), .transcriptionStopped,
        .screenIntent(false), .monitoringStopped,
        .completionReset, .defaultsCleared, .onboardingJournalCleared, .onboardingProjectionReset,
      ]
      XCTAssertEqual(
        effects,
        expected)
      XCTAssertEqual(plan.shouldRestart, source != .signOut)
    }
  }

  func testFailedAuthCommitRestoresQuiescedCaptureWithoutApplyingDestructiveCleanup() async {
    enum SignOutFailure: Error { case injected }
    var effects: [String] = []
    let transaction = OnboardingSignOutTransaction(
      preparation: transactionPreparation(effects: { effects.append($0) }),
      captureRuntime: .init(
        effects: .init(
          quiesce: { effects.append("quiesce") },
          restore: { _ in
            effects.append("restore")
            return true
          })),
      commitAuthentication: {
        effects.append("commit")
        throw SignOutFailure.injected
      },
      isAuthenticationAuthoritative: {
        effects.append("authority")
        return true
      })

    do {
      _ = try await transaction.execute()
      XCTFail("Injected sign-out failure must be surfaced")
    } catch SignOutFailure.injected {
      // Runtime capture is restored from unchanged intent; persisted owner
      // projections cannot change until authentication commits.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(effects, ["journal", "quiesce", "commit", "authority", "restore", "authority"])
  }

  func testSuccessfulSignOutQuiescesBeforeCommitThenAppliesCleanup() async throws {
    var effects: [String] = []
    let transaction = OnboardingSignOutTransaction(
      preparation: transactionPreparation(effects: { effects.append($0) }),
      captureRuntime: .init(
        effects: .init(
          quiesce: { effects.append("quiesce") },
          restore: { _ in
            effects.append("restore")
            return true
          })),
      commitAuthentication: {
        effects.append("commit")
        return true
      },
      isAuthenticationAuthoritative: {
        effects.append("authority")
        return true
      })

    let didCommit = try await transaction.execute()
    XCTAssertTrue(didCommit)

    XCTAssertEqual(
      effects,
      [
        "journal", "quiesce", "commit", "authority", "transcriptionIntent:false", "transcriptionStopped",
        "screenIntent:false", "monitoringStopped", "completionReset", "defaultsCleared",
        "projectionReset",
      ])
  }

  func testSupersededSignOutDoesNotRestoreCaptureOrApplyPriorOwnerCleanup() async throws {
    var effects: [String] = []
    let transaction = OnboardingSignOutTransaction(
      preparation: transactionPreparation(effects: { effects.append($0) }),
      captureRuntime: .init(
        effects: .init(
          quiesce: { effects.append("quiesce") },
          restore: { _ in
            effects.append("restore")
            return true
          })),
      commitAuthentication: {
        effects.append("commit")
        return false
      },
      isAuthenticationAuthoritative: {
        effects.append("authority")
        return false
      })

    let didCommit = try await transaction.execute()

    XCTAssertFalse(didCommit)
    XCTAssertEqual(effects, ["journal", "quiesce", "commit", "authority"])
  }

  func testAuthorityLossWhileRestorationIsSuspendedCancelsTheObsoleteFailure() async {
    enum SignOutFailure: Error { case injected }
    let restorationGate = OnboardingRestorationGate()
    let authority = OnboardingAuthorityFlag()
    var effects: [String] = []
    let transaction = OnboardingSignOutTransaction(
      preparation: transactionPreparation(effects: { effects.append($0) }),
      captureRuntime: .init(
        effects: .init(
          quiesce: { effects.append("quiesce") },
          restore: { isAuthoritative in
            effects.append("restore:started")
            await restorationGate.suspend()
            guard isAuthoritative() else {
              effects.append("restore:cancelled")
              return false
            }
            effects.append("monitoring:started")
            return true
          })),
      commitAuthentication: {
        effects.append("commit")
        throw SignOutFailure.injected
      },
      isAuthenticationAuthoritative: {
        effects.append("authority")
        return authority.isCurrent
      })

    let execution = Task { try await transaction.execute() }
    await restorationGate.waitUntilSuspended()
    authority.isCurrent = false
    await restorationGate.release()

    do {
      let didCommit = try await execution.value
      XCTAssertFalse(didCommit)
    } catch {
      XCTFail("A superseded sign-out must not surface its obsolete failure: \(error)")
    }
    XCTAssertEqual(
      effects,
      ["journal", "quiesce", "commit", "authority", "restore:started", "authority", "restore:cancelled"])
  }

  func testCaptureQuiescenceWaitsForTheActualTranscriptionStopTask() async {
    let gate = OnboardingStopGate()
    let returned = OnboardingStopFlag()
    let appState = AppState()
    appState.transcriptionStopTask = Task { await gate.wait() }
    let waiter = Task { @MainActor in
      await appState.stopTranscriptionAndWait()
      await returned.mark()
    }

    for _ in 0..<10 { await Task.yield() }
    let returnedBeforeTeardown = await returned.read()
    XCTAssertFalse(returnedBeforeTeardown)

    await gate.release()
    await waiter.value
    let returnedAfterTeardown = await returned.read()
    XCTAssertTrue(returnedAfterTeardown)
    appState.transcriptionStopTask = nil
  }

  func testReplayProjectionCannotLeakIntoTheNextOwner() {
    let provider = ChatProvider()
    provider.isOnboarding = true
    provider.preOnboardingMainMessages = []
    provider.presentOnboardingOpener()

    provider.resetOnboardingProjectionForReplay()

    XCTAssertFalse(provider.isOnboarding)
    XCTAssertNil(provider.preOnboardingMainMessages)
    XCTAssertNil(provider.onboardingOpener)
    provider.beginOnboardingJournal()
    XCTAssertTrue(provider.isOnboarding)
  }

  func testSecondAccountDoesNotSeeThePreviousSetupAnswer() throws {
    let suiteName = "OnboardingPersistenceClearingTests.owner-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("Friend", forKey: .onboardingHowDidYouHearSource)
    defaults.set(SBOnboardingModel.Step.language.rawValue, forKey: .onboardingResumeStep)

    OnboardingFlow.clearPersistedState(in: defaults)

    XCTAssertNil(defaults.string(forKey: .onboardingHowDidYouHearSource))
    XCTAssertNil(defaults.object(forKey: .onboardingResumeStep))
  }

  func testResetAutomationIsUnavailableToProductionFamilyBundles() {
    XCTAssertFalse(OnboardingResetAutomationPolicy.isAvailable(isProductionBundle: true))
    XCTAssertTrue(OnboardingResetAutomationPolicy.isAvailable(isProductionBundle: false))
  }

  private func transactionPreparation(
    effects: @escaping (String) -> Void
  ) -> OnboardingReplayPreparation {
    OnboardingReplayPreparation(
      effects: .init(
        setTranscriptionIntent: { effects("transcriptionIntent:\($0)") },
        stopTranscription: { effects("transcriptionStopped") },
        setScreenAnalysisIntent: { effects("screenIntent:\($0)") },
        stopScreenMonitoring: { effects("monitoringStopped") },
        resetCompletion: { effects("completionReset") },
        clearPersistedState: { effects("defaultsCleared") },
        clearOnboardingJournal: { effects("journal") },
        resetOnboardingProjection: { effects("projectionReset") }))
  }
}
