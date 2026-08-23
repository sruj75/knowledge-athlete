@preconcurrency import UserNotifications
import XCTest

@testable import Omi_Computer

private actor TasksStorePauseGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var entered = false

  func pause() async {
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class TasksStoreNoopReminderNotifications: TaskReminderNotificationBoundary {
  func add(_ request: UNNotificationRequest) async -> UserNotificationDeliveryResult {
    UserNotificationDeliveryResult(errorDescription: nil)
  }

  func pendingRequestIdentifiers() async -> [String] { [] }

  func removePendingRequests(withIdentifiers identifiers: [String]) {}
}

@MainActor
final class TasksStoreOwnerBoundaryTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?
  private var store: TasksStore!

  override func setUp() async throws {
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "tasks-store-owner")
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    self.ownerFixture = ownerFixture
    await ownerFixture.establish(authOwnerID: fixture?.testUserId)
    store = TasksStore(
      reminderService: TaskReminderService(notifications: TasksStoreNoopReminderNotifications()),
      observesNotifications: false)
    store.resetSessionState()
  }

  override func tearDown() async throws {
    store?.resetSessionState()
    store = nil
    await ownerFixture?.restore()
    ownerFixture = nil
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
  }

  func testLocalPagingStartsAt100AndUsesIndependentOffsets() async throws {
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    for index in 0..<101 {
      _ = try await ActionItemStorage.shared.insertLocalActionItem(
        ActionItemRecord(description: "To do \(index)", source: "manual"),
        authorization: .unrestricted
      )
      _ = try await ActionItemStorage.shared.insertLocalActionItem(
        ActionItemRecord(description: "Done \(index)", completed: true, source: "manual"),
        authorization: .unrestricted
      )
    }

    await store.loadIncompleteTasks(expectedOwnerID: ownerID)
    await store.loadCompletedTasks(expectedOwnerID: ownerID)
    XCTAssertEqual(store.incompleteTasks.count, 100)
    XCTAssertEqual(store.completedTasks.count, 100)
    XCTAssertTrue(store.hasMoreIncompleteTasks)
    XCTAssertTrue(store.hasMoreCompletedTasks)

    await store.loadMoreIncompleteIfNeeded(
      currentTask: try XCTUnwrap(store.incompleteTasks.last),
      expectedOwnerID: ownerID
    )
    XCTAssertEqual(store.incompleteTasks.count, 101)
    XCTAssertEqual(store.completedTasks.count, 100)
    XCTAssertFalse(store.hasMoreIncompleteTasks)
    XCTAssertTrue(store.hasMoreCompletedTasks)
  }

  func testOwnerChangeDuringMutationFailsClosedBeforeCommit() async throws {
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let createdTask = await store.createTask(
      description: "Owner A task",
      dueAt: nil,
      priority: nil,
      expectedOwnerID: ownerID
    )
    let task = try XCTUnwrap(createdTask)

    let accepted = await store.toggleTask(
      task,
      expectedOwnerID: ownerID,
      beforeLocalMutation: { [ownerFixture] in
        await ownerFixture?.establish(authOwnerID: "replacement-owner")
      }
    )

    XCTAssertFalse(accepted)
    let stored = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: task.id)
    XCTAssertEqual(stored?.completed, false)
  }

  func testExplicitStaleAuthorizationRejectsVoiceCreateAndUpdate() async throws {
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let staleSnapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let stored = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(description: "Retained task", source: "voice"),
      authorization: .unrestricted)
    let task = stored.toTaskActionItem()

    await ownerFixture?.establish(authOwnerID: nil)
    await ownerFixture?.establish(authOwnerID: ownerID)

    let created = await store.createTask(
      description: "Stale voice create",
      dueAt: nil,
      priority: nil,
      expectedOwnerID: ownerID,
      authorizationSnapshot: staleSnapshot)
    XCTAssertNil(created)

    let updated = await store.updateTask(
      task,
      description: "Stale voice update",
      expectedOwnerID: ownerID,
      authorizationSnapshot: staleSnapshot)
    XCTAssertFalse(updated)
    let unchanged = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: task.id)
    XCTAssertEqual(unchanged?.description, "Retained task")
  }

  func testPausedDashboardReadCannotPublishAfterOwnerChanges() async throws {
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let original = task(id: "local_10")
    let stale = task(id: "local_11")
    store.overdueTasks = [original]
    let gate = TasksStorePauseGate()

    let refresh = Task { @MainActor in
      await store.loadDashboardTasks(
        expectedOwnerID: ownerID,
        loader: { _ in
          await gate.pause()
          return TasksStore.DashboardTaskSnapshot(
            overdue: [stale], today: [stale], noDueDate: [stale])
        }
      )
    }
    await gate.waitUntilEntered()
    await ownerFixture?.establish(authOwnerID: "replacement-owner")
    await gate.release()
    await refresh.value

    XCTAssertEqual(store.overdueTasks.map(\.id), [original.id])
  }

  func testStaticTripwireStoreContainsNoRetiredTaskTransport() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/Stores/TasksStore.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    for retired in [
      "refreshTasksFromServer", "retryUnsynced", "backendId", "syncTaskActionItems",
      "reconcileWithAPI", "markSynced",
    ] {
      XCTAssertFalse(source.contains(retired), "retired transport residue: \(retired)")
    }

  }

  private func task(id: String) -> TaskActionItem {
    TaskActionItem(
      id: id,
      description: id,
      completed: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }
}
