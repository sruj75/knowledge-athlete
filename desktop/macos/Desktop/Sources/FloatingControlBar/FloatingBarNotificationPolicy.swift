import Foundation

enum OwnerBoundNotificationPresentationResult: Equatable {
  case rejectedOwnerChange
  case windowUnavailable
  case suppressed
  case queued
  case presented
}

enum ProactiveNotificationInteraction: Sendable {
  case click
  case dismiss
  case timeout
}

enum ProactiveNotificationInteractionEffect: Equatable, Sendable {
  case openLocalChat
  case presentationOnly
  case rejectOwnerChange
}

enum ProactiveNotificationContinuityPolicy {
  static let journalOrigin = "proactive_notification"

  static func effect(
    for interaction: ProactiveNotificationInteraction,
    notificationOwnerID: String,
    currentOwnerID: String?
  ) -> ProactiveNotificationInteractionEffect {
    guard !notificationOwnerID.isEmpty, notificationOwnerID == currentOwnerID else {
      return .rejectOwnerChange
    }
    switch interaction {
    case .click: return .openLocalChat
    case .dismiss, .timeout: return .presentationOnly
    }
  }
}

/// Lets a click wait for an already-started canonical journal admission instead
/// of racing the async write and silently losing the requested chat open.
@MainActor
final class NotificationJournalAdmissionWaiters<Key: Hashable> {
  private var waiters: [Key: [CheckedContinuation<Bool, Never>]] = [:]

  func wait(for key: Key, isAdmitted: Bool, isPending: Bool) async -> Bool {
    if isAdmitted { return true }
    guard isPending else { return false }
    return await withCheckedContinuation { continuation in
      waiters[key, default: []].append(continuation)
    }
  }

  func resolve(_ key: Key, admitted: Bool) {
    let pending = waiters.removeValue(forKey: key) ?? []
    pending.forEach { $0.resume(returning: admitted) }
  }

  func cancelAll() {
    let pending = waiters.values.flatMap { $0 }
    waiters.removeAll()
    pending.forEach { $0.resume(returning: false) }
  }
}
