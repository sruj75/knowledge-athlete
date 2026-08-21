import Foundation
import GRDB

extension RewindDatabase {
  static func registerConversationsLocalAuthoritativeMigration(on migrator: inout DatabaseMigrator) {
    migrator.registerMigration("makeConversationsLocalAuthoritative") { db in
      let hasSessions = try db.tableExists("transcription_sessions")
      let sessionColumns = hasSessions ? Set(try db.columns(in: "transcription_sessions").map(\.name)) : []

      if sessionColumns.contains("conversationId") && !sessionColumns.contains("backendId") {
        try createConversationAuthorityTables(in: db)
        return
      }

      let legacySessions =
        hasSessions
        ? try Row.fetchAll(db, sql: "SELECT * FROM transcription_sessions ORDER BY id") : []
      let legacySegments =
        try db.tableExists("transcription_segments")
        ? try Row.fetchAll(db, sql: "SELECT * FROM transcription_segments ORDER BY id") : []
      let legacyNotes =
        try db.tableExists("live_notes")
        ? try Row.fetchAll(db, sql: "SELECT * FROM live_notes ORDER BY id") : []

      let segmentsBySession = Dictionary(grouping: legacySegments) { row -> Int64 in row["sessionId"] }
      var usedConversationIds = Set<String>()
      var retainedSessions: [(row: Row, conversationId: String, status: String)] = []
      var retainedSessionIds = Set<Int64>()
      var sourceRewrites: [String: String] = [:]
      var discardedSources = Set<String>()

      for row in legacySessions {
        let id: Int64 = row["id"]
        let discarded = Self.bool(row, "discarded") || Self.bool(row, "deleted")
        let segments = segmentsBySession[id] ?? []
        let legacyStatus = Self.string(row, "status") ?? "failed"
        let finishedAt: Date? = Self.value(row, "finishedAt")
        let irrecoverableEmpty = segments.isEmpty && finishedAt != nil && legacyStatus == "failed"
        let oldIdentifiers = [Self.string(row, "clientConversationId"), Self.string(row, "backendId")]
          .compactMap { $0?.isEmpty == false ? $0 : nil }

        if discarded || irrecoverableEmpty {
          discardedSources.formUnion(oldIdentifiers)
          continue
        }

        let preferred = oldIdentifiers.first(where: { UUID(uuidString: $0) != nil })
        let conversationId: String
        if let preferred, usedConversationIds.insert(preferred).inserted {
          conversationId = preferred
        } else {
          conversationId = Self.uniqueUUID(excluding: &usedConversationIds)
        }

        for identifier in oldIdentifiers where sourceRewrites[identifier] == nil {
          sourceRewrites[identifier] = conversationId
        }

        let status: String
        if legacyStatus == "recording" && finishedAt == nil {
          status = "recording"
        } else if legacyStatus == "completed" || Self.string(row, "conversationStatus") == "completed" {
          status = "completed"
        } else if legacyStatus == "merging" || Self.string(row, "conversationStatus") == "merging" {
          status = "merging"
        } else if !segments.isEmpty {
          status = "finalizing"
        } else {
          status = "failed"
        }

        retainedSessions.append((row, conversationId, status))
        retainedSessionIds.insert(id)
      }

      discardedSources.subtract(sourceRewrites.keys)
      for table in ["action_items", "memories"] where try db.tableExists(table) {
        let columns = Set(try db.columns(in: table).map(\.name))
        guard columns.contains("conversationId") else { continue }
        for (oldId, localId) in sourceRewrites where oldId != localId {
          try db.execute(
            sql: "UPDATE \(table) SET conversationId = ? WHERE conversationId = ?",
            arguments: [localId, oldId])
        }
        for source in discardedSources {
          try db.execute(sql: "DELETE FROM \(table) WHERE conversationId = ?", arguments: [source])
        }
      }

      try db.execute(sql: "DROP INDEX IF EXISTS idx_live_notes_session")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_segments_session")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_sessions_status")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_sessions_synced")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_sessions_backendId")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_sessions_conversationStatus")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_sessions_starred")
      try db.execute(sql: "DROP INDEX IF EXISTS idx_sessions_client_conversation")
      try db.execute(sql: "DROP TABLE IF EXISTS live_notes")
      try db.execute(sql: "DROP TABLE IF EXISTS transcription_segments")
      try db.execute(sql: "DROP TABLE IF EXISTS transcription_sessions")

      try createConversationAuthorityTables(in: db)

      for item in retainedSessions {
        let row = item.row
        let id: Int64 = row["id"]
        let startedAt: Date = Self.value(row, "startedAt") ?? Date()
        let createdAt: Date = Self.value(row, "createdAt") ?? startedAt
        let updatedAt: Date = Self.value(row, "updatedAt") ?? createdAt
        try db.execute(
          sql: """
            INSERT INTO transcription_sessions
              (id, conversationId, startedAt, finishedAt, language, timezone, inputDeviceName, status, lastError,
               finalizationReason, finalizationStartedAt, finalizationCompletedAt, title, isTitleManuallyEdited,
               overview, emoji, commitmentsJson, geolocationJson, starred, folderId, createdAt, updatedAt,
               autoDetectLanguage, vocabularyJson, contentGeneration)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, NULL, ?, ?, 0, NULL, 0)
            """,
          arguments: [
            id, item.conversationId, startedAt, Self.value(row, "finishedAt") as Date?,
            Self.string(row, "language") ?? "en", Self.string(row, "timezone") ?? "UTC",
            Self.string(row, "inputDeviceName"), item.status, Self.string(row, "lastError"),
            Self.string(row, "finalizationReason"), Self.value(row, "finalizationStartedAt") as Date?,
            Self.value(row, "finalizationCompletedAt") as Date?, Self.string(row, "title"),
            Self.string(row, "overview"), Self.string(row, "emoji"),
            Self.migrateLegacyEvents(Self.string(row, "eventsJson")), Self.string(row, "geolocationJson"),
            Self.bool(row, "starred"),
            createdAt, updatedAt,
          ])
      }

      var usedSegmentIds = Set<String>()
      for row in legacySegments {
        let sessionId: Int64 = row["sessionId"]
        guard retainedSessionIds.contains(sessionId) else { continue }
        let candidate = Self.string(row, "segmentId")
        let segmentId: String
        if let candidate, UUID(uuidString: candidate) != nil, usedSegmentIds.insert(candidate).inserted {
          segmentId = candidate
        } else {
          segmentId = Self.uniqueUUID(excluding: &usedSegmentIds)
        }
        let createdAt: Date = Self.value(row, "createdAt") ?? Date()
        try db.execute(
          sql: """
            INSERT INTO transcription_segments
              (id, sessionId, segmentId, speakerId, text, startTime, endTime, segmentOrder, isUser,
               translationsJson, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            Self.value(row, "id") as Int64?, sessionId, segmentId,
            (Self.value(row, "speaker") as Int?) ?? 0, Self.string(row, "text") ?? "",
            (Self.value(row, "startTime") as Double?) ?? 0,
            (Self.value(row, "endTime") as Double?) ?? 0,
            (Self.value(row, "segmentOrder") as Int?) ?? 0, Self.bool(row, "isUser"),
            Self.string(row, "translationsJson"), createdAt, createdAt,
          ])
        try db.execute(
          sql: """
            INSERT INTO conversation_segment_ingestion
              (sessionId, segmentId, speakerId, text, startTime, endTime, sourceOrder, isUser,
               translationsJson, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            sessionId, segmentId, (Self.value(row, "speaker") as Int?) ?? 0,
            Self.string(row, "text") ?? "", (Self.value(row, "startTime") as Double?) ?? 0,
            (Self.value(row, "endTime") as Double?) ?? 0,
            (Self.value(row, "segmentOrder") as Int?) ?? 0, Self.bool(row, "isUser"),
            Self.string(row, "translationsJson"), createdAt, createdAt,
          ])
      }

      for row in legacyNotes {
        let sessionId: Int64 = row["sessionId"]
        guard retainedSessionIds.contains(sessionId) else { continue }
        let timestamp: Date = Self.value(row, "timestamp") ?? Date()
        let createdAt: Date = Self.value(row, "createdAt") ?? timestamp
        let updatedAt: Date = Self.value(row, "updatedAt") ?? createdAt
        try db.execute(
          sql: """
            INSERT INTO live_notes
              (id, sessionId, text, timestamp, isAiGenerated, segmentStartOrder, segmentEndOrder, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            Self.value(row, "id") as Int64?, sessionId, Self.string(row, "text") ?? "", timestamp,
            Self.bool(row, "isAiGenerated"), Self.value(row, "segmentStartOrder") as Int?,
            Self.value(row, "segmentEndOrder") as Int?, createdAt, updatedAt,
          ])
      }
    }

    migrator.registerMigration("addFairUseClassifierMetadataS20") { db in
      guard try db.tableExists("transcription_sessions") else { return }
      let columns = Set(try db.columns(in: "transcription_sessions").map(\.name))
      if !columns.contains("classifierCategory") {
        try db.alter(table: "transcription_sessions") { table in
          table.add(column: "classifierCategory", .text)
        }
      }
      if !columns.contains("classifierSource") {
        try db.alter(table: "transcription_sessions") { table in
          table.add(column: "classifierSource", .text)
        }
      }
    }
  }

  private struct MigratedCommitment: Codable {
    let title: String
    let description: String
    let start: Date
    let durationMinutes: Int
    let created: Bool

    enum CodingKeys: String, CodingKey {
      case title, description, start, created
      case durationMinutes = "duration_minutes"
    }
  }

  /// Legacy `eventsJson` used the hosted Event wire shape (`duration`) while the
  /// local authority stores commitment candidates (`duration_minutes`). Decode
  /// and translate each valid event so migration never leaves an unreadable
  /// blob in the new typed column. Calendar creation state is deliberately
  /// discarded: commitments are local candidates only.
  private static func migrateLegacyEvents(_ value: String?) -> String? {
    guard
      let value,
      let data = value.data(using: .utf8),
      let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }

    let iso8601 = ISO8601DateFormatter()
    let commitments = objects.compactMap { object -> MigratedCommitment? in
      guard
        let title = object["title"] as? String,
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let rawStart = object["start"]
      else { return nil }
      let start: Date?
      if let date = rawStart as? Date {
        start = date
      } else if let seconds = rawStart as? NSNumber {
        start = Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
      } else if let text = rawStart as? String {
        start = iso8601.date(from: text)
      } else {
        start = nil
      }
      guard let start else { return nil }
      let duration =
        (object["duration"] as? NSNumber)?.intValue
        ?? (object["duration_minutes"] as? NSNumber)?.intValue
        ?? 30
      guard duration > 0, duration <= 180 else { return nil }
      return MigratedCommitment(
        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
        description: object["description"] as? String ?? "",
        start: start,
        durationMinutes: duration,
        created: false)
    }
    guard !commitments.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let encoded = try? encoder.encode(commitments) else { return nil }
    return String(decoding: encoded, as: UTF8.self)
  }

  private static func createConversationAuthorityTables(in db: Database) throws {
    try db.create(table: "conversation_folders", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("name", .text).notNull()
      t.column("color", .text).notNull()
      t.column("createdAt", .datetime).notNull()
    }

    try db.create(table: "transcription_sessions", ifNotExists: true) { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("conversationId", .text).notNull().unique()
      t.column("startedAt", .datetime).notNull()
      t.column("finishedAt", .datetime)
      t.column("language", .text).notNull().defaults(to: "en")
      t.column("timezone", .text).notNull().defaults(to: "UTC")
      t.column("inputDeviceName", .text)
      t.column("status", .text).notNull().defaults(to: "recording")
      t.column("lastError", .text)
      t.column("finalizationReason", .text)
      t.column("finalizationStartedAt", .datetime)
      t.column("finalizationCompletedAt", .datetime)
      t.column("title", .text)
      t.column("isTitleManuallyEdited", .boolean).notNull().defaults(to: false)
      t.column("overview", .text)
      t.column("emoji", .text)
      t.column("commitmentsJson", .text)
      t.column("geolocationJson", .text)
      t.column("starred", .boolean).notNull().defaults(to: false)
      t.column("folderId", .text).references("conversation_folders", onDelete: .setNull)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
      t.column("contentGeneration", .integer).notNull().defaults(to: 0)
      t.column("autoDetectLanguage", .boolean).notNull().defaults(to: false)
      t.column("vocabularyJson", .text)
    }

    try db.create(table: "transcription_segments", ifNotExists: true) { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("sessionId", .integer).notNull().references("transcription_sessions", onDelete: .cascade)
      t.column("segmentId", .text).notNull().unique()
      t.column("speakerId", .integer).notNull()
      t.column("text", .text).notNull()
      t.column("startTime", .double).notNull()
      t.column("endTime", .double).notNull()
      t.column("segmentOrder", .integer).notNull()
      t.column("isUser", .boolean).notNull().defaults(to: false)
      t.column("translationsJson", .text)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }

    // Provider revisions are retained behind the public normalized segment
    // projection. Replaying or correcting a fragment that was folded into a
    // neighboring segment can therefore rebuild the same canonical transcript
    // instead of appending the fragment a second time.
    try db.create(table: "conversation_segment_ingestion", ifNotExists: true) { t in
      t.column("sessionId", .integer).notNull().references("transcription_sessions", onDelete: .cascade)
      t.column("segmentId", .text).notNull().unique()
      t.column("speakerId", .integer).notNull()
      t.column("text", .text).notNull()
      t.column("startTime", .double).notNull()
      t.column("endTime", .double).notNull()
      t.column("sourceOrder", .integer).notNull()
      t.column("isUser", .boolean).notNull().defaults(to: false)
      t.column("translationsJson", .text)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: "live_notes", ifNotExists: true) { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("sessionId", .integer).notNull().references("transcription_sessions", onDelete: .cascade)
      t.column("text", .text).notNull()
      t.column("timestamp", .datetime).notNull()
      t.column("isAiGenerated", .boolean).notNull().defaults(to: true)
      t.column("segmentStartOrder", .integer)
      t.column("segmentEndOrder", .integer)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: "conversation_speaker_labels", ifNotExists: true) { t in
      t.column("conversationId", .text).notNull()
        .references("transcription_sessions", column: "conversationId", onDelete: .cascade)
      t.column("speakerId", .integer).notNull()
      t.column("name", .text).notNull()
      t.column("isUser", .boolean).notNull().defaults(to: false)
      t.column("updatedAt", .datetime).notNull()
      t.primaryKey(["conversationId", "speakerId"])
    }

    try db.create(table: "conversation_merge_sources", ifNotExists: true) { t in
      t.column("replacementConversationId", .text).notNull()
        .references("transcription_sessions", column: "conversationId", onDelete: .cascade)
      t.column("sourceConversationId", .text).notNull()
      t.column("sourceOrdinal", .integer).notNull()
      t.primaryKey(["replacementConversationId", "sourceOrdinal"])
    }

    try db.create(table: "conversation_enrichment_work", ifNotExists: true) { t in
      t.column("conversationId", .text).notNull()
        .references("transcription_sessions", column: "conversationId", onDelete: .cascade)
      t.column("contentGeneration", .integer).notNull()
      t.column("kind", .text).notNull()
      t.column("state", .text).notNull()
      t.column("attemptCount", .integer).notNull().defaults(to: 0)
      t.column("lastError", .text)
      t.column("createdAt", .datetime).notNull()
      t.column("updatedAt", .datetime).notNull()
      t.primaryKey(["conversationId", "contentGeneration", "kind"])
    }

    try db.create(index: "idx_sessions_status", on: "transcription_sessions", columns: ["status"], ifNotExists: true)
    try db.create(
      index: "idx_sessions_created", on: "transcription_sessions", columns: ["createdAt", "id"], ifNotExists: true)
    try db.create(index: "idx_sessions_starred", on: "transcription_sessions", columns: ["starred"], ifNotExists: true)
    try db.create(index: "idx_sessions_folder", on: "transcription_sessions", columns: ["folderId"], ifNotExists: true)
    try db.create(
      index: "idx_segments_session", on: "transcription_segments", columns: ["sessionId", "segmentOrder"],
      ifNotExists: true)
    try db.create(
      index: "idx_segment_ingestion_session", on: "conversation_segment_ingestion",
      columns: ["sessionId", "sourceOrder"], ifNotExists: true)
    try db.create(index: "idx_live_notes_session", on: "live_notes", columns: ["sessionId"], ifNotExists: true)
    try db.create(
      index: "idx_conversation_folders_created", on: "conversation_folders", columns: ["createdAt"], ifNotExists: true)
    try db.create(
      index: "idx_conversation_work_state", on: "conversation_enrichment_work", columns: ["state", "updatedAt"],
      ifNotExists: true)
  }

  private static func uniqueUUID(excluding used: inout Set<String>) -> String {
    while true {
      let candidate = UUID().uuidString.lowercased()
      if used.insert(candidate).inserted { return candidate }
    }
  }

  private static func value<T: DatabaseValueConvertible>(_ row: Row, _ column: String) -> T? {
    guard row.hasColumn(column) else { return nil }
    return row[column]
  }

  private static func string(_ row: Row, _ column: String) -> String? {
    value(row, column)
  }

  private static func bool(_ row: Row, _ column: String) -> Bool {
    value(row, column) ?? false
  }
}
