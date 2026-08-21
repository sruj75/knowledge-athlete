import Foundation
@preconcurrency import UserNotifications
import XCTest

@testable import Omi_Computer

@MainActor
private final class FakeTaskReminderNotifications: TaskReminderNotificationBoundary {
  var requests: [String: UNNotificationRequest] = [:]
  var removedBatches: [[String]] = []
  var addError: String?
  var addGate: TaskReminderAddGate?

  func add(_ request: UNNotificationRequest) async -> UserNotificationDeliveryResult {
    if let addGate { await addGate.enterAndWait() }
    if addError == nil { requests[request.identifier] = request }
    return UserNotificationDeliveryResult(errorDescription: addError)
  }

  func pendingRequestIdentifiers() async -> [String] {
    Array(requests.keys)
  }

  func removePendingRequests(withIdentifiers identifiers: [String]) {
    guard !identifiers.isEmpty else { return }
    removedBatches.append(identifiers)
    for identifier in identifiers { requests.removeValue(forKey: identifier) }
  }

  func seed(identifier: String) {
    requests[identifier] = UNNotificationRequest(
      identifier: identifier,
      content: UNMutableNotificationContent(),
      trigger: nil
    )
  }
}

@MainActor
final class TaskReminderServiceTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private var fixture: RewindStorageTestIsolation.Fixture?
  private var authSnapshot: RewindStorageTestIsolation.AuthSnapshot?
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    authSnapshot = RewindStorageTestIsolation.captureAuthSnapshot()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "task-reminder")
    RewindStorageTestIsolation.signInForTests(userId: try XCTUnwrap(fixture?.testUserId))
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    self.ownerFixture = ownerFixture
    await ownerFixture.establish(authOwnerID: try XCTUnwrap(fixture?.testUserId))
  }

  override func tearDown() async throws {
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
    if let authSnapshot { RewindStorageTestIsolation.restoreAuthSnapshot(authSnapshot) }
    authSnapshot = nil
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
  }

  func testOwnerReconcileRemovesStaleRequestsAndSchedulesOnlyAuthoritativeFutureTasks() async throws {
    let notifications = FakeTaskReminderNotifications()
    let service = TaskReminderService(notifications: notifications, now: { self.now })
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID))
    let wantedID = TaskReminderService.requestIdentifier(ownerID: ownerID, taskID: "local_7")
    let staleSameOwner = TaskReminderService.requestIdentifier(ownerID: ownerID, taskID: "local_8")
    let staleOtherOwner = TaskReminderService.requestIdentifier(ownerID: "owner-b", taskID: "local_9")
    notifications.seed(identifier: staleSameOwner)
    notifications.seed(identifier: staleOtherOwner)
    notifications.seed(identifier: "unrelated.notification")

    let result = await service.reconcile(
      tasks: [
        task(id: "local_7", dueAt: now.addingTimeInterval(3_600)),
        task(id: "local_10", dueAt: now.addingTimeInterval(-1)),
        task(id: "local_11", completed: true, dueAt: now.addingTimeInterval(3_600)),
      ],
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot,
      removeOtherOwners: true
    )

    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(Set(notifications.requests.keys), Set([wantedID, "unrelated.notification"]))
    let request = notifications.requests[wantedID]
    XCTAssertEqual(request?.content.title, "Task due")
    XCTAssertEqual(request?.content.body, "Task local_7")
    XCTAssertEqual(request?.content.userInfo["task_id"] as? String, "local_7")
    XCTAssertFalse(wantedID.contains(ownerID))
  }

  func testCompletionDeadlineRemovalAndDeleteCancelExactLocalIdentifier() async throws {
    let notifications = FakeTaskReminderNotifications()
    let service = TaskReminderService(notifications: notifications, now: { self.now })
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID))
    let identifier = TaskReminderService.requestIdentifier(ownerID: ownerID, taskID: "local_4")
    notifications.seed(identifier: identifier)

    let completed = await service.schedule(
      task: task(id: "local_4", completed: true, dueAt: now.addingTimeInterval(100)),
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot
    )
    XCTAssertTrue(completed.succeeded)
    XCTAssertNil(notifications.requests[identifier])

    notifications.seed(identifier: identifier)
    let noDeadline = await service.schedule(
      task: task(id: "local_4", dueAt: nil),
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot)
    XCTAssertTrue(noDeadline.succeeded)
    XCTAssertNil(notifications.requests[identifier])

    notifications.seed(identifier: identifier)
    await service.cancel(
      taskID: "local_4",
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot)
    XCTAssertNil(notifications.requests[identifier])
  }

  func testSchedulingFailureIsReminderSpecific() async throws {
    let notifications = FakeTaskReminderNotifications()
    notifications.addError = "notifications denied"
    let service = TaskReminderService(notifications: notifications, now: { self.now })

    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID))
    let result = await service.schedule(
      task: task(id: "local_12", dueAt: now.addingTimeInterval(60)),
      ownerID: ownerID,
      authorizationSnapshot: authorizationSnapshot
    )

    XCTAssertEqual(result.errorDescription, "notifications denied")
  }

  func testSchedulingFailureLeavesTaskCommittedAndPublishesSeparateWarning() async throws {
    let notifications = FakeTaskReminderNotifications()
    notifications.addError = "notifications denied"
    let service = TaskReminderService(notifications: notifications, now: { self.now })
    let store = TasksStore(reminderService: service, observesNotifications: false)
    let ownerID = try XCTUnwrap(fixture?.testUserId)

    let created = await store.createTask(
      description: "Committed without reminder",
      dueAt: now.addingTimeInterval(300),
      priority: "High",
      expectedOwnerID: ownerID
    )

    let task = try XCTUnwrap(created)
    XCTAssertEqual(store.reminderError, "notifications denied")
    let persisted = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: task.id)
    XCTAssertEqual(persisted?.description, "Committed without reminder")
  }

  func testSuspendedAddCannotDeleteSameUIDReplacementReminder() async throws {
    let ownerFixture = try XCTUnwrap(ownerFixture)
    let notifications = FakeTaskReminderNotifications()
    let gate = TaskReminderAddGate()
    notifications.addGate = gate
    let service = TaskReminderService(notifications: notifications, now: { self.now })
    let ownerID = try XCTUnwrap(fixture?.testUserId)
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID))
    let scheduledTask = task(
      id: "local_77",
      description: "Old generation reminder",
      dueAt: now.addingTimeInterval(300))
    let identifier = TaskReminderService.requestIdentifier(ownerID: ownerID, taskID: scheduledTask.id)

    let scheduling = Task {
      await service.schedule(
        task: scheduledTask,
        ownerID: ownerID,
        authorizationSnapshot: authorizationSnapshot)
    }
    await gate.waitUntilEntered()
    let transition = Task {
      await ownerFixture.establish(authOwnerID: nil)
      await ownerFixture.establish(authOwnerID: ownerID)
    }
    await EffectiveOwnerTransitionFence.shared.waitUntilTransitionIsPending()
    await gate.release()
    _ = await scheduling.value
    await transition.value

    let replacementSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID))
    let replacement = task(
      id: "local_77",
      description: "Replacement generation reminder",
      dueAt: now.addingTimeInterval(600))
    _ = await service.schedule(
      task: replacement,
      ownerID: ownerID,
      authorizationSnapshot: replacementSnapshot)

    XCTAssertEqual(
      notifications.requests[identifier]?.content.body,
      "Replacement generation reminder")
    XCTAssertEqual(
      notifications.removedBatches.filter { $0 == [identifier] }.count,
      2)
  }

  private func task(
    id: String,
    description: String? = nil,
    completed: Bool = false,
    dueAt: Date?
  ) -> TaskActionItem {
    TaskActionItem(
      id: id,
      description: description ?? "Task \(id)",
      completed: completed,
      createdAt: now.addingTimeInterval(-100),
      dueAt: dueAt,
      deleted: false
    )
  }
}

private actor TaskReminderAddGate {
  private var entered = false
  private var released = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func enterAndWait() async {
    entered = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if !released {
      await withCheckedContinuation { releaseWaiters.append($0) }
    }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }

  func release() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
