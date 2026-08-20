import Combine
import Foundation

protocol FocusSessionPersisting: Sendable {
  func persistPruneFocusSessions(authorization: LocalMutationAuthorization) async throws
  func persistFocusSessions(from: Date, to: Date, limit: Int) async throws
    -> [FocusSessionRecord]
  func persistDeleteFocusSession(
    id: Int64,
    authorization: LocalMutationAuthorization
  ) async throws
  func persistClearFocusSessions(authorization: LocalMutationAuthorization) async throws
}

extension ProactiveStorage: FocusSessionPersisting {
  func persistPruneFocusSessions(authorization: LocalMutationAuthorization) async throws {
    try await pruneFocusSessions(authorization: authorization)
  }

  func persistFocusSessions(from: Date, to: Date, limit: Int) async throws
    -> [FocusSessionRecord]
  {
    try await getFocusSessions(from: from, to: to, limit: limit)
  }

  func persistDeleteFocusSession(
    id: Int64,
    authorization: LocalMutationAuthorization
  ) async throws {
    try await deleteFocusSession(id: id, authorization: authorization)
  }

  func persistClearFocusSessions(authorization: LocalMutationAuthorization) async throws {
    try await clearFocusSessions(authorization: authorization)
  }
}

/// Stored focus session with additional metadata
struct StoredFocusSession: Codable, Identifiable {
  let id: String
  let status: FocusStatus
  let appOrSite: String
  let description: String
  let message: String?
  let createdAt: Date
  let durationSeconds: Int?

  init(
    id: String = UUID().uuidString,
    status: FocusStatus,
    appOrSite: String,
    description: String,
    message: String? = nil,
    createdAt: Date = Date(),
    durationSeconds: Int? = nil
  ) {
    self.id = id
    self.status = status
    self.appOrSite = appOrSite
    self.description = description
    self.message = message
    self.createdAt = createdAt
    self.durationSeconds = durationSeconds
  }
}

/// Focus statistics for a day
struct FocusDayStats {
  let date: Date
  let focusedMinutes: Int
  let distractedMinutes: Int
  let sessionCount: Int
  let focusedCount: Int
  let distractedCount: Int

  /// Focus rate as a percentage (0-100), based on time spent
  var focusRate: Double {
    let total = focusedMinutes + distractedMinutes
    guard total > 0 else { return 0 }
    return Double(focusedMinutes) / Double(total) * 100
  }
}

/// Local storage manager for focus session history
@MainActor
class FocusStorage: ObservableObject {
  static let shared = FocusStorage()

  @Published private(set) var sessions: [StoredFocusSession] = []
  @Published private(set) var currentStatus: FocusStatus?
  @Published private(set) var currentApp: String?
  @Published private(set) var lastError: String?

  // MARK: - Real-time Status Properties

  /// The currently detected app (updated immediately on app switch, before analysis)
  @Published private(set) var detectedAppName: String?

  /// When the analysis delay period will end (nil if not in delay)
  @Published private(set) var delayEndTime: Date?

  /// When the analysis cooldown period will end (nil if not in cooldown)
  @Published private(set) var cooldownEndTime: Date?

  private static let retiredStorageKey: DefaultsKey = .retiredFocusSessions
  private let maxStoredSessions = 500
  private let persistence: any FocusSessionPersisting
  private let automaticallyRefresh: Bool
  private var ownerScopeGeneration = 0
  private var cancellables = Set<AnyCancellable>()

  init(
    defaults: UserDefaults = .standard,
    startAutomatically: Bool = true,
    notificationCenter: NotificationCenter = .default,
    persistence: any FocusSessionPersisting = ProactiveStorage.shared
  ) {
    self.persistence = persistence
    automaticallyRefresh = startAutomatically
    defaults.removeObject(forKey: Self.retiredStorageKey)
    notificationCenter.publisher(for: .runtimeOwnerDidChange)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          self?.resetForCurrentOwner()
        }
      }
      .store(in: &cancellables)
    if startAutomatically {
      Task { await refreshLocal() }
    }
  }

  private func resetForCurrentOwner() {
    ownerScopeGeneration += 1
    sessions = []
    currentStatus = nil
    currentApp = nil
    lastError = nil
    clearRealtimeStatus()
    if automaticallyRefresh {
      Task { await refreshLocal() }
    }
  }

  // MARK: - Real-time Status Updates

  /// Update the detected app name (called immediately on app switch)
  func updateDetectedApp(_ appName: String?) {
    detectedAppName = appName
  }

  /// Update the delay end time (called when delay period starts/ends)
  func updateDelayEndTime(_ endTime: Date?) {
    delayEndTime = endTime
  }

  /// Update the cooldown end time (called by FocusAssistant when cooldown starts/ends)
  func updateCooldownEndTime(_ endTime: Date?) {
    cooldownEndTime = endTime
  }

  /// Clear all real-time status (called when monitoring stops)
  func clearRealtimeStatus() {
    detectedAppName = nil
    delayEndTime = nil
    cooldownEndTime = nil
  }

  // MARK: - Public Methods

  /// Publish a session only after the authoritative SQLite insert returned its local id.
  func addSession(from analysis: ScreenAnalysis, sqliteId: Int64) {
    let session = StoredFocusSession(
      id: String(sqliteId),
      status: analysis.status,
      appOrSite: analysis.appOrSite,
      description: analysis.description,
      message: analysis.message
    )

    // Update status before inserting session to reduce @Published change count
    // (insert triggers sessions change, so update others only if different)
    if currentStatus != analysis.status {
      currentStatus = analysis.status
    }
    if currentApp != analysis.appOrSite {
      currentApp = analysis.appOrSite
    }

    sessions.insert(session, at: 0)

    // Trim if needed
    if sessions.count > maxStoredSessions {
      sessions = Array(sessions.prefix(maxStoredSessions))
    }

  }

  /// Get today's sessions
  var todaySessions: [StoredFocusSession] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    return sessions.filter { calendar.isDate($0.createdAt, inSameDayAs: today) }
  }

  /// Compute duration for each session based on time until the next session.
  /// Sessions array is newest-first; the most recent session's duration is `now - createdAt`.
  nonisolated static func computeStats(
    for sessionList: [StoredFocusSession],
    now: Date = Date()
  ) -> FocusDayStats {
    var focusedSeconds = 0
    var distractedSeconds = 0
    var focusedCount = 0
    var distractedCount = 0
    // Sessions are newest-first, so iterate and compute duration from each session
    // to the next one (which is the one that came before it chronologically).
    for i in 0..<sessionList.count {
      let session = sessionList[i]
      // Duration = time from this session's start until the next session starts (or now)
      let endTime: Date
      if i == 0 {
        // Most recent session — duration extends to now
        endTime = now
      } else {
        // Ended when the next (more recent) session started
        endTime = sessionList[i - 1].createdAt
      }
      let duration = max(0, Int(endTime.timeIntervalSince(session.createdAt)))

      switch session.status {
      case .focused:
        focusedCount += 1
        focusedSeconds += duration
      case .distracted:
        distractedCount += 1
        distractedSeconds += duration
      }
    }

    return FocusDayStats(
      date: Date(),
      focusedMinutes: focusedSeconds / 60,
      distractedMinutes: distractedSeconds / 60,
      sessionCount: sessionList.count,
      focusedCount: focusedCount,
      distractedCount: distractedCount
    )
  }

  /// Get today's statistics
  var todayStats: FocusDayStats {
    Self.computeStats(for: todaySessions)
  }

  /// Delete a session
  func deleteSession(_ id: String) async {
    let generation = ownerScopeGeneration
    guard sessions.contains(where: { $0.id == id }),
      let sqliteId = Int64(id),
      let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    else { return }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      try await persistence.persistDeleteFocusSession(
        id: sqliteId,
        authorization: authorization)
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      sessions.removeAll { $0.id == id }
      updateCurrentProjection()
      lastError = nil
    } catch {
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      lastError = error.localizedDescription
      logError("FocusStorage: Failed to delete session", error: error)
    }
  }

  /// Clear all sessions
  func clearAll() async {
    let generation = ownerScopeGeneration
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      try await persistence.persistClearFocusSessions(authorization: authorization)
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      sessions = []
      updateCurrentProjection()
      lastError = nil
    } catch {
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      lastError = error.localizedDescription
      logError("FocusStorage: Failed to clear sessions", error: error)
    }
  }

  /// Get sessions for a specific date
  func sessions(for date: Date) -> [StoredFocusSession] {
    let calendar = Calendar.current
    return sessions.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
  }

  /// Refresh focus sessions from the authoritative owner-local SQLite database.
  func refreshLocal() async {
    await loadFromSQLite()
  }

  // MARK: - Private Methods

  /// Load sessions from SQLite (authoritative source)
  private func loadFromSQLite() async {
    let generation = ownerScopeGeneration
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
    do {
      try await persistence.persistPruneFocusSessions(authorization: authorization)

      // Get all focus sessions from SQLite (not just today - get recent ones)
      let calendar = Calendar.current
      let startDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
      let endDate = Date()

      let sqliteSessions = try await persistence.persistFocusSessions(
        from: startDate,
        to: endDate,
        limit: maxStoredSessions
      )

      // Convert to StoredFocusSession
      let converted = sqliteSessions.map { record in
        StoredFocusSession(
          id: String(record.id ?? 0),
          status: record.isFocused ? .focused : .distracted,
          appOrSite: record.appOrSite,
          description: record.description,
          message: record.message,
          createdAt: record.createdAt,
          durationSeconds: record.durationSeconds
        )
      }

      // Update on main thread — skip if data hasn't changed to avoid unnecessary re-renders
      await MainActor.run {
        guard generation == self.ownerScopeGeneration,
          RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
        else { return }
        let newStatus = converted.first?.status
        let newApp = converted.first?.appOrSite

        // Only update if data actually changed
        let sessionsChanged = self.sessions.map(\.id) != converted.map(\.id)
        if sessionsChanged {
          self.sessions = converted
        }
        if self.currentStatus != newStatus {
          self.currentStatus = newStatus
        }
        if self.currentApp != newApp {
          self.currentApp = newApp
        }

        self.lastError = nil
        log("FocusStorage: Loaded \(converted.count) sessions from SQLite (changed: \(sessionsChanged))")
      }
    } catch {
      guard generation == ownerScopeGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      lastError = error.localizedDescription
      logError("Failed to load focus sessions from SQLite", error: error)
    }
  }

  private func updateCurrentProjection() {
    currentStatus = sessions.first?.status
    currentApp = sessions.first?.appOrSite
  }
}
