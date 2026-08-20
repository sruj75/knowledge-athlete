import XCTest

@testable import Omi_Computer

final class GoalProgressTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "simple-local-goals")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testSimpleGoalLifecycleIsLocalAndDurable() async throws {
    let created = try await GoalStorage.shared.createGoal(
      title: "  Learn piano  ",
      description: "  Practice every day  ",
      authorization: .unrestricted
    )
    XCTAssertTrue(created.id.hasPrefix("local_"))
    XCTAssertEqual(created.title, "Learn piano")
    XCTAssertEqual(created.description, "Practice every day")
    XCTAssertTrue(created.isActive)
    XCTAssertNil(created.completedAt)

    let edited = try await GoalStorage.shared.updateGoal(
      surfacedID: created.id,
      title: "Learn jazz piano",
      description: "",
      authorization: .unrestricted
    )
    XCTAssertEqual(edited.id, created.id)
    XCTAssertNil(edited.description)

    let completed = try await GoalStorage.shared.setCompleted(
      surfacedID: created.id,
      completed: true,
      authorization: .unrestricted
    )
    XCTAssertEqual(completed.id, created.id)
    XCTAssertFalse(completed.isActive)
    XCTAssertNotNil(completed.completedAt)
    let activeGoals = try await GoalStorage.shared.getLocalGoals()
    XCTAssertTrue(activeGoals.isEmpty)

    await GoalStorage.shared.invalidateCache()
    let persisted = try await GoalStorage.shared.getLocalGoals(activeOnly: false)
    XCTAssertEqual(persisted.map(\.id), [created.id])
    XCTAssertEqual(persisted.first?.title, "Learn jazz piano")
    XCTAssertFalse(try XCTUnwrap(persisted.first).isActive)
  }

  func testGoalOwnerIsolationAndExportPaging() async throws {
    let ownerAGoal = try await GoalStorage.shared.createGoal(
      title: "Owner A",
      description: nil,
      authorization: .unrestricted
    )
    let ownerAExport = try await GoalStorage.shared.getLocalExportPage(limit: 1)
    XCTAssertEqual(ownerAExport.map(\.id), [ownerAGoal.id])

    let ownerB = "simple-local-goals-b-\(UUID().uuidString)"
    let ownerBDirectory = RewindStorageTestIsolation.userDirectory(for: ownerB)
    defer { try? FileManager.default.removeItem(at: ownerBDirectory) }
    try await RewindDatabase.shared.switchUser(to: ownerB)
    await GoalStorage.shared.invalidateCache()

    let ownerBGoals = try await GoalStorage.shared.getLocalGoals(activeOnly: false)
    XCTAssertTrue(ownerBGoals.isEmpty)
  }

  @MainActor
  func testDashboardDropsGoalReadAfterOwnerGenerationChanges() async throws {
    let authSnapshot = RewindStorageTestIsolation.captureAuthSnapshot()
    defer { RewindStorageTestIsolation.restoreAuthSnapshot(authSnapshot) }
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    RewindStorageTestIsolation.signInForTests(userId: ownerID)

    let goal = LocalGoal(
      id: "local_1",
      rowID: 1,
      title: "Previous owner goal",
      description: nil,
      isActive: true,
      completedAt: nil,
      createdAt: Date(),
      updatedAt: Date()
    )
    let gate = DashboardGoalLoaderGate()
    let viewModel = DashboardViewModel(goalLoader: {
      await gate.load([goal])
    })
    let load = Task { @MainActor in await viewModel.loadCachedDashboardData() }
    await gate.waitUntilEntered()
    viewModel.resetSessionState()
    await gate.release()
    await load.value

    XCTAssertTrue(viewModel.goals.isEmpty)
  }
}

private actor DashboardGoalLoaderGate {
  private var entered = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func load(_ goals: [LocalGoal]) async -> [LocalGoal] {
    entered = true
    enteredWaiters.forEach { $0.resume() }
    enteredWaiters = []
    await withCheckedContinuation { releaseWaiters.append($0) }
    return goals
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func release() {
    releaseWaiters.forEach { $0.resume() }
    releaseWaiters = []
  }
}
