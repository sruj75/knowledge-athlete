import XCTest

@testable import Omi_Computer

private enum FocusPersistenceTestError: Error {
  case injected
}

private actor FocusPersistenceTestDouble: FocusSessionPersisting {
  let rows: [FocusSessionRecord]
  let failDelete: Bool
  let failClear: Bool
  let pauseLoad: Bool
  private var loadStarted = false
  private var loadStartWaiters: [CheckedContinuation<Void, Never>] = []
  private var loadRelease: CheckedContinuation<Void, Never>?

  init(
    rows: [FocusSessionRecord] = [],
    failDelete: Bool = false,
    failClear: Bool = false,
    pauseLoad: Bool = false
  ) {
    self.rows = rows
    self.failDelete = failDelete
    self.failClear = failClear
    self.pauseLoad = pauseLoad
  }

  func persistPruneFocusSessions(authorization: LocalMutationAuthorization) async throws {}

  func persistFocusSessions(from: Date, to: Date, limit: Int) async throws
    -> [FocusSessionRecord]
  {
    guard pauseLoad else { return Array(rows.prefix(limit)) }
    loadStarted = true
    let waiters = loadStartWaiters
    loadStartWaiters.removeAll()
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { loadRelease = $0 }
    return Array(rows.prefix(limit))
  }

  func persistDeleteFocusSession(
    id: Int64,
    authorization: LocalMutationAuthorization
  ) async throws {
    if failDelete { throw FocusPersistenceTestError.injected }
  }

  func persistClearFocusSessions(authorization: LocalMutationAuthorization) async throws {
    if failClear { throw FocusPersistenceTestError.injected }
  }

  func waitUntilLoadStarts() async {
    guard !loadStarted else { return }
    await withCheckedContinuation { loadStartWaiters.append($0) }
  }

  func releaseLoad() {
    loadRelease?.resume()
    loadRelease = nil
  }
}

@MainActor
final class FocusLifecycleBehaviorTests: XCTestCase {
  private let ownerFixture = RuntimeOwnerAuthorityTestFixture()

  override func setUp() async throws {
    await ownerFixture.establish(authOwnerID: "focus-lifecycle-owner-a")
  }

  override func tearDown() async throws {
    await ownerFixture.restore()
  }

  func testLegacyUserDefaultsCacheIsDeletedAndNeverProjected() throws {
    let suiteName = "focus-lifecycle-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let legacySession = StoredFocusSession(
      id: "cloud-id",
      status: .focused,
      appOrSite: "Wrong owner",
      description: "Persisted projection must not be an authority"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    defaults.set(try encoder.encode([legacySession]), forKey: .retiredFocusSessions)

    let storage = FocusStorage(defaults: defaults, startAutomatically: false)

    XCTAssertEqual(storage.sessions.count, 0)
    XCTAssertNil(defaults.object(forKey: .retiredFocusSessions))
  }

  func testCurrentPeriodExtendsToNowAndOlderPeriodEndsAtNextTransition() {
    let now = Date(timeIntervalSince1970: 1_730_000_000)
    let sessions = [
      StoredFocusSession(
        id: "2",
        status: .distracted,
        appOrSite: "Browser",
        description: "Brief detour",
        createdAt: now.addingTimeInterval(-120),
        durationSeconds: 60
      ),
      StoredFocusSession(
        id: "1",
        status: .focused,
        appOrSite: "Xcode",
        description: "Implementation",
        createdAt: now.addingTimeInterval(-600),
        durationSeconds: 480
      ),
    ]

    let stats = FocusStorage.computeStats(for: sessions, now: now)

    XCTAssertEqual(stats.focusedMinutes, 8)
    XCTAssertEqual(stats.distractedMinutes, 2)
  }

  func testDeleteAndClearFailureKeepProjectionAndExposeError() async {
    let persistence = FocusPersistenceTestDouble(failDelete: true, failClear: true)
    let storage = FocusStorage(startAutomatically: false, persistence: persistence)
    storage.addSession(
      from: ScreenAnalysis(
        status: .focused,
        appOrSite: "Xcode",
        description: "Implementing Focus",
        message: nil),
      sqliteId: 42)

    await storage.deleteSession("42")
    XCTAssertEqual(storage.sessions.map(\.id), ["42"])
    XCTAssertNotNil(storage.lastError)

    await storage.clearAll()
    XCTAssertEqual(storage.sessions.map(\.id), ["42"])
    XCTAssertNotNil(storage.lastError)
  }

  func testOwnerScopeResetRejectsLateRefreshProjection() async {
    let center = NotificationCenter()
    let persistence = FocusPersistenceTestDouble(
      rows: [
        FocusSessionRecord(
          id: 7,
          status: "focused",
          appOrSite: "Owner A app",
          description: "Private owner-A focus row")
      ],
      pauseLoad: true)
    let storage = FocusStorage(
      startAutomatically: false,
      notificationCenter: center,
      persistence: persistence)
    let refresh = Task { await storage.refreshLocal() }
    await persistence.waitUntilLoadStarts()

    center.post(name: .runtimeOwnerDidChange, object: nil)
    await persistence.releaseLoad()
    await refresh.value

    XCTAssertTrue(storage.sessions.isEmpty)
    XCTAssertNil(storage.lastError)
  }
}
