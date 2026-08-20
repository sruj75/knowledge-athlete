import XCTest

@testable import Omi_Computer

private actor ProfileTextRequestRecorder {
  private(set) var prompts: [String] = []

  func send(prompt: String, systemPrompt: String) -> String {
    prompts.append(prompt)
    return prompts.count == 1 ? "- Stage one fact" : "- Consolidated first profile"
  }
}

private actor PausingProfileTextRequest {
  private var callCount = 0
  private var secondStageStarted = false
  private var secondStageWaiters: [CheckedContinuation<Void, Never>] = []
  private var secondStageRelease: CheckedContinuation<Void, Never>?

  func send(prompt: String, systemPrompt: String) async -> String {
    callCount += 1
    guard callCount == 2 else { return "- Stage one fact" }
    secondStageStarted = true
    let waiters = secondStageWaiters
    secondStageWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { secondStageRelease = $0 }
    return "- Stale owner profile"
  }

  func waitUntilSecondStageStarts() async {
    guard !secondStageStarted else { return }
    await withCheckedContinuation { secondStageWaiters.append($0) }
  }

  func releaseSecondStage() {
    secondStageRelease?.resume()
    secondStageRelease = nil
  }
}

private actor ProfileRequestDispatchCounter {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

@MainActor
final class AIUserProfileLocalAuthorityTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?
  private var authSnapshot: RewindStorageTestIsolation.AuthSnapshot?
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func setUp() async throws {
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "ai-profile-local-authority")
    authSnapshot = RewindStorageTestIsolation.captureAuthSnapshot()
    RewindStorageTestIsolation.signInForTests(userId: try XCTUnwrap(fixture?.testUserId))
    await ownerFixture.establish(authOwnerID: try XCTUnwrap(fixture?.testUserId))
  }

  override func tearDown() async throws {
    await ownerFixture.restore()
    if let authSnapshot {
      RewindStorageTestIsolation.restoreAuthSnapshot(authSnapshot)
    }
    await AIUserProfileService.shared.invalidateCache()
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    authSnapshot = nil
  }

  func testInputAndHistoryBoundsAreExplicit() {
    XCTAssertEqual(AIUserProfileInputPolicy.memoryLimit, 100)
    XCTAssertEqual(AIUserProfileInputPolicy.taskLimit, 50)
    XCTAssertEqual(AIUserProfileInputPolicy.conversationLimit, 20)
    XCTAssertEqual(AIUserProfileInputPolicy.conversationLookbackDays, 7)
    XCTAssertEqual(AIUserProfileInputPolicy.journalMessageLimit, 30)
    XCTAssertEqual(AIUserProfileInputPolicy.priorProfileLimit, 5)
    XCTAssertEqual(AIUserProfileInputPolicy.settingsHistoryLimit, 30)
    XCTAssertEqual(AIUserProfileInputPolicy.conversationQuery().statuses, [.completed])
  }

  func testFirstProfileStillRunsBothGeminiStages() async throws {
    let recorder = ProfileTextRequestRecorder()
    let service = AIUserProfileService(
      textRequest: { prompt, systemPrompt, _ in
        await recorder.send(prompt: prompt, systemPrompt: systemPrompt)
      },
      dataSourceLoader: { _ in
        AIUserProfileInputs(
          memories: ["[interesting] Local evidence"],
          tasks: [],
          goals: [],
          conversations: [],
          journalMessages: [])
      })

    let profile = try await service.generateProfile()
    let prompts = await recorder.prompts

    XCTAssertEqual(prompts.count, 2)
    XCTAssertTrue(prompts[1].contains("=== NEW PROFILE"))
    XCTAssertEqual(profile.profileText, "- Consolidated first profile")
  }

  func testOwnerSwitchDuringSecondStageDropsProfileBeforeCommit() async throws {
    let pausingRequest = PausingProfileTextRequest()
    let service = AIUserProfileService(
      textRequest: { prompt, systemPrompt, _ in
        await pausingRequest.send(prompt: prompt, systemPrompt: systemPrompt)
      },
      dataSourceLoader: { _ in
        AIUserProfileInputs(
          memories: ["[interesting] Owner A evidence"],
          tasks: [],
          goals: [],
          conversations: [],
          journalMessages: [])
      })
    let generation = Task { try await service.generateProfile() }
    await pausingRequest.waitUntilSecondStageStarts()

    await ownerFixture.establish(authOwnerID: "ai-profile-owner-b")
    await pausingRequest.releaseSecondStage()

    do {
      _ = try await generation.value
      XCTFail("owner-A generation unexpectedly published after the owner switch")
    } catch {
      XCTAssertEqual(error as? LocalMutationAuthorizationError, .revoked)
    }

    await ownerFixture.establish(authOwnerID: try XCTUnwrap(fixture?.testUserId))
    let profiles = await service.getAllProfiles()
    XCTAssertTrue(profiles.isEmpty)
  }

  func testRevokedSameUIDSnapshotCannotDispatchProfileTextRequest() async throws {
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    await ownerFixture.establish(authOwnerID: try XCTUnwrap(fixture?.testUserId))
    let dispatchCounter = ProfileRequestDispatchCounter()

    do {
      _ = try await AIUserProfileService.performAuthorizedTextRequest(
        authorizationSnapshot: staleSnapshot
      ) {
        await dispatchCounter.record()
        return "owner-private-profile"
      }
      XCTFail("revoked authorization unexpectedly dispatched a Gemini request")
    } catch {
      XCTAssertEqual(error as? LocalMutationAuthorizationError, .revoked)
    }

    let dispatchCount = await dispatchCounter.count
    XCTAssertEqual(dispatchCount, 0)
  }

  func testExplorationEditRestartHistoryAndDeleteStayInLocalProfileTable() async throws {
    let didSave = await AIUserProfileService.shared.saveExplorationAsProfile(text: "- User explores local files.")
    XCTAssertTrue(didSave)
    let maybeSaved = await AIUserProfileService.shared.getLatestProfile()
    let saved = try XCTUnwrap(maybeSaved)
    let savedID = try XCTUnwrap(saved.id)

    let didUpdate = await AIUserProfileService.shared.updateProfileText(
      id: savedID,
      newText: "- User explores local files with Finder.")
    XCTAssertTrue(didUpdate)
    await AIUserProfileService.shared.invalidateCache()

    let maybeAfterRestart = await AIUserProfileService.shared.getLatestProfile()
    let afterRestart = try XCTUnwrap(maybeAfterRestart)
    XCTAssertEqual(afterRestart.id, savedID)
    XCTAssertEqual(afterRestart.profileText, "- User explores local files with Finder.")
    let history = await AIUserProfileService.shared.getAllProfiles()
    XCTAssertEqual(history.count, 1)

    let nextProfile = await AIUserProfileService.shared.deleteProfile(id: savedID)
    XCTAssertNil(nextProfile)
    let afterDelete = await AIUserProfileService.shared.getAllProfiles()
    XCTAssertTrue(afterDelete.isEmpty)
  }
}
