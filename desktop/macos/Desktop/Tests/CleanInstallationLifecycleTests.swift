import GRDB
import OmiSupport
import XCTest

@testable import Omi_Computer

private final class CleanInstallationAccessRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [String] = []

  func record(_ path: String) {
    lock.withLock { paths.append(path) }
  }

  func snapshot() -> [String] {
    lock.withLock { paths }
  }
}

@MainActor
final class CleanInstallationLifecycleTests: XCTestCase {
  func testOwnedResetSignOutOwnerSwitchAndReinstallPreserveOrdinaryData() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("clean-install-lifecycle-\(UUID().uuidString)", isDirectory: true)
    let applicationSupportBase =
      temporaryRoot
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    let foreignRoot = applicationSupportBase.appendingPathComponent("Omi", isDirectory: true)
    let foreignSentinel = foreignRoot.appendingPathComponent("foreign-sentinel.txt")
    let ownRoot = applicationSupportBase.appendingPathComponent("Intentive", isDirectory: true)
    let appBundle = temporaryRoot.appendingPathComponent("Applications/Intentive.app", isDirectory: true)
    let defaultsSuite = "CleanInstallationLifecycleTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    let bundleIdentifier = DesktopProductIdentity.stableBundleIdentifier
    let ownerA = "owner-a"
    let ownerB = "owner-b"
    var keychainInstallID: String?
    let accessRecorder = CleanInstallationAccessRecorder()

    defer {
      RewindDatabase.currentUserId = nil
      defaults.removePersistentDomain(forName: defaultsSuite)
      try? FileManager.default.removeItem(at: temporaryRoot)
    }

    try FileManager.default.createDirectory(at: foreignRoot, withIntermediateDirectories: true)
    try Data("foreign-data-must-remain-untouched".utf8).write(to: foreignSentinel)
    try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)

    let fileSystem = RewindDatabaseFileSystem { _, path in accessRecorder.record(path) }
    let storageLocation = RewindDatabaseStorageLocation(
      applicationSupportDirectoryURL: applicationSupportBase,
      productPathComponents: ["Intentive"])
    let database = RewindDatabase(storageLocation: storageLocation, fileSystem: fileSystem)

    let originalDevice = ClientDeviceService(
      bundleIdentifier: bundleIdentifier,
      userDefaults: defaults,
      keychainReader: {
        if let keychainInstallID { return .found(keychainInstallID) }
        return .missing
      },
      keychainWriter: { keychainInstallID = $0 })
    let originalDeviceHash = originalDevice.deviceIdHash
    XCTAssertNotNil(keychainInstallID)

    try await writeProbe("A-before-switch", ownerID: ownerA, database: database)
    try await writeProbe("B-after-switch", ownerID: ownerB, database: database)
    try await writeProbe("A-after-return", ownerID: ownerA, database: database)
    await database.close()

    defaults.set("keep-this-user-choice", forKey: .transcriptionVocabulary)
    for source in [OnboardingReplaySource.settings, .statusMenu, .automation] {
      defaults.set("setup-only", forKey: .onboardingHowDidYouHearSource)
      let plan = await replayPreparation(defaults: defaults).execute(source: source)
      XCTAssertTrue(plan.shouldRestart)
      XCTAssertNil(defaults.object(forKey: .onboardingHowDidYouHearSource))
      XCTAssertEqual(defaults.string(forKey: .transcriptionVocabulary), "keep-this-user-choice")
    }

    defaults.set("signed-in-owner", forKey: .authUserId)
    let signOut = OnboardingSignOutTransaction(
      preparation: replayPreparation(defaults: defaults),
      captureRuntime: .init(effects: .init(quiesce: {}, restore: { _ in true })),
      commitAuthentication: {
        defaults.removeObject(forKey: .authUserId)
        return true
      },
      isAuthenticationAuthoritative: { true })
    let didSignOut = try await signOut.execute()
    XCTAssertTrue(didSignOut)
    XCTAssertNil(defaults.object(forKey: .authUserId))
    XCTAssertEqual(defaults.string(forKey: .transcriptionVocabulary), "keep-this-user-choice")

    // Removing the app bundle models uninstall. Product data and the scoped
    // installation identity remain available to a later build of the same identity.
    try FileManager.default.removeItem(at: appBundle)
    XCTAssertTrue(FileManager.default.fileExists(atPath: ownRoot.path))
    let reinstalledDevice = ClientDeviceService(
      bundleIdentifier: bundleIdentifier,
      userDefaults: defaults,
      keychainReader: {
        if let keychainInstallID { return .found(keychainInstallID) }
        return .missing
      },
      keychainWriter: { keychainInstallID = $0 })
    XCTAssertEqual(reinstalledDevice.deviceIdHash, originalDeviceHash)

    let reopenedDatabase = RewindDatabase(storageLocation: storageLocation, fileSystem: fileSystem)
    let reopenedOwnerAValues = try await readProbe(ownerID: ownerA, database: reopenedDatabase)
    XCTAssertEqual(reopenedOwnerAValues, ["A-before-switch", "A-after-return"])
    let reopenedOwnerBValues = try await readProbe(ownerID: ownerB, database: reopenedDatabase)
    XCTAssertEqual(reopenedOwnerBValues, ["B-after-switch"])
    await reopenedDatabase.close()

    XCTAssertEqual(try Data(contentsOf: foreignSentinel), Data("foreign-data-must-remain-untouched".utf8))
    let foreignPrefix = foreignRoot.standardizedFileURL.path + "/"
    XCTAssertFalse(
      accessRecorder.snapshot().contains {
        let path = URL(fileURLWithPath: $0).standardizedFileURL.path
        return path == foreignRoot.standardizedFileURL.path || path.hasPrefix(foreignPrefix)
      },
      "The owned lifecycle must not inspect or mutate a foreign Omi root")
  }

  private func replayPreparation(defaults: UserDefaults) -> OnboardingReplayPreparation {
    OnboardingReplayPreparation(
      effects: .init(
        setTranscriptionIntent: { _ in },
        stopTranscription: {},
        setScreenAnalysisIntent: { _ in },
        stopScreenMonitoring: {},
        resetCompletion: {},
        clearPersistedState: { OnboardingFlow.clearPersistedState(in: defaults) },
        clearOnboardingJournal: {},
        resetOnboardingProjection: {}))
  }

  private func writeProbe(
    _ value: String,
    ownerID: String,
    database: RewindDatabase
  ) async throws {
    await database.configure(userId: ownerID)
    try await database.initialize()
    let maybePool = await database.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    try await pool.write { db in
      try db.execute(
        sql: "CREATE TABLE IF NOT EXISTS clean_install_probe (value TEXT NOT NULL)")
      try db.execute(
        sql: "INSERT INTO clean_install_probe(value) VALUES (?)",
        arguments: [value])
    }
  }

  private func readProbe(
    ownerID: String,
    database: RewindDatabase
  ) async throws -> [String] {
    await database.configure(userId: ownerID)
    try await database.initialize()
    let maybePool = await database.getDatabaseQueue()
    let pool = try XCTUnwrap(maybePool)
    return try await pool.read { db in
      try String.fetchAll(db, sql: "SELECT value FROM clean_install_probe ORDER BY rowid")
    }
  }
}
