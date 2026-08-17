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
    defaults.set("normal-main-chat-value", forKey: "mainChatUserData")

    OnboardingFlow.clearPersistedState(in: defaults)

    for key in OnboardingFlow.persistedStateKeys {
      XCTAssertNil(defaults.object(forKey: key), "\(key) must be cleared")
    }
    for key in retiredKeys {
      XCTAssertEqual(defaults.string(forKey: key), "ignored-retired-value")
    }
    XCTAssertEqual(defaults.string(forKey: "mainChatUserData"), "normal-main-chat-value")
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
          clearOnboardingJournal: { effects.append(.onboardingJournalCleared) }))

      let plan = await preparation.execute(source: source)

      XCTAssertEqual(
        effects,
        [
          .transcriptionIntent(false), .transcriptionStopped,
          .screenIntent(false), .monitoringStopped,
          .completionReset, .defaultsCleared, .onboardingJournalCleared,
        ])
      XCTAssertEqual(plan.shouldRestart, source != .signOut)
    }
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
