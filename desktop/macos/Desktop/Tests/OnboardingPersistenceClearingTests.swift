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
    case localNameProjectionCleared
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
          resetOnboardingProjection: { effects.append(.onboardingProjectionReset) },
          clearLocalNameProjection: { effects.append(.localNameProjectionCleared) }))

      let plan = await preparation.execute(source: source)

      var expected: [Effect] = [
        .transcriptionIntent(false), .transcriptionStopped,
        .screenIntent(false), .monitoringStopped,
        .completionReset, .defaultsCleared, .onboardingJournalCleared, .onboardingProjectionReset,
      ]
      if source == .signOut { expected.append(.localNameProjectionCleared) }
      XCTAssertEqual(
        effects,
        expected)
      XCTAssertEqual(plan.shouldRestart, source != .signOut)
    }
  }

  func testFailedAuthCommitRestoresQuiescedCaptureWithoutApplyingDestructiveCleanup() async {
    enum SignOutFailure: Error { case injected }
    var effects: [String] = []
    let auth = AuthService.shared
    let previousGivenName = auth.givenName
    let previousFamilyName = auth.familyName
    defer {
      auth.givenName = previousGivenName
      auth.familyName = previousFamilyName
    }
    auth.givenName = "Alice"
    auth.familyName = "Owner A"
    let transaction = OnboardingSignOutTransaction(
      preparation: transactionPreparation(effects: { effects.append($0) }),
      captureRuntime: .init(
        effects: .init(
          quiesce: { effects.append("quiesce") },
          restore: { effects.append("restore") })),
      commitAuthentication: {
        effects.append("commit")
        throw SignOutFailure.injected
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

    XCTAssertEqual(effects, ["journal", "quiesce", "commit", "restore"])
    XCTAssertEqual(auth.givenName, "Alice")
    XCTAssertEqual(auth.familyName, "Owner A")
  }

  func testSuccessfulSignOutQuiescesBeforeCommitAndClearsNameBeforeTheNextOwner() async throws {
    var effects: [String] = []
    let auth = AuthService.shared
    let previousGivenName = auth.givenName
    let previousFamilyName = auth.familyName
    defer {
      auth.givenName = previousGivenName
      auth.familyName = previousFamilyName
    }
    auth.givenName = "Alice"
    auth.familyName = "Owner A"
    let transaction = OnboardingSignOutTransaction(
      preparation: transactionPreparation(effects: { effects.append($0) }),
      captureRuntime: .init(
        effects: .init(
          quiesce: { effects.append("quiesce") },
          restore: { effects.append("restore") })),
      commitAuthentication: {
        effects.append("commit")
        return true
      })

    let didCommit = try await transaction.execute()
    XCTAssertTrue(didCommit)

    XCTAssertEqual(
      effects,
      [
        "journal", "quiesce", "commit", "transcriptionIntent:false", "transcriptionStopped",
        "screenIntent:false", "monitoringStopped", "completionReset", "defaultsCleared",
        "projectionReset", "localNameCleared",
      ])
    XCTAssertEqual(auth.givenName, "")
    XCTAssertEqual(auth.familyName, "")
    auth.givenName = "Bob"
    auth.familyName = "Owner B"
    XCTAssertEqual(auth.givenName, "Bob")
    XCTAssertEqual(auth.familyName, "Owner B")
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
        resetOnboardingProjection: { effects("projectionReset") },
        clearLocalNameProjection: {
          effects("localNameCleared")
          AuthService.shared.givenName = ""
          AuthService.shared.familyName = ""
        }))
  }
}
