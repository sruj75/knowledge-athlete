import XCTest

@testable import Omi_Computer

@MainActor
final class RetiredTaskReminderCleanupTests: XCTestCase {
  func testOnlyRetiredTaskNotificationsAreRemovedAcrossStoredOwners() {
    let taskA = "com.heyintentive.intentive.task-reminder.ownerA.task1"
    let taskB = "com.heyintentive.intentive.task-reminder.ownerB.task2"
    XCTAssertEqual(
      RetiredTaskReminderCleanup.identifiersToRemove(from: [
        taskA, "billing-warning", "com.heyintentive.intentive.task-reminder-other", taskB,
      ]), [taskA, taskB])
  }
}
