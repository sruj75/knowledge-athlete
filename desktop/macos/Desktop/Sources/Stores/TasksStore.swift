import Combine
import SwiftUI

/// Sendable carrier kept for the few non-task API surfaces that still accept
/// arbitrary metadata. Tasks themselves no longer persist generic metadata.
struct ActionItemMetadataBox: @unchecked Sendable {
  let value: [String: Any]?
  init(_ value: [String: Any]?) { self.value = value }
}

/// Observable projection of the current owner's local task database.
///
/// `ActionItemStorage` is the sole authority. This store never fetches, merges,
/// retries, reconciles, or rolls back against a server representation.
@MainActor
final class TasksStore: ObservableObject {
  static let shared = TasksStore()

  struct DashboardTaskSnapshot {
    let overdue: [TaskActionItem]
    let today: [TaskActionItem]
    let noDueDate: [TaskActionItem]
  }

  typealias DashboardTaskLoader = () async throws -> DashboardTaskSnapshot

  @Published var incompleteTasks: [TaskActionItem] = []
  @Published var completedTasks: [TaskActionItem] = []
  @Published var deletedTasks: [TaskActionItem] = []
  @Published var overdueTasks: [TaskActionItem] = []
  @Published var todaysTasks: [TaskActionItem] = []
  @Published var tasksWithoutDueDate: [TaskActionItem] = []

  @Published var isLoadingIncomplete = false
  @Published var isLoadingCompleted = false
  @Published var isLoadingDeleted = false
  @Published var isLoadingMore = false
  @Published var hasMoreIncompleteTasks = true
  @Published var hasMoreCompletedTasks = true
  @Published var hasMoreDeletedTasks = false
  @Published var error: String?
  @Published private(set) var incompleteError: String?
  @Published private(set) var completedError: String?
  @Published private(set) var reminderError: String?

  private(set) var refreshInvocations = 0
  private(set) var hasScheduledStartupMaintenance = false

  var tasks: [TaskActionItem] { incompleteTasks + completedTasks }
  var isLoading: Bool { isLoadingIncomplete || isLoadingCompleted || isLoadingDeleted }
  var hasLoadedIncompleteTasks: Bool { hasLoadedIncomplete }
  var hasLoadedCompletedTasks: Bool { hasLoadedCompleted }
  var todoCount: Int { incompleteTasks.count }
  var doneCount: Int { completedTasks.count }
  var deletedCount: Int { deletedTasks.count }

  var isActive = false {
    didSet {
      guard isActive, !oldValue else { return }
      refreshInvocations += 1
      Task { @MainActor [weak self] in await self?.refreshTasksIfNeeded() }
    }
  }

  private let pageSize = 100
  private var incompleteOffset = 0
  private var completedOffset = 0
  private var hasLoadedIncomplete = false
  private var hasLoadedCompleted = false
  private var ownerOperationGeneration: UInt64 = 0
  private var cancellables = Set<AnyCancellable>()
  private let reminderService: TaskReminderService

  private struct OwnerLease: Sendable {
    let authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
    let generation: UInt64
    var ownerID: String { authorizationSnapshot.ownerID }
  }

  init(
    reminderService: TaskReminderService = .shared,
    observesNotifications: Bool = true
  ) {
    self.reminderService = reminderService
    guard observesNotifications else { return }

    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.refreshInvocations += 1
          Task { @MainActor [weak self] in await self?.refreshTasksIfNeeded() }
        }
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .refreshAllData)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.refreshInvocations += 1
          Task { @MainActor [weak self] in await self?.refreshTasksIfNeeded() }
        }
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.resetSessionState()
          Task { @MainActor [weak self] in
            await self?.reconcileCurrentOwnerReminders(removeOtherOwners: true)
          }
        }
      }
      .store(in: &cancellables)
  }

  func resetSessionState() {
    ownerOperationGeneration &+= 1
    incompleteTasks = []
    completedTasks = []
    deletedTasks = []
    overdueTasks = []
    todaysTasks = []
    tasksWithoutDueDate = []
    isLoadingIncomplete = false
    isLoadingCompleted = false
    isLoadingDeleted = false
    isLoadingMore = false
    hasMoreIncompleteTasks = true
    hasMoreCompletedTasks = true
    hasMoreDeletedTasks = false
    incompleteOffset = 0
    completedOffset = 0
    hasLoadedIncomplete = false
    hasLoadedCompleted = false
    hasScheduledStartupMaintenance = false
    error = nil
    incompleteError = nil
    completedError = nil
    reminderError = nil
  }

  // MARK: - Owner boundary

  private nonisolated static func operationOwner(_ expectedOwnerID: String?) -> String? {
    if let expectedOwnerID {
      let value = expectedOwnerID.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }
    return RuntimeOwnerIdentity.currentOwnerId()
  }

  private func captureLease(
    expectedOwnerID: String? = nil,
    authorizationSnapshot suppliedSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) -> OwnerLease? {
    if let suppliedSnapshot {
      if let expectedOwnerID,
        expectedOwnerID.trimmingCharacters(in: .whitespacesAndNewlines) != suppliedSnapshot.ownerID
      {
        return nil
      }
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(suppliedSnapshot) else { return nil }
      return OwnerLease(authorizationSnapshot: suppliedSnapshot, generation: ownerOperationGeneration)
    }
    guard let ownerID = Self.operationOwner(expectedOwnerID),
      let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID)
    else { return nil }
    return OwnerLease(authorizationSnapshot: snapshot, generation: ownerOperationGeneration)
  }

  private func isCurrent(_ lease: OwnerLease) -> Bool {
    lease.generation == ownerOperationGeneration
      && RuntimeOwnerIdentity.isAuthorizationCurrent(lease.authorizationSnapshot)
      && !Task.isCancelled
  }

  private nonisolated static func authorization(_ lease: OwnerLease) -> LocalMutationAuthorization {
    LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(lease.authorizationSnapshot)
    }
  }

  // MARK: - Local reads

  func loadTasksIfNeeded(expectedOwnerID: String? = nil) async {
    guard !hasLoadedIncomplete else { return }
    await loadTasks(expectedOwnerID: expectedOwnerID)
  }

  func loadTasks(expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID) else { return }
    await purgeStrandedUndoRows(lease: lease)
    guard isCurrent(lease) else { return }
    await loadIncompleteTasks(expectedOwnerID: lease.ownerID)
    guard isCurrent(lease) else { return }
    await loadDashboardTasks(
      expectedOwnerID: lease.ownerID,
      authorizationSnapshot: lease.authorizationSnapshot
    )
    guard isCurrent(lease) else { return }
    await reconcileReminders(lease: lease)
  }

  func loadIncompleteTasks(expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID), !isLoadingIncomplete else { return }
    isLoadingIncomplete = true
    incompleteError = nil
    error = nil
    defer {
      if isCurrent(lease) { isLoadingIncomplete = false }
    }
    do {
      let rows = try await ActionItemStorage.shared.getLocalActionItems(
        limit: pageSize + 1,
        offset: 0,
        completed: false
      )
      guard isCurrent(lease) else { return }
      hasMoreIncompleteTasks = rows.count > pageSize
      incompleteTasks = Array(rows.prefix(pageSize))
      incompleteOffset = incompleteTasks.count
      hasLoadedIncomplete = true
      NotificationCenter.default.post(name: .tasksPageDidLoad, object: nil)
    } catch {
      guard isCurrent(lease) else { return }
      incompleteError = error.localizedDescription
      self.error = error.localizedDescription
      logError("TasksStore: Failed to load local To Do tasks", error: error)
    }
  }

  func loadCompletedTasks(expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID), !isLoadingCompleted else { return }
    isLoadingCompleted = true
    completedError = nil
    error = nil
    defer {
      if isCurrent(lease) { isLoadingCompleted = false }
    }
    do {
      let rows = try await ActionItemStorage.shared.getLocalActionItems(
        limit: pageSize + 1,
        offset: 0,
        completed: true
      )
      guard isCurrent(lease) else { return }
      hasMoreCompletedTasks = rows.count > pageSize
      completedTasks = Array(rows.prefix(pageSize))
      completedOffset = completedTasks.count
      hasLoadedCompleted = true
      NotificationCenter.default.post(name: .tasksPageDidLoad, object: nil)
    } catch {
      guard isCurrent(lease) else { return }
      completedError = error.localizedDescription
      self.error = error.localizedDescription
      logError("TasksStore: Failed to load local Done tasks", error: error)
    }
  }

  /// Deleted tasks are private Undo state, not a third list/filter.
  func loadDeletedTasks(expectedOwnerID: String? = nil) async {
    guard captureLease(expectedOwnerID: expectedOwnerID) != nil else { return }
    deletedTasks = []
    hasMoreDeletedTasks = false
  }

  func reloadFromLocalCache(
    expectedOwnerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async {
    guard
      let lease = captureLease(
        expectedOwnerID: expectedOwnerID,
        authorizationSnapshot: authorizationSnapshot
      )
    else { return }
    await loadIncompletePage(lease: lease, replacing: true)
    if hasLoadedCompleted, isCurrent(lease) {
      await loadCompletedPage(lease: lease, replacing: true)
    }
    if isCurrent(lease) {
      await loadDashboardTasks(
        expectedOwnerID: lease.ownerID,
        authorizationSnapshot: lease.authorizationSnapshot
      )
    }
    if isCurrent(lease) {
      await reconcileReminders(lease: lease)
    }
  }

  func refreshTasksIfNeeded() async {
    guard isActive || hasLoadedIncomplete else { return }
    await reloadFromLocalCache()
  }

  func loadDashboardTasks(
    expectedOwnerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    loader: DashboardTaskLoader? = nil
  ) async {
    guard
      let lease = captureLease(
        expectedOwnerID: expectedOwnerID,
        authorizationSnapshot: authorizationSnapshot
      )
    else { return }
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: Date())
    let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
    let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    do {
      let snapshot: DashboardTaskSnapshot
      if let loader {
        snapshot = try await loader()
      } else {
        async let overdue = ActionItemStorage.shared.getFilteredActionItems(
          limit: 50,
          completedStates: [false],
          dueDateAfter: sevenDaysAgo,
          dueDateBefore: startOfToday
        )
        async let today = ActionItemStorage.shared.getFilteredActionItems(
          limit: 50,
          completedStates: [false],
          dueDateAfter: startOfToday,
          dueDateBefore: endOfToday
        )
        async let undated = ActionItemStorage.shared.getFilteredActionItems(
          limit: 50,
          completedStates: [false],
          dueDateIsNull: true,
          createdAfter: sevenDaysAgo
        )
        snapshot = try await DashboardTaskSnapshot(
          overdue: overdue,
          today: today,
          noDueDate: undated
        )
      }
      guard isCurrent(lease) else { return }
      overdueTasks = Self.sorted(snapshot.overdue)
      todaysTasks = Self.sorted(snapshot.today)
      tasksWithoutDueDate = Self.sorted(snapshot.noDueDate)
    } catch {
      if isCurrent(lease) {
        logError("TasksStore: Failed to load local dashboard tasks", error: error)
      }
    }
  }

  private static func sorted(_ tasks: [TaskActionItem]) -> [TaskActionItem] {
    tasks.sorted {
      let lhsDue = $0.dueAt ?? .distantFuture
      let rhsDue = $1.dueAt ?? .distantFuture
      return lhsDue == rhsDue ? $0.createdAt > $1.createdAt : lhsDue < rhsDue
    }
  }

  func loadMoreIncompleteIfNeeded(currentTask: TaskActionItem, expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID),
      hasMoreIncompleteTasks,
      !isLoadingMore,
      isNearEnd(currentTask, in: incompleteTasks)
    else { return }
    await loadIncompletePage(lease: lease, replacing: false)
  }

  func loadMoreCompletedIfNeeded(currentTask: TaskActionItem, expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID),
      hasMoreCompletedTasks,
      !isLoadingMore,
      isNearEnd(currentTask, in: completedTasks)
    else { return }
    await loadCompletedPage(lease: lease, replacing: false)
  }

  func loadMoreIfNeeded(currentTask: TaskActionItem, expectedOwnerID: String? = nil) async {
    if currentTask.completed {
      await loadMoreCompletedIfNeeded(currentTask: currentTask, expectedOwnerID: expectedOwnerID)
    } else {
      await loadMoreIncompleteIfNeeded(currentTask: currentTask, expectedOwnerID: expectedOwnerID)
    }
  }

  private func isNearEnd(_ task: TaskActionItem, in tasks: [TaskActionItem]) -> Bool {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return false }
    return index >= max(0, tasks.count - 10)
  }

  private func loadIncompletePage(lease: OwnerLease, replacing: Bool) async {
    guard isCurrent(lease), !isLoadingMore else { return }
    isLoadingMore = true
    defer {
      if isCurrent(lease) { isLoadingMore = false }
    }
    do {
      let offset = replacing ? 0 : incompleteOffset
      let rows = try await ActionItemStorage.shared.getLocalActionItems(
        limit: pageSize + 1,
        offset: offset,
        completed: false
      )
      guard isCurrent(lease) else { return }
      let page = Array(rows.prefix(pageSize))
      incompleteTasks = replacing ? page : incompleteTasks + page
      incompleteOffset = incompleteTasks.count
      hasMoreIncompleteTasks = rows.count > pageSize
      hasLoadedIncomplete = true
    } catch {
      if isCurrent(lease) { incompleteError = error.localizedDescription }
    }
  }

  private func loadCompletedPage(lease: OwnerLease, replacing: Bool) async {
    guard isCurrent(lease), !isLoadingMore else { return }
    isLoadingMore = true
    defer {
      if isCurrent(lease) { isLoadingMore = false }
    }
    do {
      let offset = replacing ? 0 : completedOffset
      let rows = try await ActionItemStorage.shared.getLocalActionItems(
        limit: pageSize + 1,
        offset: offset,
        completed: true
      )
      guard isCurrent(lease) else { return }
      let page = Array(rows.prefix(pageSize))
      completedTasks = replacing ? page : completedTasks + page
      completedOffset = completedTasks.count
      hasMoreCompletedTasks = rows.count > pageSize
      hasLoadedCompleted = true
    } catch {
      if isCurrent(lease) { completedError = error.localizedDescription }
    }
  }

  // MARK: - Local mutations

  @discardableResult
  func createTask(
    description: String,
    dueAt: Date?,
    priority: String?,
    recurrenceRule: String? = nil,
    source: String = "manual",
    expectedOwnerID: String? = nil
  ) async -> TaskActionItem? {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID) else { return nil }
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    do {
      let record = ActionItemRecord(
        description: trimmed,
        source: source,
        priority: priority,
        dueAt: dueAt,
        recurrenceRule: recurrenceRule
      )
      let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
        record,
        authorization: Self.authorization(lease)
      )
      guard isCurrent(lease) else { return nil }
      let task = inserted.toTaskActionItem()
      incompleteTasks.insert(task, at: 0)
      AnalyticsManager.shared.taskAdded()
      await loadDashboardTasks(
        expectedOwnerID: lease.ownerID,
        authorizationSnapshot: lease.authorizationSnapshot
      )
      await reconcileReminders(lease: lease)
      return task
    } catch {
      if isCurrent(lease) {
        self.error = error.localizedDescription
        logError("TasksStore: Failed to create local task", error: error)
      }
      return nil
    }
  }

  @discardableResult
  func toggleTask(
    _ task: TaskActionItem,
    expectedOwnerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    beforeLocalMutation: (() async -> Void)? = nil
  ) async -> Bool {
    guard
      let lease = captureLease(
        expectedOwnerID: expectedOwnerID,
        authorizationSnapshot: authorizationSnapshot
      )
    else { return false }
    if let beforeLocalMutation { await beforeLocalMutation() }
    guard isCurrent(lease) else { return false }
    let completed = !task.completed
    let nextDue = completed ? Self.nextFutureDueDate(for: task) : nil
    do {
      let result = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
        surfacedId: task.id,
        completed: completed,
        nextDueAt: nextDue,
        authorization: Self.authorization(lease)
      )
      guard isCurrent(lease) else { return false }
      if completed {
        incompleteTasks.removeAll { $0.id == task.id }
        completedTasks.insert(result.task, at: 0)
        if let next = result.next { incompleteTasks.insert(next, at: 0) }
        AnalyticsManager.shared.taskCompleted(source: task.source)
      } else {
        completedTasks.removeAll { $0.id == task.id }
        incompleteTasks.insert(result.task, at: 0)
      }
      await loadDashboardTasks(
        expectedOwnerID: lease.ownerID,
        authorizationSnapshot: lease.authorizationSnapshot
      )
      await reconcileReminders(lease: lease)
      return true
    } catch {
      if isCurrent(lease) {
        self.error = error.localizedDescription
        logError("TasksStore: Failed to toggle local task", error: error)
      }
      return false
    }
  }

  @discardableResult
  func deleteTask(
    _ task: TaskActionItem,
    expectedOwnerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil,
    beforeLocalMutation: (() async -> Void)? = nil
  ) async -> Bool {
    guard
      let lease = captureLease(
        expectedOwnerID: expectedOwnerID,
        authorizationSnapshot: authorizationSnapshot
      )
    else { return false }
    if let beforeLocalMutation { await beforeLocalMutation() }
    guard isCurrent(lease) else { return false }
    do {
      try await ActionItemStorage.shared.softDelete(
        surfacedId: task.id,
        authorization: Self.authorization(lease)
      )
      guard isCurrent(lease) else { return false }
      incompleteTasks.removeAll { $0.id == task.id }
      completedTasks.removeAll { $0.id == task.id }
      AnalyticsManager.shared.taskDeleted(source: task.source)
      await loadDashboardTasks(
        expectedOwnerID: lease.ownerID,
        authorizationSnapshot: lease.authorizationSnapshot
      )
      await reconcileReminders(lease: lease)
      return true
    } catch {
      if isCurrent(lease) {
        self.error = error.localizedDescription
        logError("TasksStore: Failed to delete local task", error: error)
      }
      return false
    }
  }

  func restoreTask(_ task: TaskActionItem, expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID) else { return }
    do {
      let restored = try await ActionItemStorage.shared.restoreActionItem(
        surfacedId: task.id,
        authorization: Self.authorization(lease)
      )
      guard isCurrent(lease) else { return }
      if restored.completed {
        completedTasks.insert(restored, at: 0)
      } else {
        incompleteTasks.insert(restored, at: 0)
      }
      await loadDashboardTasks(
        expectedOwnerID: lease.ownerID,
        authorizationSnapshot: lease.authorizationSnapshot
      )
      await reconcileReminders(lease: lease)
    } catch {
      if isCurrent(lease) {
        self.error = error.localizedDescription
        logError("TasksStore: Failed to restore local task", error: error)
      }
    }
  }

  @discardableResult
  func updateTask(
    _ task: TaskActionItem,
    description: String? = nil,
    dueAt: Date? = nil,
    clearDueAt: Bool = false,
    priority: String? = nil,
    recurrenceRule: String? = nil,
    expectedOwnerID: String? = nil
  ) async -> Bool {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID) else { return false }
    let normalizedDescription = description.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let normalizedDescription, normalizedDescription.isEmpty { return false }
    do {
      try await ActionItemStorage.shared.updateActionItemFields(
        surfacedId: task.id,
        description: normalizedDescription,
        dueAt: dueAt,
        clearDueAt: clearDueAt,
        priority: priority,
        recurrenceRule: recurrenceRule,
        authorization: Self.authorization(lease)
      )
      guard isCurrent(lease),
        let updated = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: task.id)
      else { return false }
      replaceTask(updated)
      await loadDashboardTasks(
        expectedOwnerID: lease.ownerID,
        authorizationSnapshot: lease.authorizationSnapshot
      )
      await reconcileReminders(lease: lease)
      return true
    } catch {
      if isCurrent(lease) {
        self.error = error.localizedDescription
        logError("TasksStore: Failed to update local task", error: error)
      }
      return false
    }
  }

  private func replaceTask(_ task: TaskActionItem) {
    if let index = incompleteTasks.firstIndex(where: { $0.id == task.id }) {
      incompleteTasks[index] = task
    }
    if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
      completedTasks[index] = task
    }
  }

  func finalizePendingDeletes(expectedOwnerID: String? = nil) async {
    guard let lease = captureLease(expectedOwnerID: expectedOwnerID) else { return }
    do {
      _ = try await ActionItemStorage.shared.purgeUserDeletedItems(
        authorization: Self.authorization(lease)
      )
    } catch {
      if isCurrent(lease) {
        logError("TasksStore: Failed to finalize task deletion", error: error)
      }
    }
  }

  @discardableResult
  func scheduleStartupMaintenanceIfNeeded(expectedOwnerID: String? = nil) -> [Task<Void, Never>] {
    guard !hasScheduledStartupMaintenance,
      let lease = captureLease(expectedOwnerID: expectedOwnerID)
    else { return [] }
    hasScheduledStartupMaintenance = true
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.purgeStrandedUndoRows(lease: lease)
    }
    return [task]
  }

  private func purgeStrandedUndoRows(lease: OwnerLease) async {
    guard isCurrent(lease) else { return }
    do {
      _ = try await ActionItemStorage.shared.purgeUserDeletedItems(
        authorization: Self.authorization(lease)
      )
    } catch {
      if isCurrent(lease) {
        logError("TasksStore: Failed to purge stranded task tombstones", error: error)
      }
    }
  }

  private func reconcileReminders(lease: OwnerLease) async {
    guard isCurrent(lease) else { return }
    let authoritative =
      (try? await ActionItemStorage.shared.getLocalActionItems(
        limit: 10_000,
        completed: false
      )) ?? []
    guard isCurrent(lease) else { return }
    let result = await reminderService.reconcile(
      tasks: authoritative,
      ownerID: lease.ownerID,
      authorizationSnapshot: lease.authorizationSnapshot
    )
    guard isCurrent(lease) else { return }
    reminderError = result.errorDescription
    if let errorDescription = result.errorDescription {
      log("TasksStore: task committed but reminder reconciliation failed: \(errorDescription)")
    }
  }

  private func reconcileCurrentOwnerReminders(removeOtherOwners: Bool) async {
    guard let lease = captureLease() else {
      await reminderService.removeAllTaskRemindersWhileSignedOut()
      return
    }
    let authoritative =
      (try? await ActionItemStorage.shared.getLocalActionItems(
        limit: 10_000,
        completed: false
      )) ?? []
    guard isCurrent(lease) else { return }
    let result = await reminderService.reconcile(
      tasks: authoritative,
      ownerID: lease.ownerID,
      authorizationSnapshot: lease.authorizationSnapshot,
      removeOtherOwners: removeOtherOwners
    )
    guard isCurrent(lease) else { return }
    reminderError = result.errorDescription
  }

  nonisolated static func nextFutureDueDate(
    for task: TaskActionItem,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> Date? {
    guard let rule = task.recurrenceRule, !rule.isEmpty else { return nil }
    let start = task.dueAt ?? now
    func advance(_ date: Date) -> Date? {
      switch rule {
      case "daily": return calendar.date(byAdding: .day, value: 1, to: date)
      case "weekdays":
        var next = calendar.date(byAdding: .day, value: 1, to: date)
        while let value = next, calendar.isDateInWeekend(value) {
          next = calendar.date(byAdding: .day, value: 1, to: value)
        }
        return next
      case "weekly": return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
      case "biweekly": return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
      case "monthly": return calendar.date(byAdding: .month, value: 1, to: date)
      default: return nil
      }
    }
    guard var next = advance(start) else { return nil }
    while next <= now {
      guard let value = advance(next) else { return nil }
      next = value
    }
    return next
  }
}
