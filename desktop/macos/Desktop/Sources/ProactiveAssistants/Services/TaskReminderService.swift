import CryptoKit
import Foundation
import OmiSupport
@preconcurrency import UserNotifications

struct TaskReminderResult: Equatable, Sendable {
  let errorDescription: String?
  var succeeded: Bool { errorDescription == nil }
}

@MainActor
protocol TaskReminderNotificationBoundary: AnyObject {
  func add(_ request: UNNotificationRequest) async -> UserNotificationDeliveryResult
  func pendingRequestIdentifiers() async -> [String]
  func removePendingRequests(withIdentifiers identifiers: [String])
}

@MainActor
final class LiveTaskReminderNotificationBoundary: TaskReminderNotificationBoundary {
  func add(_ request: UNNotificationRequest) async -> UserNotificationDeliveryResult {
    await withCheckedContinuation { continuation in
      UserNotificationCallbackBridge.add(request) { result in
        continuation.resume(returning: result)
      }
    }
  }

  func pendingRequestIdentifiers() async -> [String] {
    await withCheckedContinuation { continuation in
      UserNotificationCallbackBridge.pendingRequests { requests in
        continuation.resume(returning: requests.map(\.identifier))
      }
    }
  }

  func removePendingRequests(withIdentifiers identifiers: [String]) {
    UserNotificationCallbackBridge.removePendingRequests(withIdentifiers: identifiers)
  }
}

/// Idempotent derived-state owner for task due reminders. Task rows commit
/// first; notification failure never rolls database state back.
@MainActor
final class TaskReminderService {
  static let shared = TaskReminderService()

  private static let namespace = "omi.task-reminder."
  private let notifications: TaskReminderNotificationBoundary
  private let now: () -> Date

  init(
    notifications: TaskReminderNotificationBoundary = LiveTaskReminderNotificationBoundary(),
    now: @escaping () -> Date = Date.init
  ) {
    self.notifications = notifications
    self.now = now
  }

  static func requestIdentifier(ownerID: String, taskID: String) -> String {
    let digest = SHA256.hash(data: Data(ownerID.utf8))
      .prefix(12)
      .map { String(format: "%02x", $0) }
      .joined()
    return "\(namespace)\(digest).\(taskID)"
  }

  func reconcile(
    tasks: [TaskActionItem],
    ownerID: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    removeOtherOwners: Bool = false
  ) async -> TaskReminderResult {
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
      return TaskReminderResult(errorDescription: nil)
    }
    let currentTime = now()
    let desired = Dictionary(
      lastWriteWins: tasks.compactMap { task -> (String, TaskActionItem)? in
        guard !task.completed, task.deleted != true, let dueAt = task.dueAt, dueAt > currentTime else { return nil }
        return (Self.requestIdentifier(ownerID: ownerID, taskID: task.id), task)
      })
    let prefix = Self.ownerPrefix(ownerID: ownerID)
    let pending = await notifications.pendingRequestIdentifiers()
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
      return TaskReminderResult(errorDescription: nil)
    }
    let stale = pending.filter { identifier in
      guard identifier.hasPrefix(Self.namespace) else { return false }
      return removeOtherOwners || (identifier.hasPrefix(prefix) && desired[identifier] == nil)
    }
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
      return TaskReminderResult(errorDescription: nil)
    }
    notifications.removePendingRequests(withIdentifiers: stale)

    for (identifier, task) in desired {
      guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
        return TaskReminderResult(errorDescription: nil)
      }
      guard let dueAt = task.dueAt else { continue }
      let result = await schedule(
        task: task,
        ownerID: ownerID,
        dueAt: dueAt,
        identifier: identifier,
        authorizationSnapshot: authorizationSnapshot)
      if !result.succeeded { return result }
    }
    return TaskReminderResult(errorDescription: nil)
  }

  func schedule(
    task: TaskActionItem,
    ownerID: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> TaskReminderResult {
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
      return TaskReminderResult(errorDescription: nil)
    }
    guard !task.completed, task.deleted != true, let dueAt = task.dueAt, dueAt > now() else {
      cancel(
        taskID: task.id,
        ownerID: ownerID,
        authorizationSnapshot: authorizationSnapshot)
      return TaskReminderResult(errorDescription: nil)
    }
    return await schedule(
      task: task,
      ownerID: ownerID,
      dueAt: dueAt,
      identifier: Self.requestIdentifier(ownerID: ownerID, taskID: task.id),
      authorizationSnapshot: authorizationSnapshot
    )
  }

  func cancel(
    taskID: String,
    ownerID: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else { return }
    notifications.removePendingRequests(
      withIdentifiers: [Self.requestIdentifier(ownerID: ownerID, taskID: taskID)]
    )
  }

  func removeAllTaskRemindersWhileSignedOut() async {
    guard RuntimeOwnerIdentity.currentOwnerId() == nil else { return }
    let identifiers = await notifications.pendingRequestIdentifiers()
      .filter { $0.hasPrefix(Self.namespace) }
    guard RuntimeOwnerIdentity.currentOwnerId() == nil else { return }
    notifications.removePendingRequests(withIdentifiers: identifiers)
  }

  private static func ownerPrefix(ownerID: String) -> String {
    let sample = requestIdentifier(ownerID: ownerID, taskID: "")
    return sample
  }

  private func schedule(
    task: TaskActionItem,
    ownerID: String,
    dueAt: Date,
    identifier: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async -> TaskReminderResult {
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
      return TaskReminderResult(errorDescription: nil)
    }
    notifications.removePendingRequests(withIdentifiers: [identifier])
    let content = UNMutableNotificationContent()
    content.title = "Task due"
    content.body = task.description
    content.sound = .default
    content.userInfo = ["task_id": task.id]
    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: dueAt
    )
    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    )
    let result = await notifications.add(request)
    guard isAuthorized(authorizationSnapshot, ownerID: ownerID) else {
      // The add may have crossed an account transition. Remove only the exact
      // stale request that just completed; never sweep the replacement owner.
      notifications.removePendingRequests(withIdentifiers: [identifier])
      return TaskReminderResult(errorDescription: nil)
    }
    return TaskReminderResult(errorDescription: result.errorDescription)
  }

  private func isAuthorized(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    ownerID: String
  ) -> Bool {
    authorizationSnapshot.ownerID == ownerID
      && RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
  }
}
