import XCTest

@testable import Omi_Computer

@MainActor
final class Wave2OwnerPublicationFenceTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    ownerFixture = fixture
    await fixture.establish(authOwnerID: "wave2-publication-owner")
  }

  override func tearDown() async throws {
    AssistantCoordinator.shared.setEventCallback(nil)
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
  }

  func testRewindRejectsStaleSearchPublicationAfterSameUIDReauthentication() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let viewModel = RewindViewModel()
    let retained = Screenshot(id: 1, appName: "Retained")
    viewModel.screenshots = [retained]
    let staleSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "wave2-publication-owner")

    XCTAssertFalse(
      viewModel.publishSearchResults(
        [Screenshot(id: 2, appName: "Stale")],
        authorizationSnapshot: staleSnapshot))
    XCTAssertEqual(viewModel.screenshots, [retained])
  }

  func testMemorySemanticReadRequiresTheOriginalOwnerGeneration() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let staleSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "wave2-publication-owner")

    do {
      _ = try await MemoryStorage.shared.semanticMatches(
        queryVector: [1],
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale memory recall must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
  }

  func testOwnerlessCaptureCannotRepopulateCoordinatorTrackingDuringTransition() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    AssistantCoordinator.shared.trackFrame(
      CapturedFrame(
        jpegData: Data([0x0A]),
        appName: "Safari",
        frameNumber: 1),
      authorizationSnapshot: authorizationSnapshot)
    XCTAssertNotNil(AssistantCoordinator.shared.trackedFrameAuthorizationForTests)

    await fixture.establish(authOwnerID: nil)
    await AssistantCoordinator.shared.resetForOwnerChange()
    AssistantCoordinator.shared.trackFrame(
      CapturedFrame(
        jpegData: Data([0x0B]),
        appName: "Notes",
        frameNumber: 2),
      authorizationSnapshot: authorizationSnapshot)

    XCTAssertNil(AssistantCoordinator.shared.trackedFrameAuthorizationForTests)
  }

  func testOwnerResetClearsPluginDebounceFrameBeforeReplacementOwnerIsVisible() async throws {
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let plugin = ProactiveAssistantsPlugin.shared
    plugin.stageDistributionForTests(
      OwnerBoundCapturedFrame(
        frame: CapturedFrame(
          jpegData: Data([0x0C]),
          appName: "Mail",
          frameNumber: 3),
        authorizationSnapshot: authorizationSnapshot))
    plugin.stageAnalysisDelayForTests(
      authorizationSnapshot: authorizationSnapshot)
    XCTAssertEqual(
      plugin.pendingDistributionAuthorizationForTests,
      authorizationSnapshot)

    await AssistantCoordinator.shared.resetForOwnerChange()

    XCTAssertNil(plugin.pendingDistributionAuthorizationForTests)
    XCTAssertFalse(plugin.hasAnalysisDelayTimerForTests)
    XCTAssertNil(FocusStorage.shared.delayEndTime)
  }

  func testSuggestionGroundingReadsRejectAStaleGenerationAtTheirStorageBoundaries() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let staleSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "wave2-publication-owner")

    do {
      _ = try await ActionItemStorage.shared.searchFTS(
        query: "retained",
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale task grounding must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }

    do {
      _ = try await MemoryStorage.shared.literalSearch(
        "retained",
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale memory grounding must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
  }

  func testTaskContextReadsRejectAStaleGenerationAtEveryStorageBoundary() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let staleSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "wave2-publication-owner")

    do {
      _ = try await ActionItemStorage.shared.getRecentActiveTasks(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale active-task context must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await ActionItemStorage.shared.getRecentCompletedTasks(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale completed-task context must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await ActionItemStorage.shared.getRecentDeletedTasks(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale deleted-task context must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await ActionItemStorage.shared.getActionItem(
        id: 1,
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale task hydration must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await ActionItemStorage.shared.getLocalActionItems(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale Focus task context must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await MemoryStorage.shared.list(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale Focus and Insight memory context must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await GoalStorage.shared.getLocalGoals(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale goal context must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
  }

  func testQueuedAssistantEventChecksAuthorizationAtActualCallbackBoundary() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let staleSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    var delivered = false
    AssistantCoordinator.shared.setEventCallback { _, _ in delivered = true }

    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "wave2-publication-owner")
    AssistantCoordinator.shared.sendEvent(
      type: "memoryExtracted",
      data: [:],
      authorizationSnapshot: staleSnapshot)

    XCTAssertFalse(delivered)
  }

  func testSuggestionRejectsLateResultFromPreviousSameUIDGeneration() async throws {
    let fixture = try XCTUnwrap(ownerFixture)
    let assistant = try SuggestionAssistant(apiKey: "test-key")
    let staleSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let result = SuggestionResult(
      hasSuggestion: true,
      suggestion: ExtractedSuggestion(
        suggestion: "Review the retained task",
        reasoning: "A prior commitment is due",
        category: .commitment,
        confidence: 1),
      contextSummary: "Reviewing work",
      currentActivity: "Working",
      telemetryIdentity: nil)

    await fixture.establish(authOwnerID: nil)
    await fixture.establish(authOwnerID: "wave2-publication-owner")
    await assistant.handleResult(
      result,
      authorizationSnapshot: staleSnapshot,
      sendEvent: { _, _ in })

    let recentSuggestionsCount = await assistant.recentSuggestionsCount
    XCTAssertEqual(recentSuggestionsCount, 0)
  }

  func testSuggestionOwnerResetClearsEvaluationBudget() async throws {
    let assistant = try SuggestionAssistant(apiKey: "test-key")
    let now = Date()
    await assistant.recordEvaluationForTests(now: now)
    let beforeReset = await assistant.evaluationsTodayForTests(now: now)
    XCTAssertEqual(beforeReset, 1)

    await assistant.resetForOwnerChange()

    let afterReset = await assistant.evaluationsTodayForTests(now: now)
    XCTAssertEqual(afterReset, 0)
  }
}
