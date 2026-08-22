import XCTest

@testable import Omi_Computer

private actor HomeTaskReadGate {
  private var entered = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func pause() async {
    entered = true
    enteredContinuation?.resume()
    enteredContinuation = nil
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { enteredContinuation = $0 }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

@MainActor
final class HomeShellOwnerTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture?.establish(authOwnerID: "home-owner-a")
  }

  override func tearDown() async throws {
    await ownerFixture?.restore()
    ownerFixture = nil
  }

  func testTasksStorePublishesTheExactHomeRowsAndCount() async {
    let store = TasksStore(observesNotifications: false)
    let rows = [task(id: "task-a"), task(id: "task-b")]

    await store.loadHomeTasks {
      TasksStore.HomeTaskSnapshot(tasks: rows, openCount: 7)
    }

    XCTAssertEqual(store.homeTasks.map(\.id), ["task-a", "task-b"])
    XCTAssertEqual(store.openTaskCount, 7)
    XCTAssertNil(store.homeTaskError)
  }

  func testSuspendedHomeReadCannotPublishAfterOwnerChanges() async {
    let store = TasksStore(observesNotifications: false)
    let gate = HomeTaskReadGate()
    let refresh = Task { @MainActor in
      await store.loadHomeTasks {
        await gate.pause()
        return TasksStore.HomeTaskSnapshot(tasks: [self.task(id: "stale")], openCount: 1)
      }
    }

    await gate.waitUntilEntered()
    await ownerFixture?.establish(authOwnerID: "home-owner-b")
    store.resetSessionState()
    await gate.release()
    await refresh.value

    XCTAssertTrue(store.homeTasks.isEmpty)
    XCTAssertEqual(store.openTaskCount, 0)
  }

  /// Source-inspection tripwire for an intentional owner deletion. The observable behavior above
  /// proves the surviving store; this assertion keeps the former parallel projection from returning.
  func testDashboardViewModelAndDuplicateHomeListAreGone() throws {
    let desktopRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
    // omi-test-quality: source-inspection -- static contract: DashboardViewModel and the duplicate Home list are intentional deletion boundaries; TasksStore behavior and owner fencing are exercised by the tests above.
    let dashboardSource = try String(
      contentsOf: desktopRoot.appendingPathComponent("Sources/MainWindow/Pages/DashboardPage.swift"),
      encoding: .utf8)
    // omi-test-quality: source-inspection -- static contract: ViewModelContainer must not restore the retired DashboardViewModel owner; the surviving TasksStore projection is exercised behaviorally above.
    let containerSource = try String(
      contentsOf: desktopRoot.appendingPathComponent("Sources/ViewModelContainer.swift"),
      encoding: .utf8)

    XCTAssertFalse(dashboardSource.contains("DashboardViewModel"))
    XCTAssertFalse(containerSource.contains("dashboardViewModel"))
    XCTAssertEqual(dashboardSource.components(separatedBy: "      homeKnowsList\n").count - 1, 1)
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
