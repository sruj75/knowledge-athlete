import Foundation

/// A narrow, local handoff from Home into the existing Tasks presentation.
/// It carries navigation intent only; task/candidate storage remains owned by
/// the corresponding local stores.
@MainActor
final class TaskNavigationRequestStore {
  static let shared = TaskNavigationRequestStore()

  enum Target: Equatable {
    case task(String)
  }

  private(set) var pendingTarget: Target?
  private(set) var pendingTask: TaskActionItem?

  func request(task: TaskActionItem) {
    pendingTarget = .task(task.id)
    pendingTask = task
  }

  func peek() -> Target? { pendingTarget }

  func consumeIfAvailable(taskIDs: Set<String>) -> Target? {
    guard let target = pendingTarget else { return nil }
    let isAvailable: Bool
    switch target {
    case .task(let id): isAvailable = taskIDs.contains(id)
    }
    guard isAvailable else { return nil }
    clear()
    return target
  }

  private func clear() {
    pendingTarget = nil
    pendingTask = nil
  }
}
