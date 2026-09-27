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
    do {
      _ = try await ActionItemStorage.shared.getFilteredActionItems(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale voice task listing must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await ActionItemStorage.shared.getLocalActionItem(
        surfacedId: "local_1",
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale voice task hydration must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
    do {
      _ = try await MemoryStorage.shared.listForTool(
        authorizationSnapshot: staleSnapshot)
      XCTFail("stale voice memory listing must be revoked")
    } catch {
      XCTAssertTrue(error is LocalMutationAuthorizationError)
    }
  }

}
