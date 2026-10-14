import GRDB
import OmiSupport
import XCTest

@testable import Omi_Computer

private final class OwnerDatabaseCommitObserver: TransactionObserver, @unchecked Sendable {
  private let releaseCommit = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var reachedWillCommit = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { true }
  func databaseDidChange(with event: DatabaseEvent) {}

  func databaseWillCommit() throws {
    let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      reachedWillCommit = true
      let pending = waiters
      waiters.removeAll()
      return pending
    }
    pending.forEach { $0.resume() }
    releaseCommit.wait()
  }

  func databaseDidCommit(_ db: Database) {}
  func databaseDidRollback(_ db: Database) {}

  func waitUntilWillCommit() async {
    if lock.withLock({ reachedWillCommit }) { return }
    await withCheckedContinuation { continuation in
      let shouldResume = lock.withLock { () -> Bool in
        guard !reachedWillCommit else { return true }
        waiters.append(continuation)
        return false
      }
      if shouldResume { continuation.resume() }
    }
  }

  func allowCommit() {
    releaseCommit.signal()
  }
}

@MainActor
final class EffectiveOwnerDatabaseBoundaryTests: XCTestCase {
  private var originalAuthOwner: String?
  private var originalOverride: String?
  private var originalBackup: String?
  private var createdOwnerIDs: [String] = []
  private var temporaryApplicationSupportDirectory: URL?

  override func setUp() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("effective-owner-boundary-\(UUID().uuidString)", isDirectory: true)
    temporaryApplicationSupportDirectory = temporaryDirectory
    let storageLocation = RewindDatabaseStorageLocation(
      applicationSupportDirectoryURL: temporaryDirectory,
      productPathComponents: ["Intentive"])
    DesktopLocalProfile.configureApplicationSupportURLForTesting(storageLocation.productRootURL)
    await RewindDatabase.shared.close()
    await RewindDatabase.shared.configureStorageLocationForTesting(storageLocation)

    originalAuthOwner = UserDefaults.standard.string(forKey: .authUserId)
    originalOverride = UserDefaults.standard.string(forKey: .automationOwnerOverride)
    originalBackup = UserDefaults.standard.string(forKey: .automationOwnerABackup)
    try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
      allowAutomationOverride: true,
      plannedNextOwner: { _, _ in nil }
    ) { defaults in
      defaults.removeObject(forKey: .authUserId)
      defaults.removeObject(forKey: .automationOwnerOverride)
      defaults.removeObject(forKey: .automationOwnerABackup)
    }
    await RewindDatabase.shared.close()
  }

  override func tearDown() async throws {
    await RewindDatabase.shared.close()
    let authOwner = originalAuthOwner
    let override = originalOverride
    let backup = originalBackup
    try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
      allowAutomationOverride: true,
      plannedNextOwner: { _, _ in
        let normalizedOverride = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedOverride, !normalizedOverride.isEmpty { return normalizedOverride }
        return authOwner?.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    ) { defaults in
      Self.restore(authOwner, forKey: .authUserId, in: defaults)
      Self.restore(override, forKey: .automationOwnerOverride, in: defaults)
      Self.restore(backup, forKey: .automationOwnerABackup, in: defaults)
    }
    for ownerID in createdOwnerIDs {
      try? FileManager.default.removeItem(at: userDirectory(ownerID))
    }
    createdOwnerIDs = []
    await RewindDatabase.shared.configureStorageLocationForTesting(nil)
    DesktopLocalProfile.configureApplicationSupportURLForTesting(nil)
    if let temporaryApplicationSupportDirectory {
      try? FileManager.default.removeItem(at: temporaryApplicationSupportDirectory)
    }
    temporaryApplicationSupportDirectory = nil
  }

  private func setOwner(_ ownerID: String) async {
    do {
      try await RuntimeOwnerIdentity.performEffectiveOwnerTransition(
        allowAutomationOverride: false,
        plannedNextOwner: { _, _ in ownerID }
      ) { defaults in
        defaults.set(ownerID, forKey: .authUserId)
      }
    } catch {
      XCTFail("owner transition failed: \(error)")
    }
  }

  private func readProbeValues(ownerID: String) throws -> [String] {
    let pool = try DatabasePool(
      path: userDirectory(ownerID).appendingPathComponent("heyintentive.db").path)
    return try pool.read { db in
      try String.fetchAll(db, sql: "SELECT value FROM owner_probe ORDER BY rowid")
    }
  }

  private func makeOwnerID(_ prefix: String) -> String {
    let ownerID = "\(prefix)-\(UUID().uuidString)"
    createdOwnerIDs.append(ownerID)
    return ownerID
  }

  private func userDirectory(_ ownerID: String) -> URL {
    DesktopLocalProfile.applicationSupportURL()
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(ownerID, isDirectory: true)
  }

  nonisolated private static func restore(
    _ value: String?,
    forKey key: DefaultsKey,
    in defaults: UserDefaults
  ) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

}
