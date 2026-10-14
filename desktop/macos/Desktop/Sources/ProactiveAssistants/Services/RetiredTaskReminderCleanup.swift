import Foundation
import OmiSupport

/// Upgrade cleanup for the retired Tasks feature. Historical task rows remain
/// available to export; only notifications created by that feature are removed.
@MainActor
enum RetiredTaskReminderCleanup {
  static func identifiersToRemove(from identifiers: [String]) -> [String] {
    identifiers.filter { $0.hasPrefix("com.heyintentive.intentive.task-reminder.") }
  }

  static func removePendingReminders() async {
    let identifiers: [String] = await withCheckedContinuation { continuation in
      UserNotificationCallbackBridge.pendingRequests { requests in
        continuation.resume(returning: requests.map(\.identifier))
      }
    }
    UserNotificationCallbackBridge.removePendingRequests(
      withIdentifiers: identifiersToRemove(from: identifiers))
  }
}
