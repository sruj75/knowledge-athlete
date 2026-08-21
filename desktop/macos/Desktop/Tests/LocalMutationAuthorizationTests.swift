import GRDB
import XCTest

@testable import Omi_Computer

private final class MutationAuthorizationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var remainingAllowedChecks: Int

  init(allowedChecks: Int = 3) {
    remainingAllowedChecks = allowedChecks
  }

  func authorization() -> LocalMutationAuthorization {
    LocalMutationAuthorization { [self] in
      lock.lock()
      defer { lock.unlock() }
      guard remainingAllowedChecks > 0 else { return false }
      remainingAllowedChecks -= 1
      return true
    }
  }
}

private final class LocalMutationTransactionObserver: TransactionObserver, @unchecked Sendable {
  private let lock = NSLock()
  private var observedDML = false
  private var rolledBack = false

  func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { true }
  func databaseDidChange(with event: DatabaseEvent) {
    lock.withLock { observedDML = true }
  }
  func databaseWillCommit() throws {}
  func databaseDidCommit(_ db: Database) {}
  func databaseDidRollback(_ db: Database) {
    lock.withLock { rolledBack = true }
  }

  func snapshot() -> (observedDML: Bool, rolledBack: Bool) {
    lock.withLock { (observedDML, rolledBack) }
  }
}

private actor OwnerTransitionTestGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    guard !isOpen else { return }
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}

private final class EffectiveOwnerTransitionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var ownerID: String? = "owner-a"
  private var events: [String] = []
  private var mutationValidatorCalls = 0

  func owner() -> String? { lock.withLock { ownerID } }
  func setOwner(_ ownerID: String?) { lock.withLock { self.ownerID = ownerID } }
  func record(_ event: String) { lock.withLock { events.append(event) } }
  func validateOwnerB() -> Bool {
    lock.withLock {
      mutationValidatorCalls += 1
      events.append("mutation_validator")
      return ownerID == "owner-b"
    }
  }
  func snapshot() -> (ownerID: String?, events: [String], validatorCalls: Int) {
    lock.withLock { (ownerID, events, mutationValidatorCalls) }
  }
}

final class LocalMutationAuthorizationTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(
      userIdPrefix: "owner-bound-local-mutation")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testPostDMLRevocationRollsBackEveryTaskMutationBoundary() async throws {
    let original = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(description: "must remain unchanged", source: "manual"),
      // Fixture setup precedes the revocation gates exercised below.
      authorization: .unrestricted)
    let localID = try XCTUnwrap(original.id)
    let surfacedID = "local_\(localID)"

    let updateObserver = LocalMutationTransactionObserver()
    let maybePool = await RewindDatabase.shared.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    pool.add(transactionObserver: updateObserver, extent: .nextTransaction)

    await assertRevoked {
      try await ActionItemStorage.shared.updateActionItemFields(
        surfacedId: surfacedID,
        description: "must roll back",
        authorization: MutationAuthorizationGate().authorization())
    }
    var fetched = try await ActionItemStorage.shared.getActionItem(id: localID)
    var stored = try XCTUnwrap(fetched)
    XCTAssertEqual(stored.description, "must remain unchanged")
    let updateTransaction = updateObserver.snapshot()
    XCTAssertTrue(updateTransaction.observedDML)
    XCTAssertTrue(updateTransaction.rolledBack)

    await assertRevoked {
      _ = try await ActionItemStorage.shared.setCompletionAndCreateNextOccurrence(
        surfacedId: surfacedID,
        completed: true,
        nextDueAt: nil,
        authorization: MutationAuthorizationGate().authorization())
    }
    fetched = try await ActionItemStorage.shared.getActionItem(id: localID)
    stored = try XCTUnwrap(fetched)
    XCTAssertFalse(stored.completed)

    await assertRevoked {
      try await ActionItemStorage.shared.reorderTask(
        surfacedId: surfacedID,
        dueAt: Date().addingTimeInterval(3_600),
        orderedIds: [surfacedID],
        categoryIndex: 1,
        authorization: MutationAuthorizationGate().authorization())
    }
    fetched = try await ActionItemStorage.shared.getActionItem(id: localID)
    stored = try XCTUnwrap(fetched)
    XCTAssertNil(stored.dueAt)
    XCTAssertNil(stored.sortOrder)

    await assertRevoked {
      try await ActionItemStorage.shared.softDelete(
        surfacedId: surfacedID,
        authorization: MutationAuthorizationGate().authorization())
    }
    fetched = try await ActionItemStorage.shared.getActionItem(id: localID)
    stored = try XCTUnwrap(fetched)
    XCTAssertFalse(stored.deleted)
  }

  func testOwnerQuiescenceCompletesBeforeOwnerMutationAndOwnerBAdmission() async throws {
    let fence = EffectiveOwnerTransitionFence()
    let probe = EffectiveOwnerTransitionProbe()
    let quiescenceEntered = OwnerTransitionTestGate()
    let allowQuiescenceToFinish = OwnerTransitionTestGate()

    let transition = Task {
      try await fence.performEffectiveOwnerTransition(
        currentOwner: { probe.owner() },
        plannedNextOwner: { _ in "owner-b" },
        quiescePreviousOwner: { previousOwner, plannedOwner in
          XCTAssertEqual(previousOwner, "owner-a")
          XCTAssertEqual(plannedOwner, "owner-b")
          probe.record("quiesce_started")
          await quiescenceEntered.open()
          await allowQuiescenceToFinish.wait()
          probe.record("quiesce_finished")
        },
        transition: {
          probe.record("owner_mutation")
          probe.setOwner("owner-b")
        },
        retargetLocalStorage: { _, _ in probe.record("retarget") },
        ownerDidChange: { probe.record("owner_changed") })
    }

    await quiescenceEntered.wait()
    let ownerBMutation = Task {
      let lease = try await fence.acquireMutationLease(validating: {
        probe.validateOwnerB()
      })
      await fence.releaseMutationLease(lease)
    }
    await fence.waitUntilMutationIsPending()

    var snapshot = probe.snapshot()
    XCTAssertEqual(snapshot.ownerID, "owner-a")
    XCTAssertEqual(snapshot.validatorCalls, 0)
    XCTAssertEqual(snapshot.events, ["quiesce_started"])

    await allowQuiescenceToFinish.open()
    try await transition.value
    try await ownerBMutation.value

    snapshot = probe.snapshot()
    XCTAssertEqual(snapshot.ownerID, "owner-b")
    XCTAssertEqual(snapshot.validatorCalls, 1)
    XCTAssertEqual(
      snapshot.events,
      [
        "quiesce_started", "quiesce_finished", "owner_mutation", "retarget",
        "owner_changed", "mutation_validator",
      ])
  }

  func testReadLeaseKeepsOwnerTransitionParkedUntilPhysicalReadFinishes() async throws {
    let probe = EffectiveOwnerTransitionProbe()
    let readEntered = OwnerTransitionTestGate()
    let allowReadToFinish = OwnerTransitionTestGate()
    let authorization = LocalMutationAuthorization {
      probe.owner() == "owner-a"
    }

    let read = Task {
      try await authorization.withReadLease {
        await readEntered.open()
        await allowReadToFinish.wait()
        return probe.owner()
      }
    }

    await readEntered.wait()
    let transition = Task {
      try await EffectiveOwnerTransitionFence.shared.performEffectiveOwnerTransition(
        currentOwner: { probe.owner() },
        plannedNextOwner: { _ in "owner-b" },
        quiescePreviousOwner: { _, _ in },
        transition: { probe.setOwner("owner-b") },
        retargetLocalStorage: { _, _ in },
        ownerDidChange: {})
    }
    await EffectiveOwnerTransitionFence.shared.waitUntilTransitionIsPending()

    XCTAssertEqual(probe.owner(), "owner-a")
    await allowReadToFinish.open()
    let readOwner = try await read.value
    XCTAssertEqual(readOwner, "owner-a")
    try await transition.value
    XCTAssertEqual(probe.owner(), "owner-b")
  }

  private func assertRevoked(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await operation()
      XCTFail("owner-revoked mutation unexpectedly committed", file: file, line: line)
    } catch {
      XCTAssertEqual(
        error as? LocalMutationAuthorizationError,
        .revoked,
        file: file,
        line: line)
    }
  }
}
