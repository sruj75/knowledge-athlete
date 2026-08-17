import XCTest

@testable import Omi_Computer

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

      XCTAssertEqual(
        effects,
        [
          .transcriptionIntent(false), .transcriptionStopped,
          .screenIntent(false), .monitoringStopped,
          .completionReset, .defaultsCleared, .onboardingJournalCleared, .onboardingProjectionReset,
        ])
      XCTAssertEqual(plan.shouldRestart, source != .signOut)
    }
  }

  func testFailedAuthCommitDoesNotApplyDestructiveSignOutCleanup() async {
    enum SignOutFailure: Error { case injected }
    var effects: [String] = []
    let transaction = OnboardingSignOutTransaction(
      clearCurrentOwnerJournal: { effects.append("journal") },
      commitAuthentication: {
        effects.append("commit")
        throw SignOutFailure.injected
      },
      applyPostCommitCleanup: { effects.append("cleanup") })

    do {
      _ = try await transaction.execute()
      XCTFail("Injected sign-out failure must be surfaced")
    } catch SignOutFailure.injected {
      // The owner-scoped setup journal is cleared while its lease is valid, but
      // capture/default/completion cleanup cannot run until auth commits.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(effects, ["journal", "commit"])
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
}
