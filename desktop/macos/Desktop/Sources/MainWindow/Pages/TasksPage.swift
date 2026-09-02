import AppKit
import Combine
import OmiTheme
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Due-date grouping

enum TaskCategory: String, CaseIterable {
  case today = "Today & Overdue"
  case tomorrow = "Tomorrow"
  case later = "Later"
  case noDeadline = "No Deadline"

  var icon: String {
    switch self {
    case .today: return "sun.max.fill"
    case .tomorrow: return "sunrise.fill"
    case .later: return "calendar"
    case .noDeadline: return "tray.fill"
    }
  }
}

// MARK: - View model

@MainActor
final class TasksViewModel: ObservableObject {
  private let store = TasksStore.shared
  private var cancellables = Set<AnyCancellable>()
  private var ownerGeneration: UInt64 = 0
  private var didRegisterAutomationActions = false
  private var searchTask: Task<Void, Never>?
  private var returnTask: Task<Void, Never>?
  private var undoTask: Task<Void, Never>?
  private var lastReturn: (id: String, date: Date)?
  private var reorderGeneration: UInt64 = 0

  @Published var searchText = "" {
    didSet {
      guard searchText != oldValue else { return }
      searchTask?.cancel()
      searchTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(180))
        await self?.performSearch()
      }
    }
  }
  @Published private(set) var searchResults: [TaskActionItem] = []
  @Published private(set) var isSearching = false
  @Published var showCompleted = false {
    didSet {
      guard showCompleted != oldValue else { return }
      keyboardSelectedTaskId = nil
      recompute()
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.showCompleted { await self.store.loadCompletedTasks() }
        self.recompute()
      }
    }
  }
  @Published private(set) var displayTasks: [TaskActionItem] = []
  @Published private(set) var categorizedTasks: [TaskCategory: [TaskActionItem]] = [:]
  @Published var keyboardSelectedTaskId: String?
  @Published var isInlineCreating = false
  @Published var inlineCreateAfterTaskId: String?
  @Published var editingTaskId: String?
  @Published var animateToggleTaskId: String?
  @Published var draggedTaskId: String?
  @Published var dropTargetTaskId: String?

  struct UndoableAction: Identifiable {
    let task: TaskActionItem
    let timestamp: Date
    var id: String { task.id }
  }
  @Published private(set) var undoStack: [UndoableAction] = []
  @Published var showUndoToast = false

  var tasks: [TaskActionItem] { store.tasks }
  var isLoading: Bool { showCompleted ? store.isLoadingCompleted : store.isLoadingIncomplete }
  var isLoadingMore: Bool { store.isLoadingMore }
  var error: String? { showCompleted ? store.completedError : store.incompleteError }
  var reminderWarning: String? {
    store.reminderError.map { _ in
      "Task saved, but its reminder could not be scheduled."
    }
  }
  var hasMoreTasks: Bool { showCompleted ? store.hasMoreCompletedTasks : store.hasMoreIncompleteTasks }
  var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  var canReorder: Bool { !showCompleted && !isSearchActive }

  var navigationOrder: [TaskActionItem] {
    showCompleted || isSearchActive
      ? displayTasks
      : TaskCategory.allCases.flatMap { categorizedTasks[$0] ?? [] }
  }

  init() {
    store.objectWillChange
      .receive(on: DispatchQueue.main)
      .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in self?.recompute() }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.ownerGeneration &+= 1
          self.reorderGeneration &+= 1
          self.searchTask?.cancel()
          self.returnTask?.cancel()
          self.undoTask?.cancel()
          self.undoStack = []
          self.showUndoToast = false
          self.searchResults = []
          self.keyboardSelectedTaskId = nil
          self.recompute()
        }
      }
      .store(in: &cancellables)
  }

  func loadTasksForFirstUse() async {
    await store.loadTasksIfNeeded()
    recompute()
  }

  func loadTasks() async {
    if showCompleted {
      await store.loadCompletedTasks()
    } else {
      await store.loadTasks()
    }
    recompute()
  }

  func toggleShowCompletedView() { showCompleted.toggle() }

  private func performSearch() async {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      searchResults = []
      isSearching = false
      recompute()
      return
    }
    isSearching = true
    let generation = ownerGeneration
    do {
      let rows = try await ActionItemStorage.shared.searchDescriptions(query: query, limit: 500)
      guard generation == ownerGeneration, !Task.isCancelled else { return }
      searchResults = rows
    } catch {
      guard generation == ownerGeneration else { return }
      searchResults = []
    }
    isSearching = false
    recompute()
  }

  func recompute() {
    let source =
      isSearchActive
      ? searchResults
      : (showCompleted
        ? store.completedTasks.filter(\.completed)
        : store.incompleteTasks.filter { !$0.completed })
    displayTasks = source.sorted(by: Self.taskSort)
    guard !showCompleted, !isSearchActive else {
      categorizedTasks = [:]
      return
    }
    categorizedTasks = Dictionary(
      grouping: displayTasks,
      by: { Self.category(for: $0) }
    ).mapValues { $0.sorted(by: Self.taskSort) }
  }

  private static func taskSort(_ lhs: TaskActionItem, _ rhs: TaskActionItem) -> Bool {
    let lhsOrder = lhs.sortOrder ?? Int.max
    let rhsOrder = rhs.sortOrder ?? Int.max
    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
    let lhsDue = lhs.dueAt ?? .distantFuture
    let rhsDue = rhs.dueAt ?? .distantFuture
    return lhsDue == rhsDue ? lhs.createdAt > rhs.createdAt : lhsDue < rhsDue
  }

  static func category(for task: TaskActionItem, now: Date = Date(), calendar: Calendar = .current) -> TaskCategory {
    guard let due = task.dueAt else { return .noDeadline }
    let today = calendar.startOfDay(for: now)
    guard
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
      let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)
    else { return .later }
    if due < tomorrow { return .today }
    if due < dayAfterTomorrow { return .tomorrow }
    return .later
  }

  static func deadline(for category: TaskCategory, now: Date = Date(), calendar: Calendar = .current) -> Date? {
    let today = calendar.startOfDay(for: now)
    switch category {
    case .today:
      return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: today)
    case .tomorrow:
      return calendar.date(byAdding: .day, value: 1, to: today)
    case .later:
      return calendar.date(byAdding: .day, value: 7, to: today)
    case .noDeadline:
      return nil
    }
  }

  static func inlineCreationDueDate(
    after selected: TaskActionItem?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> Date? {
    selected.flatMap {
      deadline(for: category(for: $0, now: now, calendar: calendar), now: now, calendar: calendar)
    }
  }

  static func reorderedDueDate(
    for task: TaskActionItem,
    in category: TaskCategory,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> Date? {
    Self.category(for: task, now: now, calendar: calendar) == category
      ? task.dueAt
      : Self.deadline(for: category, now: now, calendar: calendar)
  }

  func getOrderedTasks(for category: TaskCategory) -> [TaskActionItem] {
    categorizedTasks[category] ?? []
  }

  @discardableResult
  func createTask(description: String, dueAt: Date?, priority: String?) async -> TaskActionItem? {
    let task = await store.createTask(description: description, dueAt: dueAt, priority: priority)
    recompute()
    return task
  }

  func createInlineTask(description: String, afterTaskId: String?) async {
    let selected = afterTaskId.flatMap(findTask)
    let due = Self.inlineCreationDueDate(after: selected)
    guard let created = await createTask(description: description, dueAt: due, priority: nil) else { return }
    if let selected {
      await reorderTask(created, before: nil, after: selected, in: Self.category(for: selected))
    }
    keyboardSelectedTaskId = created.id
    isInlineCreating = false
    inlineCreateAfterTaskId = nil
  }

  func updateTaskDetails(
    _ task: TaskActionItem,
    description: String? = nil,
    dueAt: Date? = nil,
    clearDueAt: Bool = false,
    priority: String? = nil,
    recurrenceRule: String? = nil
  ) async {
    await store.updateTask(
      task,
      description: description,
      dueAt: dueAt,
      clearDueAt: clearDueAt,
      priority: priority,
      recurrenceRule: recurrenceRule
    )
    recompute()
  }

  @discardableResult
  func toggleTask(_ task: TaskActionItem) async -> Bool {
    animateToggleTaskId = task.id
    try? await Task.sleep(for: .milliseconds(140))
    let accepted = await store.toggleTask(task)
    animateToggleTaskId = nil
    recompute()
    return accepted
  }

  @discardableResult
  func deleteTaskWithUndo(_ task: TaskActionItem) async -> Bool {
    guard await store.deleteTask(task) else { return false }
    guard !store.tasks.contains(where: { $0.id == task.id }) else { return false }
    undoStack.append(UndoableAction(task: task, timestamp: Date()))
    if undoStack.count > 10 { undoStack.removeFirst(undoStack.count - 10) }
    showUndoToast = true
    scheduleUndoExpiry()
    recompute()
    return true
  }

  func undoLastDelete() async {
    guard let action = undoStack.popLast() else { return }
    await store.restoreTask(action.task)
    showUndoToast = !undoStack.isEmpty
    if undoStack.isEmpty {
      undoTask?.cancel()
    } else {
      scheduleUndoExpiry()
    }
    recompute()
  }

  private func scheduleUndoExpiry() {
    undoTask?.cancel()
    undoTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard let self, !Task.isCancelled else { return }
      await self.store.finalizePendingDeletes()
      self.undoStack = []
      self.showUndoToast = false
    }
  }

  func findTask(_ id: String) -> TaskActionItem? {
    store.tasks.first(where: { $0.id == id }) ?? searchResults.first(where: { $0.id == id })
  }

  func loadMoreIfNeeded(currentTask: TaskActionItem) async {
    guard !isSearchActive else { return }
    await store.loadMoreIfNeeded(currentTask: currentTask)
    recompute()
  }

  func loadMoreTapped() async {
    guard let last = displayTasks.last else { return }
    await loadMoreIfNeeded(currentTask: last)
  }

  @discardableResult
  func reorderTask(
    _ task: TaskActionItem,
    before target: TaskActionItem?,
    after previous: TaskActionItem? = nil,
    in category: TaskCategory
  ) async -> Bool {
    guard canReorder,
      let ownerID = RuntimeOwnerIdentity.currentOwnerId(),
      let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot(expectedOwnerID: ownerID)
    else { return false }

    // Drag callbacks can arrive faster than SQLite commits. Only the newest
    // drop in a burst is allowed to persist so an older write cannot win the
    // race after the pointer has already moved elsewhere.
    reorderGeneration &+= 1
    let generation = reorderGeneration
    try? await Task.sleep(for: .milliseconds(75))
    guard generation == reorderGeneration, !Task.isCancelled else { return false }

    var ids = getOrderedTasks(for: category).map(\.id)
    for key in TaskCategory.allCases where key != category {
      ids.removeAll { Set(getOrderedTasks(for: key).map(\.id)).contains($0) }
    }
    ids.removeAll { $0 == task.id }
    if let target, let index = ids.firstIndex(of: target.id) {
      ids.insert(task.id, at: index)
    } else if let previous, let index = ids.firstIndex(of: previous.id) {
      ids.insert(task.id, at: min(ids.count, index + 1))
    } else {
      ids.append(task.id)
    }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      try await ActionItemStorage.shared.reorderTask(
        surfacedId: task.id,
        dueAt: Self.reorderedDueDate(for: task, in: category),
        orderedIds: ids,
        categoryIndex: TaskCategory.allCases.firstIndex(of: category) ?? 0,
        authorization: authorization
      )
      await store.reloadFromLocalCache(
        expectedOwnerID: ownerID,
        authorizationSnapshot: snapshot
      )
      recompute()
      return true
    } catch {
      logError("TasksViewModel: Failed to persist local task order", error: error)
      return false
    }
  }

  // MARK: Keyboard

  func handleKeyDown(_ event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "n" {
      isInlineCreating = true
      inlineCreateAfterTaskId = nil
      return true
    }
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "d",
      let id = keyboardSelectedTaskId, let task = findTask(id)
    {
      Task { @MainActor in await deleteTaskWithUndo(task) }
      return true
    }
    if editingTaskId != nil { return false }
    switch event.keyCode {
    case 53:  // Escape
      returnTask?.cancel()
      isInlineCreating = false
      inlineCreateAfterTaskId = nil
      keyboardSelectedTaskId = nil
      return true
    case 126:  // Up
      moveSelection(by: -1)
      return true
    case 125:  // Down
      moveSelection(by: 1)
      return true
    case 49:  // Space
      if let id = keyboardSelectedTaskId, let task = findTask(id) {
        Task { @MainActor in await toggleTask(task) }
        return true
      }
    case 36:  // Return
      handleReturn()
      return true
    default:
      break
    }
    return false
  }

  private func moveSelection(by delta: Int) {
    let rows = navigationOrder
    guard !rows.isEmpty else { return }
    let current = keyboardSelectedTaskId.flatMap { id in rows.firstIndex(where: { $0.id == id }) }
    let next = min(rows.count - 1, max(0, (current ?? (delta > 0 ? -1 : rows.count)) + delta))
    keyboardSelectedTaskId = rows[next].id
  }

  private func handleReturn() {
    guard let id = keyboardSelectedTaskId else {
      isInlineCreating = true
      inlineCreateAfterTaskId = nil
      return
    }
    let now = Date()
    if let lastReturn, lastReturn.id == id, now.timeIntervalSince(lastReturn.date) <= 0.4 {
      returnTask?.cancel()
      self.lastReturn = nil
      editingTaskId = id
      return
    }
    lastReturn = (id, now)
    returnTask?.cancel()
    returnTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard let self, !Task.isCancelled, self.findTask(id) != nil else { return }
      self.inlineCreateAfterTaskId = id
      self.isInlineCreating = true
      self.lastReturn = nil
    }
  }

  // MARK: Automation

  func registerAutomationActions() {
    guard !didRegisterAutomationActions else { return }
    didRegisterAutomationActions = true
    let registry = DesktopAutomationActionRegistry.shared

    registry.register(
      name: "create_task",
      summary: "Create a local task and return its stable local id",
      params: ["description", "priority"]
    ) { [weak self] params in
      guard let self else { return ["error": "tasks view model deallocated"] }
      let description = params["description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedDescription = description.flatMap { $0.isEmpty ? nil : $0 } ?? "Automation task"
      guard
        let task = await self.createTask(
          description: resolvedDescription,
          dueAt: nil,
          priority: params["priority"]
        )
      else { return ["error": "create failed"] }
      return [
        "id": task.id, "local_id": task.id.hasPrefix("local_") ? "true" : "false", "description": task.description,
      ]
    }

    registry.register(
      name: "seed_tasks",
      summary: "Create a bounded set of local tasks",
      params: ["count", "prefix"]
    ) { [weak self] params in
      guard let self else { return ["error": "tasks view model deallocated"] }
      let count = max(0, min(Int(params["count"] ?? "") ?? 5, 300))
      let prefix = params["prefix"] ?? "Automation task"
      var ids: [String] = []
      for index in 0..<count {
        if let task = await self.createTask(
          description: "\(prefix) \(index + 1)",
          dueAt: nil,
          priority: nil
        ) {
          ids.append(task.id)
        }
      }
      return ["created": String(ids.count), "ids": ids.joined(separator: ",")]
    }

    registry.register(
      name: "toggle_task",
      summary: "Toggle a local task",
      params: ["id", "description"]
    ) { [weak self] params in
      guard let self else { return ["error": "tasks view model deallocated"] }
      await self.ensureTasksLoadedForAutomation()
      let matches = self.matches(params)
      guard matches.count == 1, let task = matches.first else {
        return ["error": matches.count > 1 ? "ambiguous task" : "task not found"]
      }
      guard await self.toggleTask(task) else { return ["error": "toggle failed"] }
      let completed = self.findTask(task.id)?.completed ?? task.completed
      return ["id": task.id, "completed": completed ? "true" : "false"]
    }

    registry.register(
      name: "delete_task",
      summary: "Delete a local task",
      params: ["id", "description"]
    ) { [weak self] params in
      guard let self else { return ["error": "tasks view model deallocated"] }
      await self.ensureTasksLoadedForAutomation()
      let matches = self.matches(params)
      guard matches.count == 1, let task = matches.first else {
        return ["error": matches.count > 1 ? "ambiguous task" : "task not found"]
      }
      guard await self.deleteTaskWithUndo(task) else { return ["error": "delete failed"] }
      return ["id": task.id, "deleted": "true"]
    }

    registry.register(
      name: "reorder_task",
      summary: "Move a task within or across a local due-date section",
      params: ["id", "index", "category"]
    ) { [weak self] params in
      guard let self else { return ["error": "tasks view model deallocated"] }
      await self.ensureTasksLoadedForAutomation()
      guard let id = params["id"], let task = self.findTask(id) else {
        return ["error": "task not found"]
      }
      let category = Self.automationCategory(params["category"]) ?? .today
      let rows = self.getOrderedTasks(for: category).filter { $0.id != id }
      let index = max(0, min(Int(params["index"] ?? "") ?? 0, rows.count))
      let target = index < rows.count ? rows[index] : nil
      let previous = index > 0 ? rows[index - 1] : nil
      guard await self.reorderTask(task, before: target, after: previous, in: category) else {
        return ["error": "reorder failed"]
      }
      return [
        "id": id,
        "category": category.rawValue,
        "order": self.getOrderedTasks(for: category).map(\.id).joined(separator: ","),
      ]
    }

    registry.register(
      name: "dump_tasks",
      summary: "Read local tasks with stable ids and retained fields",
      params: ["includeCompleted", "limit", "marker"]
    ) { params in
      let includeCompleted = ["true", "1", "yes"].contains(params["includeCompleted"]?.lowercased() ?? "")
      let limit = max(1, min(Int(params["limit"] ?? "") ?? 500, 10_000))
      do {
        let items = try await ActionItemStorage.shared.getLocalActionItems(
          limit: limit,
          completed: includeCompleted ? nil : false
        )
        let rows: [[String: Any]] = items.map { task in
          [
            "id": task.id,
            "description": task.description,
            "completed": task.completed,
            "sortOrder": task.sortOrder ?? -1,
            "dueAt": task.dueAt?.ISO8601Format() ?? "",
          ]
        }
        let json =
          (try? JSONSerialization.data(withJSONObject: rows))
          .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var result = ["count": String(items.count), "tasks": json]
        if let marker = params["marker"], !marker.isEmpty {
          result["marker_absent"] = items.contains { $0.description.contains(marker) } ? "false" : "true"
        }
        return result
      } catch {
        return ["error": error.localizedDescription]
      }
    }
  }

  private func ensureTasksLoadedForAutomation() async {
    await store.loadTasks()
    await store.loadCompletedTasks()
    recompute()
  }

  private func matches(_ params: [String: String]) -> [TaskActionItem] {
    if let id = params["id"], !id.isEmpty { return tasks.filter { $0.id == id } }
    guard let description = params["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !description.isEmpty
    else { return [] }
    return tasks.filter { $0.description.localizedCaseInsensitiveContains(description) }
  }

  private static func automationCategory(_ raw: String?) -> TaskCategory? {
    switch raw?.lowercased() {
    case "today": return .today
    case "tomorrow": return .tomorrow
    case "later": return .later
    case "nodeadline", "no_deadline", "none": return .noDeadline
    default: return nil
    }
  }
}

// MARK: - Page

struct TasksPage: View {
  @ObservedObject var viewModel: TasksViewModel
  var chatProvider: ChatProvider?

  @State private var inlineText = ""
  @FocusState private var inlineFocused: Bool
  @State private var keyboardMonitor: Any?

  var body: some View {
    VStack(spacing: 0) {
      header
      if let reminderWarning = viewModel.reminderWarning {
        HStack(spacing: OmiSpacing.sm) {
          Image(systemName: "exclamationmark.triangle.fill")
          Text(reminderWarning)
          Spacer()
        }
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textSecondary)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.vertical, OmiSpacing.sm)
        .background(OmiColors.backgroundSecondary)
        .accessibilityIdentifier("tasks.reminder.warning")
      }
      content
    }
    .background(OmiColors.backgroundPrimary)
    .overlay(alignment: .bottom) {
      if viewModel.showUndoToast, let latest = viewModel.undoStack.last {
        UndoToastView(
          taskDescription: latest.task.description,
          undoCount: viewModel.undoStack.count,
          onUndo: { Task { await viewModel.undoLastDelete() } }
        )
        .padding(.bottom, OmiSpacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .task { await viewModel.loadTasksForFirstUse() }
    .onAppear { installKeyboardMonitor() }
    .onDisappear { removeKeyboardMonitor() }
    .onChange(of: viewModel.isInlineCreating) { _, active in
      if active {
        inlineText = ""
        DispatchQueue.main.async { inlineFocused = true }
      } else {
        inlineFocused = false
      }
    }
  }

  private var header: some View {
    HStack(spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.sm) {
        if viewModel.isSearching {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "magnifyingglass")
            .foregroundColor(OmiColors.textTertiary)
        }
        TextField("Search tasks...", text: $viewModel.searchText)
          .textFieldStyle(.plain)
        if !viewModel.searchText.isEmpty {
          Button {
            viewModel.searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .foregroundColor(OmiColors.textTertiary)
        }
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(OmiColors.backgroundSecondary)
      .cornerRadius(OmiChrome.elementRadius)

      Button {
        viewModel.toggleShowCompletedView()
      } label: {
        Image(systemName: viewModel.showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
          .padding(OmiSpacing.sm)
          .background(OmiColors.backgroundSecondary)
          .cornerRadius(OmiChrome.elementRadius)
      }
      .buttonStyle(.plain)
      .help(viewModel.showCompleted ? "Show To Do" : "Show Done")

      Button {
        viewModel.inlineCreateAfterTaskId = nil
        viewModel.isInlineCreating = true
      } label: {
        Image(systemName: "plus")
          .padding(OmiSpacing.sm)
          .background(OmiColors.backgroundSecondary)
          .cornerRadius(OmiChrome.elementRadius)
      }
      .buttonStyle(.plain)
      .help("Add task (⌘N)")

      Button {
        NotificationCenter.default.post(name: .navigateToTaskSettings, object: nil)
      } label: {
        Image(systemName: "gearshape")
          .padding(OmiSpacing.sm)
          .background(OmiColors.backgroundSecondary)
          .cornerRadius(OmiChrome.elementRadius)
      }
      .buttonStyle(.plain)
      .help("Task Settings")
    }
    .foregroundColor(OmiColors.textSecondary)
    .padding(.horizontal, OmiSpacing.lg)
    .padding(.vertical, OmiSpacing.md)
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading && viewModel.displayTasks.isEmpty {
      ProgressView("Loading tasks...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = viewModel.error, viewModel.displayTasks.isEmpty {
      VStack(spacing: OmiSpacing.md) {
        Text("Failed to load tasks").scaledFont(size: OmiType.heading, weight: .semibold)
        Text(error).foregroundColor(OmiColors.textTertiary)
        Button("Try Again") { Task { await viewModel.loadTasks() } }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if viewModel.displayTasks.isEmpty && !viewModel.isInlineCreating {
      VStack(spacing: OmiSpacing.md) {
        Image(systemName: viewModel.isSearchActive ? "magnifyingglass" : "tray.fill")
          .scaledFont(size: 42)
          .foregroundColor(OmiColors.textTertiary)
        Text(
          viewModel.isSearchActive
            ? "No Results Found" : (viewModel.showCompleted ? "No Completed Tasks" : "All Caught Up")
        )
        .scaledFont(size: OmiType.heading, weight: .semibold)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      taskList
    }
  }

  private var taskList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: OmiSpacing.lg) {
          if viewModel.isInlineCreating && viewModel.inlineCreateAfterTaskId == nil {
            inlineCreationRow
          }

          if viewModel.showCompleted || viewModel.isSearchActive {
            ForEach(viewModel.displayTasks) { task in
              taskWithInlineCreation(task: task, category: nil)
                .onAppear { Task { await viewModel.loadMoreIfNeeded(currentTask: task) } }
            }
          } else {
            ForEach(TaskCategory.allCases, id: \.self) { category in
              let rows = viewModel.getOrderedTasks(for: category)
              if !rows.isEmpty {
                TaskCategorySection(
                  category: category,
                  tasks: rows,
                  viewModel: viewModel,
                  inlineText: $inlineText,
                  inlineFocused: $inlineFocused,
                  commitInline: commitInline,
                  cancelInline: cancelInline
                )
              }
            }
          }

          if viewModel.isLoadingMore {
            ProgressView().controlSize(.small).padding(.vertical, OmiSpacing.md)
          } else if viewModel.hasMoreTasks && !viewModel.isSearchActive {
            Button("Load more tasks") { Task { await viewModel.loadMoreTapped() } }
              .buttonStyle(.bordered)
              .controlSize(.small)
          }

          if !viewModel.displayTasks.isEmpty {
            KeyboardHintBar(
              isEditing: viewModel.editingTaskId != nil,
              isInlineCreating: viewModel.isInlineCreating,
              hasSelection: viewModel.keyboardSelectedTaskId != nil
            )
          }
        }
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.bottom, OmiSpacing.xxl)
      }
      .refreshable { await viewModel.loadTasks() }
      .onAppear { proxy.scrollTo(viewModel.keyboardSelectedTaskId, anchor: .center) }
      .onChange(of: viewModel.keyboardSelectedTaskId) { _, id in
        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
      }
    }
  }

  private func taskWithInlineCreation(task: TaskActionItem, category: TaskCategory?) -> some View {
    VStack(spacing: OmiSpacing.xxs) {
      TaskRow(
        task: task,
        isKeyboardSelected: viewModel.keyboardSelectedTaskId == task.id,
        isEditing: viewModel.editingTaskId == task.id,
        canDrag: false,
        onSelect: { viewModel.keyboardSelectedTaskId = task.id },
        onStartEditing: { viewModel.editingTaskId = task.id },
        onFinishEditing: { viewModel.editingTaskId = nil },
        onToggle: { await viewModel.toggleTask(task) },
        onDelete: { await viewModel.deleteTaskWithUndo(task) },
        onUpdate: { description, dueAt, clearDueAt, priority, recurrence in
          await viewModel.updateTaskDetails(
            task,
            description: description,
            dueAt: dueAt,
            clearDueAt: clearDueAt,
            priority: priority,
            recurrenceRule: recurrence
          )
        }
      )
      .id(task.id)

      if viewModel.isInlineCreating && viewModel.inlineCreateAfterTaskId == task.id {
        inlineCreationRow
      }
    }
  }

  private var inlineCreationRow: some View {
    InlineTaskCreationRow(
      text: $inlineText,
      isFocused: $inlineFocused,
      onCommit: commitInline,
      onCancel: cancelInline
    )
  }

  private func commitInline() {
    let description = inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !description.isEmpty else {
      cancelInline()
      return
    }
    let after = viewModel.inlineCreateAfterTaskId
    inlineText = ""
    Task { await viewModel.createInlineTask(description: description, afterTaskId: after) }
  }

  private func cancelInline() {
    inlineText = ""
    inlineFocused = false
    viewModel.isInlineCreating = false
    viewModel.inlineCreateAfterTaskId = nil
  }

  private func installKeyboardMonitor() {
    guard keyboardMonitor == nil else { return }
    keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let handled = MainActor.assumeIsolated { viewModel.handleKeyDown(event) }
      return handled ? nil : event
    }
  }

  private func removeKeyboardMonitor() {
    if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    keyboardMonitor = nil
  }
}

// MARK: - Sections and drag/drop

struct TaskCategorySection: View {
  let category: TaskCategory
  let tasks: [TaskActionItem]
  @ObservedObject var viewModel: TasksViewModel
  @Binding var inlineText: String
  var inlineFocused: FocusState<Bool>.Binding
  let commitInline: () -> Void
  let cancelInline: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: category.icon)
        Text(category.rawValue).scaledFont(size: OmiType.body, weight: .semibold)
        Text("\(tasks.count)").foregroundColor(OmiColors.textTertiary)
      }
      .foregroundColor(OmiColors.textSecondary)

      ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
        VStack(spacing: OmiSpacing.xxs) {
          TaskRow(
            task: task,
            isKeyboardSelected: viewModel.keyboardSelectedTaskId == task.id,
            isEditing: viewModel.editingTaskId == task.id,
            canDrag: viewModel.canReorder,
            onSelect: { viewModel.keyboardSelectedTaskId = task.id },
            onStartEditing: { viewModel.editingTaskId = task.id },
            onFinishEditing: { viewModel.editingTaskId = nil },
            onToggle: { await viewModel.toggleTask(task) },
            onDelete: { await viewModel.deleteTaskWithUndo(task) },
            onUpdate: { description, dueAt, clearDueAt, priority, recurrence in
              await viewModel.updateTaskDetails(
                task,
                description: description,
                dueAt: dueAt,
                clearDueAt: clearDueAt,
                priority: priority,
                recurrenceRule: recurrence
              )
            }
          )
          .id(task.id)
          .onDrop(
            of: [.plainText],
            delegate: TaskDropDelegate(
              target: task,
              category: category,
              viewModel: viewModel
            )
          )

          if viewModel.isInlineCreating && viewModel.inlineCreateAfterTaskId == task.id {
            InlineTaskCreationRow(
              text: $inlineText,
              isFocused: inlineFocused,
              onCommit: commitInline,
              onCancel: cancelInline
            )
          }

          if index == tasks.count - 1 {
            Color.clear.frame(height: 1)
              .onDrop(
                of: [.plainText],
                delegate: TaskDropDelegate(
                  target: nil,
                  category: category,
                  viewModel: viewModel
                )
              )
          }
        }
      }
    }
  }
}

private struct TaskDropDelegate: DropDelegate {
  let target: TaskActionItem?
  let category: TaskCategory
  let viewModel: TasksViewModel

  func dropEntered(info: DropInfo) {
    viewModel.dropTargetTaskId = target?.id
  }

  func dropExited(info: DropInfo) {
    if viewModel.dropTargetTaskId == target?.id { viewModel.dropTargetTaskId = nil }
  }

  func performDrop(info: DropInfo) -> Bool {
    guard let draggedID = viewModel.draggedTaskId, let task = viewModel.findTask(draggedID) else { return false }
    viewModel.dropTargetTaskId = nil
    viewModel.draggedTaskId = nil
    Task { @MainActor in
      await viewModel.reorderTask(task, before: target, in: category)
    }
    return true
  }
}

// MARK: - Row

struct TaskRow: View {
  let task: TaskActionItem
  let isKeyboardSelected: Bool
  let isEditing: Bool
  let canDrag: Bool
  let onSelect: () -> Void
  let onStartEditing: () -> Void
  let onFinishEditing: () -> Void
  let onToggle: () async -> Void
  let onDelete: () async -> Void
  let onUpdate:
    (_ description: String?, _ dueAt: Date?, _ clearDueAt: Bool, _ priority: String?, _ recurrence: String?) async ->
      Void

  @State private var text: String
  @State private var showDetails = false
  @State private var hovered = false
  @State private var editTask: Task<Void, Never>?
  @State private var swipeOffset: CGFloat = 0
  @FocusState private var focused: Bool

  init(
    task: TaskActionItem,
    isKeyboardSelected: Bool,
    isEditing: Bool,
    canDrag: Bool,
    onSelect: @escaping () -> Void,
    onStartEditing: @escaping () -> Void,
    onFinishEditing: @escaping () -> Void,
    onToggle: @escaping () async -> Void,
    onDelete: @escaping () async -> Void,
    onUpdate: @escaping (String?, Date?, Bool, String?, String?) async -> Void
  ) {
    self.task = task
    self.isKeyboardSelected = isKeyboardSelected
    self.isEditing = isEditing
    self.canDrag = canDrag
    self.onSelect = onSelect
    self.onStartEditing = onStartEditing
    self.onFinishEditing = onFinishEditing
    self.onToggle = onToggle
    self.onDelete = onDelete
    self.onUpdate = onUpdate
    _text = State(initialValue: task.description)
  }

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      if canDrag {
        Image(systemName: "line.3.horizontal")
          .foregroundColor(OmiColors.textTertiary)
          .onDrag {
            onSelect()
            return NSItemProvider(object: task.id as NSString)
          } preview: {
            Text(task.description)
              .lineLimit(1)
              .padding(OmiSpacing.sm)
              .background(OmiColors.backgroundSecondary)
              .cornerRadius(OmiChrome.elementRadius)
          }
          .simultaneousGesture(TapGesture().onEnded { onSelect() })
      }

      Button {
        Task { await onToggle() }
      } label: {
        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
          .foregroundColor(task.completed ? OmiColors.textSecondary : OmiColors.textTertiary)
      }
      .buttonStyle(.plain)

      if isEditing {
        TextField("Task", text: $text)
          .textFieldStyle(.plain)
          .focused($focused)
          .onSubmit { saveAndExit() }
          .onExitCommand { saveAndExit() }
          .onChange(of: text) { _, _ in scheduleDebouncedSave() }
          .onChange(of: focused) { _, active in if !active { saveAndExit() } }
          .onAppear {
            focused = true
            text = task.description
          }
      } else {
        Text(task.description)
          .scaledFont(size: OmiType.body)
          .foregroundColor(task.completed ? OmiColors.textTertiary : OmiColors.textPrimary)
          .strikethrough(task.completed)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onTapGesture(count: 2) { onStartEditing() }
          .onTapGesture { onSelect() }
      }

      if Date().timeIntervalSince(task.createdAt) < 60 { NewBadge() }

      if task.source != nil, task.source != "manual", !(task.provenance ?? []).isEmpty {
        TaskWhyButton(task: task)
      }

      if !task.completed {
        TaskDueButton(task: task, onUpdate: onUpdate)
        TaskPriorityButton(task: task, onUpdate: onUpdate)
      }

      TaskDetailButton(task: task, showDetail: $showDetails)

      if hovered {
        Button {
          Task { await onDelete() }
        } label: {
          Image(systemName: "trash").foregroundColor(OmiColors.textTertiary)
        }
        .buttonStyle(.plain)
        .help("Delete task (⌘D)")
      }
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
        .fill(isKeyboardSelected ? OmiColors.backgroundTertiary : OmiColors.backgroundSecondary)
    )
    .offset(x: swipeOffset)
    .contentShape(Rectangle())
    .onHover { hovered = $0 }
    .gesture(
      DragGesture(minimumDistance: 20)
        .onChanged { value in
          guard !canDrag || abs(value.translation.width) > abs(value.translation.height) else { return }
          swipeOffset = min(0, value.translation.width)
        }
        .onEnded { value in
          if value.translation.width < -80 { Task { await onDelete() } }
          withAnimation { swipeOffset = 0 }
        }
    )
    .sheet(isPresented: $showDetails) { TaskDetailView(task: task) }
  }

  private func scheduleDebouncedSave() {
    editTask?.cancel()
    let value = text
    editTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, trimmed != task.description { await onUpdate(trimmed, nil, false, nil, nil) }
    }
  }

  private func saveAndExit() {
    editTask?.cancel()
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      text = task.description
    } else if trimmed != task.description {
      Task { await onUpdate(trimmed, nil, false, nil, nil) }
    }
    focused = false
    onFinishEditing()
  }
}

private struct TaskDueButton: View {
  let task: TaskActionItem
  let onUpdate: (String?, Date?, Bool, String?, String?) async -> Void
  @State private var showing = false
  @State private var draftDate: Date

  init(task: TaskActionItem, onUpdate: @escaping (String?, Date?, Bool, String?, String?) async -> Void) {
    self.task = task
    self.onUpdate = onUpdate
    _draftDate = State(initialValue: task.dueAt ?? Date())
  }

  var body: some View {
    Button {
      showing.toggle()
    } label: {
      Label(label, systemImage: "calendar")
        .labelStyle(.titleAndIcon)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textTertiary)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showing) {
      VStack(alignment: .leading, spacing: OmiSpacing.md) {
        DatePicker("Deadline", selection: $draftDate)
          .datePickerStyle(.graphical)
        Picker("Repeat", selection: recurrenceBinding) {
          Text("Never").tag("")
          Text("Daily").tag("daily")
          Text("Weekdays").tag("weekdays")
          Text("Weekly").tag("weekly")
          Text("Every 2 Weeks").tag("biweekly")
          Text("Monthly").tag("monthly")
        }
        HStack {
          if task.dueAt != nil {
            Button("Remove deadline") {
              showing = false
              Task { await onUpdate(nil, nil, true, nil, task.recurrenceRule) }
            }
          }
          Spacer()
          Button("Cancel") { showing = false }
          Button("Save") {
            showing = false
            Task { await onUpdate(nil, draftDate, false, nil, task.recurrenceRule) }
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .padding(OmiSpacing.lg)
      .frame(width: 340)
    }
  }

  private var recurrenceBinding: Binding<String> {
    Binding(
      get: { task.recurrenceRule ?? "" },
      set: { value in Task { await onUpdate(nil, nil, false, nil, value) } }
    )
  }

  private var label: String {
    guard let due = task.dueAt else { return "Set date" }
    return due.formatted(date: .abbreviated, time: .shortened)
  }
}

private struct TaskPriorityButton: View {
  let task: TaskActionItem
  let onUpdate: (String?, Date?, Bool, String?, String?) async -> Void

  var body: some View {
    Menu {
      ForEach(["high", "medium", "low"], id: \.self) { priority in
        Button {
          Task { await onUpdate(nil, nil, false, priority, nil) }
        } label: {
          Label(priority.capitalized, systemImage: task.priority == priority ? "checkmark" : "flag")
        }
      }
    } label: {
      Text(task.priority?.capitalized ?? "+ Priority")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textTertiary)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }
}

private struct TaskWhyButton: View {
  let task: TaskActionItem
  @State private var showing = false

  var body: some View {
    Button(task.source == "screenshot" ? "Why Intentive added this" : "Why") { showing.toggle() }
      .buttonStyle(.plain)
      .scaledFont(size: OmiType.caption)
      .foregroundColor(OmiColors.textTertiary)
      .accessibilityIdentifier("task-why-\(task.id)")
      .popover(isPresented: $showing) {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          Text(task.source == "screenshot" ? "Why Intentive added this" : "Why")
            .scaledFont(size: OmiType.body, weight: .semibold)
          Text("This task came from \(task.sourceAppLabel.lowercased()) context.")
          Text("\((task.provenance ?? []).count) linked source\((task.provenance ?? []).count == 1 ? "" : "s")")
            .foregroundColor(OmiColors.textTertiary)
        }
        .padding(OmiSpacing.md)
        .frame(width: 280, alignment: .leading)
      }
  }
}

struct NewBadge: View {
  var body: some View {
    Text("New")
      .scaledFont(size: OmiType.micro, weight: .semibold)
      .foregroundColor(OmiColors.textSecondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(OmiColors.backgroundTertiary))
  }
}

struct InlineTaskCreationRow: View {
  @Binding var text: String
  var isFocused: FocusState<Bool>.Binding
  let onCommit: () -> Void
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: "circle").foregroundColor(OmiColors.textTertiary)
      TextField("New task", text: $text)
        .textFieldStyle(.plain)
        .focused(isFocused)
        .onSubmit(onCommit)
        .onExitCommand(perform: onCancel)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .background(OmiColors.backgroundSecondary)
    .cornerRadius(OmiChrome.elementRadius)
  }
}

struct UndoToastView: View {
  let taskDescription: String
  let undoCount: Int
  let onUndo: () -> Void

  var body: some View {
    HStack(spacing: OmiSpacing.md) {
      Text(undoCount == 1 ? "Deleted \(taskDescription)" : "Deleted \(undoCount) tasks")
        .lineLimit(1)
      Button("Undo", action: onUndo).buttonStyle(.plain).fontWeight(.semibold)
    }
    .scaledFont(size: OmiType.body)
    .padding(.horizontal, OmiSpacing.lg)
    .padding(.vertical, OmiSpacing.sm)
    .background(.ultraThinMaterial)
    .cornerRadius(OmiChrome.elementRadius)
    .shadow(radius: 8)
  }
}

struct KeyboardHintBar: View {
  let isEditing: Bool
  let isInlineCreating: Bool
  let hasSelection: Bool

  var body: some View {
    Text(
      isEditing || isInlineCreating
        ? "Return Save  ·  Escape Save & exit"
        : (hasSelection
          ? "↑↓ Move  ·  Return New below  ·  Return twice Edit  ·  Space Complete  ·  ⌘D Delete  ·  ⌘N New"
          : "↑↓ Select  ·  ⌘N New")
    )
    .scaledFont(size: OmiType.caption)
    .foregroundColor(OmiColors.textTertiary)
    .padding(.vertical, OmiSpacing.sm)
  }
}
