import Foundation
@preconcurrency import GRDB

extension TranscriptionStorage {
  func beginConversation(
    configuration: ConversationCaptureConfiguration,
    startedAt: Date = Date(),
    conversationId: String = UUID().uuidString.lowercased(),
    classifierSource: String? = nil,
    authorization suppliedAuthorization: LocalMutationAuthorization? = nil
  ) async throws -> ConversationCaptureHandle {
    guard UUID(uuidString: conversationId) != nil else {
      throw TranscriptionStorageError.invalidState("conversationId must be a UUID")
    }
    let db = try await localAuthorityDatabase()
    let authorization = try localAuthorityAuthorization(suppliedAuthorization)
    let vocabularyJson = try Self.encodeJSON(configuration.vocabulary)
    let locationJson = try configuration.location.map(Self.encodeJSON)
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: """
            INSERT INTO transcription_sessions
              (conversationId, startedAt, language, timezone, inputDeviceName, status, isTitleManuallyEdited,
               geolocationJson, starred, createdAt, updatedAt, contentGeneration, autoDetectLanguage, vocabularyJson,
               classifierSource)
            VALUES (?, ?, ?, ?, ?, 'recording', 0, ?, 0, ?, ?, 0, ?, ?, ?)
            """,
          arguments: [
            conversationId.lowercased(), startedAt, configuration.language, configuration.timezone,
            configuration.inputDeviceName, locationJson, startedAt, startedAt, configuration.autoDetectLanguage,
            vocabularyJson, classifierSource,
          ])
        return ConversationCaptureHandle(
          sessionId: database.lastInsertedRowID, conversationId: conversationId.lowercased())
      }
    }
  }

  func upsertSegments(
    conversationId: String,
    segments incoming: [ConversationSegmentInput],
    authorization suppliedAuthorization: LocalMutationAuthorization? = nil
  ) async throws {
    guard !incoming.isEmpty else { return }
    let db = try await localAuthorityDatabase()
    let authorization = try localAuthorityAuthorization(suppliedAuthorization)
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let session = try Row.fetchOne(
            database,
            sql: "SELECT id, status FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        let sessionId: Int64 = session["id"]
        let status: String = session["status"]
        guard status == ConversationLifecycleState.recording.rawValue else {
          throw TranscriptionStorageError.invalidState("segments are closed after recording")
        }

        let now = Date()
        var nextSourceOrder =
          (try Int.fetchOne(
            database,
            sql: "SELECT COALESCE(MAX(sourceOrder), -1) + 1 FROM conversation_segment_ingestion WHERE sessionId = ?",
            arguments: [sessionId])) ?? 0
        for input in incoming where !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          let segmentId = LocalTranscriptFormatter.stableSegmentId(conversationId: conversationId, input: input)
          let translationsJson = input.translations.isEmpty ? nil : try Self.encodeJSON(input.translations)
          try database.execute(
            sql: """
              INSERT INTO conversation_segment_ingestion
                (sessionId, segmentId, speakerId, text, startTime, endTime, sourceOrder, isUser,
                 translationsJson, createdAt, updatedAt)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(segmentId) DO UPDATE SET
                speakerId = excluded.speakerId,
                text = excluded.text,
                startTime = excluded.startTime,
                endTime = excluded.endTime,
                isUser = excluded.isUser,
                translationsJson = COALESCE(excluded.translationsJson, conversation_segment_ingestion.translationsJson),
                updatedAt = excluded.updatedAt
              """,
            arguments: [
              sessionId, segmentId, input.speakerId, input.text, input.startTime, input.endTime,
              nextSourceOrder, input.isUser, translationsJson, now, now,
            ])
          if database.changesCount == 1,
            try Int.fetchOne(
              database,
              sql: "SELECT sourceOrder FROM conversation_segment_ingestion WHERE segmentId = ?",
              arguments: [segmentId]) == nextSourceOrder
          {
            nextSourceOrder += 1
          }
        }

        let rawSegments = try Row.fetchAll(
          database,
          sql: "SELECT * FROM conversation_segment_ingestion WHERE sessionId = ? ORDER BY sourceOrder",
          arguments: [sessionId]
        ).map { row in
          let json: String? = row["translationsJson"]
          return LocalTranscriptSegment(
            segmentId: row["segmentId"], speakerId: row["speakerId"], text: row["text"],
            startTime: row["startTime"], endTime: row["endTime"], segmentOrder: row["sourceOrder"],
            isUser: row["isUser"],
            translations: Self.decodeJSON([ConversationSegmentTranslation].self, from: json) ?? [])
        }
        let current = LocalTranscriptFormatter.normalize(existing: [], incoming: rawSegments).segments

        try database.execute(
          sql: "DELETE FROM transcription_segments WHERE sessionId = ?", arguments: [sessionId])
        for (order, segment) in current.enumerated() {
          let translationsJson = segment.translations.isEmpty ? nil : try Self.encodeJSON(segment.translations)
          try database.execute(
            sql: """
              INSERT INTO transcription_segments
                (sessionId, segmentId, speakerId, text, startTime, endTime, segmentOrder, isUser,
                 translationsJson, createdAt, updatedAt)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              """,
            arguments: [
              sessionId, segment.segmentId, segment.speakerId, segment.text, segment.startTime, segment.endTime, order,
              segment.isUser, translationsJson, now, now,
            ])
        }
        try database.execute(
          sql:
            "UPDATE transcription_sessions SET updatedAt = ?, contentGeneration = contentGeneration + 1 WHERE id = ?",
          arguments: [now, sessionId])
      }
    }
  }

  func upsertSegments(
    sessionId: Int64,
    segments: [ConversationSegmentInput],
    authorization suppliedAuthorization: LocalMutationAuthorization? = nil
  ) async throws {
    let authorization = try localAuthorityAuthorization(suppliedAuthorization)
    let db = try await localAuthorityDatabase()
    let conversationId = try await authorization.withCommitLease {
      try await db.read { database in
        try authorization.require()
        guard
          let value = try String.fetchOne(
            database,
            sql: "SELECT conversationId FROM transcription_sessions WHERE id = ?",
            arguments: [sessionId])
        else { throw TranscriptionStorageError.sessionNotFound }
        return value
      }
    }
    try await upsertSegments(
      conversationId: conversationId, segments: segments, authorization: authorization)
  }

  func attachTranslation(
    sessionId: Int64,
    segmentId: String,
    translation: ConversationSegmentTranslation,
    authorization suppliedAuthorization: LocalMutationAuthorization? = nil
  ) async throws {
    guard UUID(uuidString: segmentId) != nil,
      !translation.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !translation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TranscriptionStorageError.invalidState("translation is invalid") }
    let authorization = try localAuthorityAuthorization(suppliedAuthorization)
    let db = try await localAuthorityDatabase()
    let input = try await authorization.withCommitLease {
      try await db.read { database in
        try authorization.require()
        guard
          let row = try Row.fetchOne(
            database,
            sql: """
              SELECT speakerId, text, startTime, endTime, isUser, translationsJson
              FROM conversation_segment_ingestion
              WHERE sessionId = ? AND segmentId = ?
              """,
            arguments: [sessionId, segmentId.lowercased()])
        else { throw TranscriptionStorageError.invalidState("translation segment was not found") }
        let json: String? = row["translationsJson"]
        var translations = Self.decodeJSON([ConversationSegmentTranslation].self, from: json) ?? []
        translations.removeAll { $0.language == translation.language }
        translations.append(translation)
        return ConversationSegmentInput(
          segmentId: segmentId.lowercased(),
          speakerId: row["speakerId"],
          text: row["text"],
          startTime: row["startTime"],
          endTime: row["endTime"],
          isUser: row["isUser"],
          translations: translations)
      }
    }
    try await upsertSegments(
      sessionId: sessionId,
      segments: [input],
      authorization: authorization)
  }

  func conversationDetail(id conversationId: String) async throws -> LocalConversationDetail? {
    let db = try await localAuthorityDatabase()
    return try await db.read { database in
      guard
        let row = try Row.fetchOne(
          database, sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?", arguments: [conversationId])
      else { return nil }
      return try Self.makeLocalConversationDetail(database, row: row)
    }
  }

  func setConversationLocation(
    id conversationId: String,
    location: ConversationLocationSnapshot,
    authorization: LocalMutationAuthorization
  ) async throws -> Bool {
    let db = try await localAuthorityDatabase()
    let locationJson = try Self.encodeJSON(location)
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: """
            UPDATE transcription_sessions SET geolocationJson = ?, updatedAt = ?
            WHERE conversationId = ? AND status = ? AND geolocationJson IS NULL
            """,
          arguments: [
            locationJson, Date(), conversationId, ConversationLifecycleState.recording.rawValue,
          ])
        return database.changesCount == 1
      }
    }
  }

  func conversationPage(
    query: ConversationLocalQuery,
    offset: Int,
    limit: Int
  ) async throws -> [LocalConversationSummary] {
    let db = try await localAuthorityDatabase()
    let boundedOffset = max(0, offset)
    let boundedLimit = max(1, min(limit, 200))
    let predicate = Self.localConversationPredicate(query: query)
    return try await db.read { database in
      var arguments = predicate.arguments
      arguments += [boundedLimit, boundedOffset]
      return try Row.fetchAll(
        database,
        sql: """
          SELECT s.*,
                 (SELECT COUNT(*) FROM transcription_segments seg WHERE seg.sessionId = s.id) AS segmentCount
          FROM transcription_sessions s
          WHERE \(predicate.sql)
          ORDER BY s.startedAt DESC, s.id DESC
          LIMIT ? OFFSET ?
          """,
        arguments: arguments
      ).map(Self.makeLocalConversationSummary)
    }
  }

  func conversationCount(query: ConversationLocalQuery) async throws -> Int {
    let db = try await localAuthorityDatabase()
    let predicate = Self.localConversationPredicate(query: query)
    return try await db.read { database in
      try Int.fetchOne(
        database,
        sql: "SELECT COUNT(*) FROM transcription_sessions s WHERE \(predicate.sql)",
        arguments: predicate.arguments) ?? 0
    }
  }

  func fairUseEvidence(now: Date = Date()) async throws -> [FairUseConversationEvidence] {
    let db = try await localAuthorityDatabase()
    let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql: """
          SELECT title, overview, classifierCategory, classifierSource, startedAt, finishedAt, createdAt
          FROM transcription_sessions
          WHERE createdAt >= ? AND createdAt <= ?
            AND status NOT IN ('recording', 'merging')
          ORDER BY createdAt DESC, id DESC
          LIMIT 30
          """,
        arguments: [cutoff, now]
      ).map { row in
        let startedAt: Date = row["startedAt"]
        let finishedAt: Date? = row["finishedAt"]
        let duration = finishedAt.map { max(0, $0.timeIntervalSince(startedAt) / 60) } ?? 0
        let overview: String = row["overview"] ?? ""
        return FairUseConversationEvidence(
          conversationId: UUID().uuidString.lowercased(),
          title: row["title"] ?? "",
          overview: String(overview.prefix(200)),
          category: row["classifierCategory"] ?? "",
          durationMinutes: (duration * 10).rounded() / 10,
          source: row["classifierSource"] ?? "",
          createdAt: row["createdAt"])
      }
    }
  }

  func searchConversations(text: String) async throws -> [LocalConversationSummary] {
    let normalized = text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    guard !normalized.isEmpty else { return [] }
    let escaped =
      normalized
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
    let pattern = "%\(escaped)%"
    let db = try await localAuthorityDatabase()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql: """
          SELECT s.*,
                 (SELECT COUNT(*) FROM transcription_segments seg WHERE seg.sessionId = s.id) AS segmentCount
          FROM transcription_sessions s
          WHERE s.status NOT IN ('recording', 'merging')
            AND (LOWER(COALESCE(s.title, '')) LIKE LOWER(?) ESCAPE '\\'
              OR LOWER(COALESCE(s.overview, '')) LIKE LOWER(?) ESCAPE '\\')
          ORDER BY s.startedAt DESC, s.id DESC
          LIMIT 50
          """,
        arguments: [pattern, pattern]
      ).map(Self.makeLocalConversationSummary)
    }
  }

  func setConversationStarred(
    id conversationId: String,
    starred: Bool,
    authorization: LocalMutationAuthorization
  ) async throws -> LocalConversationDetail {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: "UPDATE transcription_sessions SET starred = ?, updatedAt = ? WHERE conversationId = ?",
          arguments: [starred, Date(), conversationId])
        guard database.changesCount == 1,
          let row = try Row.fetchOne(
            database, sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        return try Self.makeLocalConversationDetail(database, row: row)
      }
    }
  }

  func setConversationTitle(
    id conversationId: String,
    title: String,
    authorization: LocalMutationAuthorization
  ) async throws -> LocalConversationDetail {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.count <= 256 else {
      throw TranscriptionStorageError.invalidState("title must be 1 through 256 characters")
    }
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        let now = Date()
        guard
          let current = try Row.fetchOne(
            database,
            sql: "SELECT status, contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        let currentStatus = ConversationLifecycleState(rawValue: current["status"] as String) ?? .failed
        guard currentStatus != .recording, currentStatus != .merging else {
          throw TranscriptionStorageError.invalidState("conversation title is not editable yet")
        }
        let oldGeneration: Int = current["contentGeneration"]
        let generation = oldGeneration + 1
        let nextStatus: ConversationLifecycleState =
          currentStatus == .finalizing ? .finalizing : .processing
        try database.execute(
          sql: """
            UPDATE transcription_sessions
            SET title = ?, isTitleManuallyEdited = 1, contentGeneration = ?, status = ?,
                finalizationCompletedAt = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ?
            """,
          arguments: [
            normalized, generation, nextStatus.rawValue, now, conversationId, oldGeneration,
          ])
        guard database.changesCount == 1 else {
          throw TranscriptionStorageError.invalidState("conversation title generation changed")
        }
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work SET state = ?, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND state IN (?, ?)
            """,
          arguments: [
            ConversationEnrichmentState.superseded.rawValue, now, conversationId, oldGeneration,
            ConversationEnrichmentState.pending.rawValue, ConversationEnrichmentState.running.rawValue,
          ])
        if currentStatus == .finalizing {
          try Self.admitWork(
            database, conversationId: conversationId, generation: generation, kind: .discard, now: now)
        } else {
          try Self.admitWork(
            database, conversationId: conversationId, generation: generation, kind: .structure, now: now)
          try Self.admitWork(
            database, conversationId: conversationId, generation: generation, kind: .actionItems, now: now)
        }
        guard
          let row = try Row.fetchOne(
            database, sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        return try Self.makeLocalConversationDetail(database, row: row)
      }
    }
  }

  func applyConversationStructureCandidate(
    id conversationId: String,
    contentGeneration: Int,
    title: String,
    overview: String,
    emoji: String,
    commitmentsJson: String?,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationStructureCommitResult {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let row = try Row.fetchOne(
            database,
            sql: "SELECT contentGeneration, isTitleManuallyEdited FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return .missing }
        let currentGeneration: Int = row["contentGeneration"]
        guard currentGeneration == contentGeneration else { return .stale }
        let isManual: Bool = row["isTitleManuallyEdited"]
        let now = Date()
        if isManual {
          try database.execute(
            sql: """
              UPDATE transcription_sessions
              SET overview = ?, emoji = ?, commitmentsJson = ?, updatedAt = ?
              WHERE conversationId = ? AND contentGeneration = ?
              """,
            arguments: [overview, emoji, commitmentsJson, now, conversationId, contentGeneration])
        } else {
          try database.execute(
            sql: """
              UPDATE transcription_sessions
              SET title = ?, overview = ?, emoji = ?, commitmentsJson = ?, updatedAt = ?
              WHERE conversationId = ? AND contentGeneration = ?
              """,
            arguments: [title, overview, emoji, commitmentsJson, now, conversationId, contentGeneration])
        }
        return database.changesCount == 1 ? .applied : .stale
      }
    }
  }

  func conversationFolders() async throws -> [ConversationFolderRecord] {
    let db = try await localAuthorityDatabase()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql: """
          SELECT f.id, f.name, f.color, f.createdAt, COUNT(s.id) AS conversationCount
          FROM conversation_folders f
          LEFT JOIN transcription_sessions s ON s.folderId = f.id
          GROUP BY f.id, f.name, f.color, f.createdAt, f.rowid
          ORDER BY f.createdAt, f.rowid
          """
      ).map { row in
        ConversationFolderRecord(
          id: row["id"], name: row["name"], color: row["color"], createdAt: row["createdAt"],
          conversationCount: row["conversationCount"])
      }
    }
  }

  func createConversationFolder(
    name: String,
    color: String,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationFolderRecord {
    let normalizedName = try Self.normalizedFolderName(name)
    let normalizedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedColor.isEmpty else {
      throw TranscriptionStorageError.invalidState("folder color must not be blank")
    }
    let folder = ConversationFolderRecord(
      id: UUID().uuidString.lowercased(), name: normalizedName, color: normalizedColor, createdAt: Date())
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: "INSERT INTO conversation_folders (id, name, color, createdAt) VALUES (?, ?, ?, ?)",
          arguments: [folder.id, folder.name, folder.color, folder.createdAt])
        return folder
      }
    }
  }

  func updateConversationFolder(
    id: String,
    name: String,
    color: String,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationFolderRecord {
    let normalizedName = try Self.normalizedFolderName(name)
    let normalizedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedColor.isEmpty else {
      throw TranscriptionStorageError.invalidState("folder color must not be blank")
    }
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        try database.execute(
          sql: "UPDATE conversation_folders SET name = ?, color = ? WHERE id = ?",
          arguments: [normalizedName, normalizedColor, id])
        guard database.changesCount == 1,
          let createdAt = try Date.fetchOne(
            database, sql: "SELECT createdAt FROM conversation_folders WHERE id = ?", arguments: [id])
        else { throw TranscriptionStorageError.invalidState("folder not found") }
        return ConversationFolderRecord(id: id, name: normalizedName, color: normalizedColor, createdAt: createdAt)
      }
    }
  }

  func moveConversation(
    id conversationId: String,
    toFolder folderId: String?,
    authorization: LocalMutationAuthorization
  ) async throws -> LocalConversationDetail {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        if let folderId,
          try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM conversation_folders WHERE id = ?", arguments: [folderId]) != 1
        {
          throw TranscriptionStorageError.invalidState("folder not found")
        }
        try database.execute(
          sql: "UPDATE transcription_sessions SET folderId = ?, updatedAt = ? WHERE conversationId = ?",
          arguments: [folderId, Date(), conversationId])
        guard database.changesCount == 1,
          let row = try Row.fetchOne(
            database, sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        return try Self.makeLocalConversationDetail(database, row: row)
      }
    }
  }

  func deleteConversationFolder(
    id: String,
    moveConversationsTo destinationId: String?,
    authorization: LocalMutationAuthorization
  ) async throws {
    guard destinationId != id else {
      throw TranscriptionStorageError.invalidState("folder cannot be its own deletion destination")
    }
    let db = try await localAuthorityDatabase()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM conversation_folders WHERE id = ?", arguments: [id]) == 1
        else { throw TranscriptionStorageError.invalidState("folder not found") }
        if let destinationId,
          try Int.fetchOne(
            database, sql: "SELECT COUNT(*) FROM conversation_folders WHERE id = ?", arguments: [destinationId]) != 1
        {
          throw TranscriptionStorageError.invalidState("destination folder not found")
        }
        try database.execute(
          sql: "UPDATE transcription_sessions SET folderId = ?, updatedAt = ? WHERE folderId = ?",
          arguments: [destinationId, Date(), id])
        try database.execute(sql: "DELETE FROM conversation_folders WHERE id = ?", arguments: [id])
      }
    }
  }

  func setConversationSpeakerLabel(
    conversationId: String,
    speakerId: Int,
    name: String,
    isUser: Bool,
    applyToExisting: Bool = true,
    segmentIds: [String] = [],
    authorization: LocalMutationAuthorization
  ) async throws {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard speakerId >= 0, !normalizedName.isEmpty, normalizedName.count <= 100 else {
      throw TranscriptionStorageError.invalidState("speaker label is invalid")
    }
    let db = try await localAuthorityDatabase()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let sessionId = try Int64.fetchOne(
            database,
            sql: "SELECT id FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        let now = Date()
        let targetSpeakerId: Int
        if applyToExisting {
          targetSpeakerId = speakerId
        } else {
          guard !segmentIds.isEmpty else {
            throw TranscriptionStorageError.invalidState("single-segment naming requires a segment ID")
          }
          targetSpeakerId =
            (try Int.fetchOne(
              database,
              sql: "SELECT COALESCE(MAX(speakerId), -1) + 1 FROM transcription_segments WHERE sessionId = ?",
              arguments: [sessionId])) ?? speakerId + 1
          let placeholders = segmentIds.map { _ in "?" }.joined(separator: ",")
          var arguments: StatementArguments = [targetSpeakerId, isUser, now, sessionId]
          arguments += StatementArguments(segmentIds)
          try database.execute(
            sql: """
              UPDATE transcription_segments SET speakerId = ?, isUser = ?, updatedAt = ?
              WHERE sessionId = ? AND segmentId IN (\(placeholders))
              """,
            arguments: arguments)
          guard database.changesCount == Set(segmentIds).count else {
            throw TranscriptionStorageError.invalidState("one or more speaker segments were not found")
          }
        }
        try database.execute(
          sql: """
            INSERT INTO conversation_speaker_labels
              (conversationId, speakerId, name, isUser, updatedAt)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(conversationId, speakerId) DO UPDATE SET
              name = excluded.name, isUser = excluded.isUser, updatedAt = excluded.updatedAt
            """,
          arguments: [conversationId, targetSpeakerId, normalizedName, isUser, now])
        if isUser && applyToExisting {
          try database.execute(
            sql: "UPDATE transcription_segments SET isUser = 1, updatedAt = ? WHERE sessionId = ? AND speakerId = ?",
            arguments: [now, sessionId, speakerId])
        }
        guard
          let session = try Row.fetchOne(
            database,
            sql: "SELECT status, contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        let currentStatus = ConversationLifecycleState(rawValue: session["status"] as String) ?? .failed
        guard currentStatus != .merging else {
          throw TranscriptionStorageError.invalidState("merged conversation speaker labels are not editable yet")
        }
        let oldGeneration: Int = session["contentGeneration"]
        let generation = oldGeneration + 1
        let nextStatus: ConversationLifecycleState =
          currentStatus == .recording || currentStatus == .finalizing ? currentStatus : .processing
        try database.execute(
          sql: """
            UPDATE transcription_sessions
            SET contentGeneration = ?, status = ?, finalizationCompletedAt = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ?
            """,
          arguments: [generation, nextStatus.rawValue, now, conversationId, oldGeneration])
        guard database.changesCount == 1 else {
          throw TranscriptionStorageError.invalidState("speaker-label generation changed")
        }
        guard currentStatus != .recording else { return }
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work SET state = ?, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND state IN (?, ?)
            """,
          arguments: [
            ConversationEnrichmentState.superseded.rawValue, now, conversationId, oldGeneration,
            ConversationEnrichmentState.pending.rawValue, ConversationEnrichmentState.running.rawValue,
          ])
        if currentStatus == .finalizing {
          try Self.admitWork(
            database, conversationId: conversationId, generation: generation, kind: .discard, now: now)
        } else {
          try Self.admitWork(
            database, conversationId: conversationId, generation: generation, kind: .structure, now: now)
          try Self.admitWork(
            database, conversationId: conversationId, generation: generation, kind: .actionItems, now: now)
        }
      }
    }
  }

  func deleteConversationCascade(
    id conversationId: String,
    authorization: LocalMutationAuthorization,
    failureInjector: (@Sendable () throws -> Void)? = nil
  ) async throws {
    let db = try await localAuthorityDatabase()
    try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId]) == 1
        else { throw TranscriptionStorageError.sessionNotFound }

        if try database.tableExists("action_items") {
          try ActionItemStorage.deleteExactConversationSource(
            in: database, conversationId: conversationId)
        }
        if try database.tableExists("memories") {
          try MemoryStorage.deleteExactConversationSource(
            in: database, conversationId: conversationId)
        }
        try failureInjector?()
        try authorization.require()
        try database.execute(
          sql: "DELETE FROM transcription_sessions WHERE conversationId = ?", arguments: [conversationId])
        guard database.changesCount == 1 else { throw TranscriptionStorageError.sessionNotFound }
      }
    }
  }

  func mergeConversations(
    ids sourceIds: [String],
    replacementId: String = UUID().uuidString.lowercased(),
    authorization: LocalMutationAuthorization,
    failureInjector: (@Sendable () throws -> Void)? = nil
  ) async throws -> LocalConversationDetail {
    let uniqueIds = Array(Set(sourceIds))
    guard uniqueIds.count >= 2, UUID(uuidString: replacementId) != nil else {
      throw TranscriptionStorageError.invalidState("merge requires at least two unique conversations and a UUID")
    }
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        let placeholders = uniqueIds.map { _ in "?" }.joined(separator: ",")
        let sources = try Row.fetchAll(
          database,
          sql: """
            SELECT * FROM transcription_sessions
            WHERE conversationId IN (\(placeholders))
            ORDER BY startedAt, id
            """,
          arguments: StatementArguments(uniqueIds))
        guard sources.count == uniqueIds.count else { throw TranscriptionStorageError.sessionNotFound }
        for source in sources {
          let status: String = source["status"]
          guard status == ConversationLifecycleState.completed.rawValue else {
            throw TranscriptionStorageError.invalidState("only completed conversations can be merged")
          }
        }

        let first = sources[0]
        let last = sources[sources.count - 1]
        let now = Date()
        let startedAt: Date = first["startedAt"]
        let finishedAt: Date? = last["finishedAt"]
        try database.execute(
          sql: """
            INSERT INTO transcription_sessions
              (conversationId, startedAt, finishedAt, language, timezone, inputDeviceName, status,
               isTitleManuallyEdited, geolocationJson, starred, folderId, createdAt, updatedAt, contentGeneration,
               autoDetectLanguage, vocabularyJson)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 1, ?, ?)
            """,
          arguments: [
            replacementId.lowercased(), startedAt, finishedAt, first["language"] as String,
            first["timezone"] as String, first["inputDeviceName"] as String?,
            ConversationLifecycleState.merging.rawValue, first["geolocationJson"] as String?,
            sources.contains { ($0["starred"] as Bool) }, Self.commonFolderId(sources), now, now,
            first["autoDetectLanguage"] as Bool, first["vocabularyJson"] as String?,
          ])
        let replacementSessionId = database.lastInsertedRowID

        var cumulativeOffset = 0.0
        var previousFinishedAt: Date?
        var segmentOrder = 0
        var nextMergedSpeakerId = 0
        for (sourceOrdinal, source) in sources.enumerated() {
          let sourceSessionId: Int64 = source["id"]
          let sourceConversationId: String = source["conversationId"]
          try database.execute(
            sql: """
              INSERT INTO conversation_merge_sources
                (replacementConversationId, sourceConversationId, sourceOrdinal)
              VALUES (?, ?, ?)
              """,
            arguments: [replacementId.lowercased(), sourceConversationId, sourceOrdinal])
          let currentStartedAt: Date = source["startedAt"]
          let gap = previousFinishedAt.map { max(0, currentStartedAt.timeIntervalSince($0)) } ?? 0
          let offset = sourceOrdinal == 0 ? 0 : cumulativeOffset + gap
          let segments = try Row.fetchAll(
            database,
            sql: "SELECT * FROM transcription_segments WHERE sessionId = ? ORDER BY segmentOrder, id",
            arguments: [sourceSessionId])
          let labels = try Row.fetchAll(
            database,
            sql: "SELECT * FROM conversation_speaker_labels WHERE conversationId = ?",
            arguments: [sourceConversationId])
          let sourceSpeakerIds = Set(
            segments.map { $0["speakerId"] as Int }
              + labels.map { $0["speakerId"] as Int })
          var mergedSpeakerIds: [Int: Int] = [:]
          for sourceSpeakerId in sourceSpeakerIds.sorted() {
            mergedSpeakerIds[sourceSpeakerId] = nextMergedSpeakerId
            nextMergedSpeakerId += 1
          }
          var sourceMaxEnd = 0.0
          for segment in segments {
            let oldSegmentId: String = segment["segmentId"]
            let sourceSpeakerId: Int = segment["speakerId"]
            guard let mergedSpeakerId = mergedSpeakerIds[sourceSpeakerId] else {
              throw TranscriptionStorageError.invalidState("merged segment speaker mapping missing")
            }
            let mergedSegmentId = LocalTranscriptFormatter.stableSegmentId(
              conversationId: replacementId.lowercased(),
              input: ConversationSegmentInput(
                segmentId: "merge:\(sourceConversationId):\(oldSegmentId)",
                speakerId: segment["speakerId"], text: segment["text"],
                startTime: segment["startTime"], endTime: segment["endTime"],
                isUser: segment["isUser"], translations: []))
            let start: Double = segment["startTime"]
            let end: Double = segment["endTime"]
            sourceMaxEnd = max(sourceMaxEnd, end)
            try database.execute(
              sql: """
                  INSERT INTO transcription_segments
                    (sessionId, segmentId, speakerId, text, startTime, endTime, segmentOrder, isUser,
                     translationsJson, createdAt, updatedAt)
                  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
              arguments: [
                replacementSessionId, mergedSegmentId, mergedSpeakerId,
                segment["text"] as String, start + offset, end + offset, segmentOrder,
                segment["isUser"] as Bool, segment["translationsJson"] as String?, now, now,
              ])
            segmentOrder += 1
          }
          if segments.isEmpty, let sourceFinishedAt: Date = source["finishedAt"] {
            sourceMaxEnd = max(0, sourceFinishedAt.timeIntervalSince(currentStartedAt))
          }
          cumulativeOffset = offset + sourceMaxEnd
          previousFinishedAt = source["finishedAt"]

          for label in labels {
            let sourceSpeakerId: Int = label["speakerId"]
            guard let mergedSpeakerId = mergedSpeakerIds[sourceSpeakerId] else {
              throw TranscriptionStorageError.invalidState("merged label speaker mapping missing")
            }
            try database.execute(
              sql: """
                INSERT OR IGNORE INTO conversation_speaker_labels
                  (conversationId, speakerId, name, isUser, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
              arguments: [
                replacementId.lowercased(), mergedSpeakerId, label["name"] as String,
                label["isUser"] as Bool, now,
              ])
          }
        }

        let copiedCount =
          try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM transcription_segments WHERE sessionId = ?",
            arguments: [replacementSessionId]) ?? 0
        let sourceSegmentCount =
          try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM transcription_segments WHERE sessionId IN (\(placeholders))",
            arguments: StatementArguments(sources.map { $0["id"] as Int64 })) ?? 0
        guard copiedCount == sourceSegmentCount else {
          throw TranscriptionStorageError.invalidState("merged transcript validation failed")
        }
        try failureInjector?()
        try authorization.require()

        for source in sources {
          let sourceConversationId: String = source["conversationId"]
          if try database.tableExists("action_items") {
            try ActionItemStorage.reassignExactConversationSource(
              in: database,
              from: sourceConversationId,
              to: replacementId.lowercased())
          }
          if try database.tableExists("memories") {
            try MemoryStorage.reassignExactConversationSource(
              in: database,
              from: sourceConversationId,
              to: replacementId.lowercased())
          }
          try database.execute(
            sql: "DELETE FROM transcription_sessions WHERE conversationId = ?",
            arguments: [sourceConversationId])
        }
        try database.execute(
          sql: "UPDATE transcription_sessions SET status = ?, updatedAt = ? WHERE conversationId = ?",
          arguments: [ConversationLifecycleState.processing.rawValue, now, replacementId.lowercased()])
        try Self.admitWork(
          database, conversationId: replacementId.lowercased(), generation: 1, kind: .structure, now: now)
        try Self.admitWork(
          database, conversationId: replacementId.lowercased(), generation: 1, kind: .actionItems, now: now)
        guard
          let replacement = try Row.fetchOne(
            database,
            sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [replacementId.lowercased()])
        else { throw TranscriptionStorageError.sessionNotFound }
        return try Self.makeLocalConversationDetail(database, row: replacement)
      }
    }
  }

  func finishConversation(
    sessionId: Int64,
    reason: TranscriptionFinalizationReason,
    finishedAt: Date = Date(),
    authorization suppliedAuthorization: LocalMutationAuthorization? = nil
  ) async throws -> LocalConversationDetail {
    let db = try await localAuthorityDatabase()
    let authorization = try localAuthorityAuthorization(suppliedAuthorization)
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let current = try Row.fetchOne(
            database, sql: "SELECT * FROM transcription_sessions WHERE id = ?", arguments: [sessionId])
        else { throw TranscriptionStorageError.sessionNotFound }
        let conversationId: String = current["conversationId"]
        let status: String = current["status"]
        if status == ConversationLifecycleState.recording.rawValue {
          let startedAt: Date = current["startedAt"]
          let closedAt = max(finishedAt, startedAt.addingTimeInterval(1))
          let now = Date()
          try database.execute(
            sql: """
              UPDATE transcription_sessions
              SET finishedAt = ?, status = ?, finalizationReason = ?, finalizationStartedAt = ?,
                  finalizationCompletedAt = NULL, lastError = NULL, contentGeneration = contentGeneration + 1,
                  updatedAt = ?
              WHERE id = ? AND status = ?
              """,
            arguments: [
              closedAt, ConversationLifecycleState.finalizing.rawValue, reason.rawValue, now, now, sessionId,
              ConversationLifecycleState.recording.rawValue,
            ])
          let generation =
            try Int.fetchOne(
              database, sql: "SELECT contentGeneration FROM transcription_sessions WHERE id = ?", arguments: [sessionId]
            )
            ?? 0
          try Self.admitWork(
            database,
            conversationId: conversationId,
            generation: generation,
            kind: .discard,
            now: now)
        }
        guard
          let updated = try Row.fetchOne(
            database, sql: "SELECT * FROM transcription_sessions WHERE id = ?", arguments: [sessionId])
        else { throw TranscriptionStorageError.sessionNotFound }
        return try Self.makeLocalConversationDetail(database, row: updated)
      }
    }
  }

  func recoverLocalFinalization(
    now: Date = Date(),
    minimumRecordingAge: TimeInterval = 30
  ) async throws -> ConversationRecoveryReport {
    let db = try await localAuthorityDatabase()
    return try await db.write { database in
      let cutoff = now.addingTimeInterval(-minimumRecordingAge)
      let rows = try Row.fetchAll(
        database,
        sql: """
          SELECT s.*,
                 (SELECT COUNT(*) FROM transcription_segments seg WHERE seg.sessionId = s.id) AS segmentCount
          FROM transcription_sessions s
          WHERE s.status = ? AND s.createdAt <= ?
          ORDER BY s.createdAt, s.id
          """,
        arguments: [ConversationLifecycleState.recording.rawValue, cutoff])
      var finalized: [String] = []
      var deleted: [String] = []
      for row in rows {
        let sessionId: Int64 = row["id"]
        let conversationId: String = row["conversationId"]
        let segmentCount: Int = row["segmentCount"]
        if segmentCount == 0 {
          try database.execute(sql: "DELETE FROM transcription_sessions WHERE id = ?", arguments: [sessionId])
          deleted.append(conversationId)
          continue
        }
        let startedAt: Date = row["startedAt"]
        let closedAt = max(now, startedAt.addingTimeInterval(1))
        try database.execute(
          sql: """
            UPDATE transcription_sessions
            SET finishedAt = ?, status = ?, finalizationReason = ?, finalizationStartedAt = ?,
                contentGeneration = contentGeneration + 1, updatedAt = ?
            WHERE id = ?
            """,
          arguments: [
            closedAt, ConversationLifecycleState.finalizing.rawValue,
            TranscriptionFinalizationReason.crashRecovery.rawValue, now, now, sessionId,
          ])
        let generation =
          try Int.fetchOne(
            database, sql: "SELECT contentGeneration FROM transcription_sessions WHERE id = ?", arguments: [sessionId])
          ?? 0
        try Self.admitWork(
          database,
          conversationId: conversationId,
          generation: generation,
          kind: .discard,
          now: now)
        finalized.append(conversationId)
      }

      let unfinished = try Row.fetchAll(
        database,
        sql: "SELECT conversationId, contentGeneration FROM transcription_sessions WHERE status = ?",
        arguments: [ConversationLifecycleState.finalizing.rawValue])
      for row in unfinished {
        try Self.admitWork(
          database,
          conversationId: row["conversationId"],
          generation: row["contentGeneration"],
          kind: .discard,
          now: now)
      }
      return ConversationRecoveryReport(
        finalizedConversationIds: finalized,
        deletedEmptyConversationIds: deleted)
    }
  }

  func enrichmentWork(conversationId: String) async throws -> [ConversationEnrichmentWork] {
    let db = try await localAuthorityDatabase()
    return try await db.read { database in
      try Row.fetchAll(
        database,
        sql: """
          SELECT * FROM conversation_enrichment_work
          WHERE conversationId = ?
          ORDER BY contentGeneration, CASE kind WHEN 'discard' THEN 0 WHEN 'structure' THEN 1 ELSE 2 END
          """,
        arguments: [conversationId]
      ).compactMap { row in
        guard
          let kind = ConversationEnrichmentKind(rawValue: row["kind"]),
          let state = ConversationEnrichmentState(rawValue: row["state"])
        else { return nil }
        return ConversationEnrichmentWork(
          conversationId: row["conversationId"],
          contentGeneration: row["contentGeneration"],
          kind: kind,
          state: state,
          attemptCount: row["attemptCount"],
          lastError: row["lastError"],
          createdAt: row["createdAt"],
          updatedAt: row["updatedAt"])
      }
    }
  }

  /// Manual retry is a new content generation. Old terminal work remains durable but is
  /// superseded, so delayed responses can never commit into the retry generation.
  func retryConversationEnrichment(
    id conversationId: String,
    authorization: LocalMutationAuthorization,
    now: Date = Date()
  ) async throws -> LocalConversationDetail {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        let status = ConversationLifecycleState(rawValue: row["status"] as String) ?? .failed
        guard status != .recording, status != .merging else {
          throw TranscriptionStorageError.invalidState("conversation cannot retry enrichment")
        }
        let oldGeneration: Int = row["contentGeneration"]
        let newGeneration = oldGeneration + 1
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work
            SET state = ?, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind IN (?, ?)
            """,
          arguments: [
            ConversationEnrichmentState.superseded.rawValue, now, conversationId, oldGeneration,
            ConversationEnrichmentKind.structure.rawValue, ConversationEnrichmentKind.actionItems.rawValue,
          ])
        try database.execute(
          sql: """
            UPDATE transcription_sessions
            SET contentGeneration = ?, status = ?, lastError = NULL,
                finalizationCompletedAt = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ?
            """,
          arguments: [
            newGeneration, ConversationLifecycleState.processing.rawValue, now,
            conversationId, oldGeneration,
          ])
        guard database.changesCount == 1 else {
          throw TranscriptionStorageError.invalidState("conversation retry generation changed")
        }
        try Self.admitWork(
          database, conversationId: conversationId, generation: newGeneration,
          kind: .structure, now: now)
        try Self.admitWork(
          database, conversationId: conversationId, generation: newGeneration,
          kind: .actionItems, now: now)
        guard
          let updated = try Row.fetchOne(
            database,
            sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { throw TranscriptionStorageError.sessionNotFound }
        return try Self.makeLocalConversationDetail(database, row: updated)
      }
    }
  }

  func recoverAndListPendingEnrichmentWork(
    maximumAttempts: Int = 5,
    minimumRunningAge: TimeInterval = 5 * 60,
    now: Date = Date()
  ) async throws -> [ConversationEnrichmentWork] {
    let db = try await localAuthorityDatabase()
    return try await db.write { database in
      let staleCutoff = now.addingTimeInterval(-minimumRunningAge)
      let staleDiscardRows = try Row.fetchAll(
        database,
        sql: """
          SELECT conversationId, contentGeneration
          FROM conversation_enrichment_work
          WHERE kind = ? AND state = ? AND updatedAt <= ?
          """,
        arguments: [
          ConversationEnrichmentKind.discard.rawValue,
          ConversationEnrichmentState.running.rawValue,
          staleCutoff,
        ])
      for row in staleDiscardRows {
        let conversationId: String = row["conversationId"]
        let generation: Int = row["contentGeneration"]
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work
            SET state = ?, lastError = ?, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ?
            """,
          arguments: [
            ConversationEnrichmentState.failed.rawValue, "discard_interrupted_keep", now,
            conversationId, generation, ConversationEnrichmentKind.discard.rawValue,
            ConversationEnrichmentState.running.rawValue,
          ])
        guard database.changesCount == 1 else { continue }
        try Self.admitWork(
          database, conversationId: conversationId, generation: generation, kind: .structure, now: now)
        try Self.admitWork(
          database, conversationId: conversationId, generation: generation, kind: .actionItems, now: now)
        try database.execute(
          sql: """
            UPDATE transcription_sessions SET status = ?, lastError = ?, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ?
            """,
          arguments: [
            ConversationLifecycleState.processing.rawValue, "discard_interrupted_keep", now,
            conversationId, generation,
          ])
      }
      try database.execute(
        sql: """
          UPDATE conversation_enrichment_work
          SET state = CASE WHEN attemptCount < ? THEN ? ELSE ? END, updatedAt = ?
          WHERE kind IN (?, ?) AND state = ? AND updatedAt <= ?
          """,
        arguments: [
          maximumAttempts,
          ConversationEnrichmentState.pending.rawValue,
          ConversationEnrichmentState.failed.rawValue,
          now,
          ConversationEnrichmentKind.structure.rawValue,
          ConversationEnrichmentKind.actionItems.rawValue,
          ConversationEnrichmentState.running.rawValue,
          staleCutoff,
        ])
      return try Row.fetchAll(
        database,
        sql: """
          SELECT * FROM conversation_enrichment_work
          WHERE state = ? AND attemptCount < ?
          ORDER BY updatedAt, conversationId,
            CASE kind WHEN 'structure' THEN 0 ELSE 1 END
          """,
        arguments: [ConversationEnrichmentState.pending.rawValue, maximumAttempts]
      ).compactMap { row in
        guard
          let kind = ConversationEnrichmentKind(rawValue: row["kind"]),
          let state = ConversationEnrichmentState(rawValue: row["state"])
        else { return nil }
        return ConversationEnrichmentWork(
          conversationId: row["conversationId"],
          contentGeneration: row["contentGeneration"],
          kind: kind,
          state: state,
          attemptCount: row["attemptCount"],
          lastError: row["lastError"],
          createdAt: row["createdAt"],
          updatedAt: row["updatedAt"])
      }
    }
  }

  func claimDiscardWork(
    conversationId: String,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationDiscardWorkClaim? {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let work = try Row.fetchOne(
            database,
            sql: """
              SELECT contentGeneration FROM conversation_enrichment_work
              WHERE conversationId = ? AND kind = ? AND state = ?
              ORDER BY contentGeneration DESC LIMIT 1
              """,
            arguments: [
              conversationId, ConversationEnrichmentKind.discard.rawValue,
              ConversationEnrichmentState.pending.rawValue,
            ]),
          let conversation = try Row.fetchOne(
            database,
            sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return nil }
        let workGeneration: Int = work["contentGeneration"]
        let currentGeneration: Int = conversation["contentGeneration"]
        guard workGeneration == currentGeneration else {
          try database.execute(
            sql: """
              UPDATE conversation_enrichment_work SET state = ?, updatedAt = ?
              WHERE conversationId = ? AND contentGeneration = ? AND kind = ?
              """,
            arguments: [
              ConversationEnrichmentState.superseded.rawValue, Date(), conversationId, workGeneration,
              ConversationEnrichmentKind.discard.rawValue,
            ])
          return nil
        }
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work
            SET state = ?, attemptCount = attemptCount + 1, lastError = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ?
            """,
          arguments: [
            ConversationEnrichmentState.running.rawValue, Date(), conversationId, workGeneration,
            ConversationEnrichmentKind.discard.rawValue, ConversationEnrichmentState.pending.rawValue,
          ])
        guard database.changesCount == 1 else { return nil }
        let attemptCount =
          try Int.fetchOne(
            database,
            sql: """
              SELECT attemptCount FROM conversation_enrichment_work
              WHERE conversationId = ? AND contentGeneration = ? AND kind = ?
              """,
            arguments: [conversationId, workGeneration, ConversationEnrichmentKind.discard.rawValue]) ?? 0
        return try ConversationDiscardWorkClaim(
          conversation: Self.makeLocalConversationDetail(database, row: conversation),
          contentGeneration: currentGeneration,
          attemptCount: attemptCount)
      }
    }
  }

  func claimEnrichmentWork(
    conversationId: String,
    kind: ConversationEnrichmentKind,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationDiscardWorkClaim? {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let session = try Row.fetchOne(
            database, sql: "SELECT * FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return nil }
        let generation: Int = session["contentGeneration"]
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work
            SET state = ?, attemptCount = attemptCount + 1, lastError = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ?
            """,
          arguments: [
            ConversationEnrichmentState.running.rawValue, Date(), conversationId, generation, kind.rawValue,
            ConversationEnrichmentState.pending.rawValue,
          ])
        guard database.changesCount == 1 else { return nil }
        let attemptCount =
          try Int.fetchOne(
            database,
            sql: """
              SELECT attemptCount FROM conversation_enrichment_work
              WHERE conversationId = ? AND contentGeneration = ? AND kind = ?
              """,
            arguments: [conversationId, generation, kind.rawValue]) ?? 0
        return try ConversationDiscardWorkClaim(
          conversation: Self.makeLocalConversationDetail(database, row: session),
          contentGeneration: generation,
          attemptCount: attemptCount)
      }
    }
  }

  func completeStructureWork(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    response: ConversationStructureComputeResponse,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationStructureCommitResult {
    let commitments = try Self.encodeJSON(response.commitments)
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let row = try Row.fetchOne(
            database,
            sql: "SELECT contentGeneration, isTitleManuallyEdited FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return .missing }
        let current: Int = row["contentGeneration"]
        guard current == contentGeneration else { return .stale }
        let work = try Row.fetchOne(
          database,
          sql:
            "SELECT state, attemptCount FROM conversation_enrichment_work WHERE conversationId = ? AND contentGeneration = ? AND kind = ?",
          arguments: [conversationId, contentGeneration, ConversationEnrichmentKind.structure.rawValue])
        guard
          work?["state"] as String? == ConversationEnrichmentState.running.rawValue,
          work?["attemptCount"] as Int? == attemptCount
        else { return .missing }
        let manual: Bool = row["isTitleManuallyEdited"]
        let now = Date()
        if manual {
          try database.execute(
            sql:
              "UPDATE transcription_sessions SET overview = ?, emoji = ?, commitmentsJson = ?, classifierCategory = ?, updatedAt = ? WHERE conversationId = ?",
            arguments: [response.overview, response.emoji, commitments, response.category, now, conversationId])
        } else {
          try database.execute(
            sql:
              "UPDATE transcription_sessions SET title = ?, overview = ?, emoji = ?, commitmentsJson = ?, classifierCategory = ?, updatedAt = ? WHERE conversationId = ?",
            arguments: [
              response.title, response.overview, response.emoji, commitments, response.category, now, conversationId,
            ])
        }
        try database.execute(
          sql:
            "UPDATE conversation_enrichment_work SET state = ?, updatedAt = ? WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ? AND attemptCount = ?",
          arguments: [
            ConversationEnrichmentState.succeeded.rawValue, now, conversationId, contentGeneration,
            ConversationEnrichmentKind.structure.rawValue,
            ConversationEnrichmentState.running.rawValue, attemptCount,
          ])
        guard database.changesCount == 1 else { return .missing }
        try Self.completeConversationWhenEnrichmentIsTerminal(
          database, conversationId: conversationId, generation: contentGeneration, now: now)
        return .applied
      }
    }
  }

  func relatedOpenActionItems(
    conversationId: String,
    matches: [ConversationTaskSimilarityMatch],
    now: Date = Date()
  ) async throws -> [ConversationRelatedLocalTask] {
    let eligibleMatches = matches.filter { $0.similarity >= 0.6 }
    guard !eligibleMatches.isEmpty else { return [] }
    let db = try await localAuthorityDatabase()
    return try await db.read { database in
      guard try database.tableExists("action_items") else { return [] }
      var excludedSources: Set<String> = [conversationId]
      if try database.tableExists("conversation_merge_sources") {
        excludedSources.formUnion(
          try String.fetchAll(
            database,
            sql: "SELECT sourceConversationId FROM conversation_merge_sources WHERE replacementConversationId = ?",
            arguments: [conversationId]))
      }
      let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
      var tasks: [ConversationRelatedLocalTask] = []
      for match in eligibleMatches {
        guard
          let row = try Row.fetchOne(
            database,
            sql: """
              SELECT id, description, dueAt, conversationId
              FROM action_items
              WHERE id = ? AND completed = 0 AND deleted = 0
                AND (updatedAt >= ? OR createdAt >= ?)
              """,
            arguments: [match.localRowId, cutoff, cutoff])
        else { continue }
        let sourceId: String? = row["conversationId"]
        guard sourceId.map({ !excludedSources.contains($0) }) ?? true else { continue }
        tasks.append(
          ConversationRelatedLocalTask(
            localRowId: row["id"], description: row["description"], dueAt: row["dueAt"]))
        if tasks.count == 10 { break }
      }
      return Array(tasks.prefix(10))
    }
  }

  func conversationActionItems(conversationId: String) async throws -> [LocalConversationActionItem] {
    let db = try await localAuthorityDatabase()
    return try await db.read { database in
      guard try database.tableExists("action_items") else { return [] }
      return try Row.fetchAll(
        database,
        sql: """
          SELECT id, description, completed, deleted, dueAt
          FROM action_items WHERE conversationId = ? ORDER BY createdAt, id
          """,
        arguments: [conversationId]
      ).map { row in
        LocalConversationActionItem(
          localRowId: row["id"],
          description: row["description"],
          completed: row["completed"],
          deleted: row["deleted"],
          dueAt: row["dueAt"])
      }
    }
  }

  func completeActionItemsWork(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    response: ConversationActionItemsComputeResponse,
    tokenMap: [ConversationActionTaskToken],
    authorization: LocalMutationAuthorization,
    now: Date = Date(),
    failAfterOperations: Int? = nil
  ) async throws -> ConversationStructureCommitResult {
    let tokens = Dictionary(lastWriteWins: tokenMap.map { ($0.token, $0.localRowId) })
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard try database.tableExists("action_items") else {
          throw TranscriptionStorageError.invalidState("action_items table unavailable")
        }
        guard
          let generation = try Int.fetchOne(
            database,
            sql: "SELECT contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return .missing }
        guard generation == contentGeneration else { return .stale }
        let work = try Row.fetchOne(
          database,
          sql:
            "SELECT state, attemptCount FROM conversation_enrichment_work WHERE conversationId = ? AND contentGeneration = ? AND kind = ?",
          arguments: [conversationId, contentGeneration, ConversationEnrichmentKind.actionItems.rawValue])
        guard
          work?["state"] as String? == ConversationEnrichmentState.running.rawValue,
          work?["attemptCount"] as Int? == attemptCount
        else { return .missing }

        var operationCount = 0
        for candidate in response.candidates {
          let description = candidate.description.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !description.isEmpty, description.count <= 4_096 else {
            throw TranscriptionStorageError.invalidState("invalid action-item candidate")
          }
          let dueAt = candidate.dueAt.flatMap {
            $0 >= now.addingTimeInterval(-24 * 60 * 60) ? $0 : nil
          }
          switch candidate.action {
          case .create:
            guard candidate.targetTaskToken == nil else {
              throw TranscriptionStorageError.invalidState("create candidate contains target")
            }
            try database.execute(
              sql: """
                INSERT INTO action_items
                  (description, completed, deleted, source, conversationId,
                   dueAt, createdAt, updatedAt)
                VALUES (?, 0, 0, 'conversation', ?, ?, ?, ?)
                """,
              arguments: [description, conversationId, dueAt, now, now])
          case .update, .complete:
            guard let token = candidate.targetTaskToken, let localRowId = tokens[token] else {
              throw TranscriptionStorageError.invalidState("candidate target was not supplied")
            }
            if candidate.action == .update {
              try database.execute(
                sql: """
                  UPDATE action_items SET description = ?, dueAt = ?, updatedAt = ?
                  WHERE id = ? AND completed = 0 AND deleted = 0
                  """,
                arguments: [description, dueAt, now, localRowId])
            } else {
              try database.execute(
                sql: """
                  UPDATE action_items SET completed = 1, completedAt = ?, updatedAt = ?
                  WHERE id = ? AND completed = 0 AND deleted = 0
                  """,
                arguments: [now, now, localRowId])
            }
            guard database.changesCount == 1 else {
              throw TranscriptionStorageError.invalidState("candidate target is no longer open")
            }
          }
          operationCount += 1
          if failAfterOperations == operationCount {
            throw TranscriptionStorageError.invalidState("injected action-item failure")
          }
        }
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work SET state = ?, lastError = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ? AND attemptCount = ?
            """,
          arguments: [
            ConversationEnrichmentState.succeeded.rawValue, now, conversationId, contentGeneration,
            ConversationEnrichmentKind.actionItems.rawValue, ConversationEnrichmentState.running.rawValue,
            attemptCount,
          ])
        guard database.changesCount == 1 else { return .missing }
        try Self.completeConversationWhenEnrichmentIsTerminal(
          database, conversationId: conversationId, generation: contentGeneration, now: now)
        return .applied
      }
    }
  }

  func failEnrichmentWork(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    kind: ConversationEnrichmentKind,
    reason: String,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationStructureCommitResult {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let current = try Int.fetchOne(
            database, sql: "SELECT contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return .missing }
        guard current == contentGeneration else { return .stale }
        let now = Date()
        try database.execute(
          sql:
            "UPDATE conversation_enrichment_work SET state = CASE WHEN attemptCount < 5 THEN ? ELSE ? END, lastError = ?, updatedAt = ? WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ? AND attemptCount = ?",
          arguments: [
            ConversationEnrichmentState.pending.rawValue, ConversationEnrichmentState.failed.rawValue, reason, now,
            conversationId, contentGeneration, kind.rawValue, ConversationEnrichmentState.running.rawValue,
            attemptCount,
          ])
        guard database.changesCount == 1 else { return .missing }
        try Self.completeConversationWhenEnrichmentIsTerminal(
          database, conversationId: conversationId, generation: contentGeneration, now: now)
        return .applied
      }
    }
  }

  func resolveDiscardWork(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    discard: Bool,
    authorization: LocalMutationAuthorization
  ) async throws -> ConversationDiscardCommitResult {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let row = try Row.fetchOne(
            database,
            sql: "SELECT status, contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return .missing }
        let currentGeneration: Int = row["contentGeneration"]
        guard currentGeneration == contentGeneration else {
          try Self.supersedeDiscardAndReadmit(
            database, conversationId: conversationId, oldGeneration: contentGeneration,
            currentGeneration: currentGeneration)
          return .stale
        }
        let work = try Row.fetchOne(
          database,
          sql: """
            SELECT state, attemptCount FROM conversation_enrichment_work
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ?
            """,
          arguments: [conversationId, contentGeneration, ConversationEnrichmentKind.discard.rawValue])
        guard
          work?["state"] as String? == ConversationEnrichmentState.running.rawValue,
          work?["attemptCount"] as Int? == attemptCount
        else { return .missing }
        if discard {
          try database.execute(
            sql: "DELETE FROM transcription_sessions WHERE conversationId = ? AND contentGeneration = ?",
            arguments: [conversationId, contentGeneration])
          return database.changesCount == 1 ? .deleted : .stale
        }
        let now = Date()
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work SET state = ?, lastError = NULL, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ? AND attemptCount = ?
            """,
          arguments: [
            ConversationEnrichmentState.succeeded.rawValue, now, conversationId, contentGeneration,
            ConversationEnrichmentKind.discard.rawValue,
            ConversationEnrichmentState.running.rawValue, attemptCount,
          ])
        guard database.changesCount == 1 else { return .missing }
        try Self.admitWork(
          database, conversationId: conversationId, generation: contentGeneration, kind: .structure, now: now)
        try Self.admitWork(
          database, conversationId: conversationId, generation: contentGeneration, kind: .actionItems, now: now)
        try database.execute(
          sql: "UPDATE transcription_sessions SET status = ?, updatedAt = ? WHERE conversationId = ?",
          arguments: [ConversationLifecycleState.processing.rawValue, now, conversationId])
        return .kept
      }
    }
  }

  func failDiscardWorkKeepingConversation(
    conversationId: String,
    contentGeneration: Int,
    attemptCount: Int,
    authorization: LocalMutationAuthorization,
    reason: String
  ) async throws -> ConversationDiscardCommitResult {
    let db = try await localAuthorityDatabase()
    return try await authorization.withCommitLease {
      try await db.write { database in
        try authorization.require()
        guard
          let currentGeneration = try Int.fetchOne(
            database,
            sql: "SELECT contentGeneration FROM transcription_sessions WHERE conversationId = ?",
            arguments: [conversationId])
        else { return .missing }
        guard currentGeneration == contentGeneration else {
          try Self.supersedeDiscardAndReadmit(
            database, conversationId: conversationId, oldGeneration: contentGeneration,
            currentGeneration: currentGeneration)
          return .stale
        }
        let now = Date()
        try database.execute(
          sql: """
            UPDATE conversation_enrichment_work SET state = ?, lastError = ?, updatedAt = ?
            WHERE conversationId = ? AND contentGeneration = ? AND kind = ? AND state = ? AND attemptCount = ?
            """,
          arguments: [
            ConversationEnrichmentState.failed.rawValue, reason, now, conversationId, contentGeneration,
            ConversationEnrichmentKind.discard.rawValue, ConversationEnrichmentState.running.rawValue,
            attemptCount,
          ])
        guard database.changesCount == 1 else { return .missing }
        try Self.admitWork(
          database, conversationId: conversationId, generation: contentGeneration, kind: .structure, now: now)
        try Self.admitWork(
          database, conversationId: conversationId, generation: contentGeneration, kind: .actionItems, now: now)
        try database.execute(
          sql: "UPDATE transcription_sessions SET status = ?, lastError = ?, updatedAt = ? WHERE conversationId = ?",
          arguments: [ConversationLifecycleState.processing.rawValue, reason, now, conversationId])
        return .kept
      }
    }
  }

  fileprivate func localAuthorityDatabase() async throws -> DatabasePool {
    try await ensureInitializedForLocalAuthority()
  }

  private func localAuthorityAuthorization(
    _ supplied: LocalMutationAuthorization?
  ) throws -> LocalMutationAuthorization {
    if let supplied { return supplied }
    if injectedDatabasePool != nil { return .unrestricted }
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    return LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
  }

  private static func fetchLocalSegments(_ database: Database, sessionId: Int64) throws -> [LocalTranscriptSegment] {
    try Row.fetchAll(
      database,
      sql: "SELECT * FROM transcription_segments WHERE sessionId = ? ORDER BY segmentOrder, id",
      arguments: [sessionId]
    ).map { row in
      let json: String? = row["translationsJson"]
      return LocalTranscriptSegment(
        segmentId: row["segmentId"],
        speakerId: row["speakerId"],
        text: row["text"],
        startTime: row["startTime"],
        endTime: row["endTime"],
        segmentOrder: row["segmentOrder"],
        isUser: row["isUser"],
        translations: Self.decodeJSON([ConversationSegmentTranslation].self, from: json) ?? [])
    }
  }

  private static func makeLocalConversationDetail(_ database: Database, row: Row) throws -> LocalConversationDetail {
    let sessionId: Int64 = row["id"]
    let conversationId: String = row["conversationId"]
    let labels = try Row.fetchAll(
      database,
      sql: "SELECT speakerId, name, isUser FROM conversation_speaker_labels WHERE conversationId = ?",
      arguments: [conversationId]
    ).reduce(into: [Int: ConversationSpeakerLabel]()) { result, label in
      let speakerId: Int = label["speakerId"]
      result[speakerId] = ConversationSpeakerLabel(
        speakerId: speakerId, name: label["name"], isUser: label["isUser"])
    }
    let locationJSON: String? = row["geolocationJson"]
    let vocabularyJSON: String? = row["vocabularyJson"]
    let reasonRaw: String? = row["finalizationReason"]
    return LocalConversationDetail(
      conversationId: conversationId,
      startedAt: row["startedAt"],
      finishedAt: row["finishedAt"],
      language: row["language"],
      autoDetectLanguage: row["autoDetectLanguage"],
      vocabulary: Self.decodeJSON([String].self, from: vocabularyJSON) ?? [],
      timezone: row["timezone"],
      inputDeviceName: row["inputDeviceName"],
      location: Self.decodeJSON(ConversationLocationSnapshot.self, from: locationJSON),
      status: ConversationLifecycleState(rawValue: row["status"]) ?? .failed,
      lastError: row["lastError"],
      finalizationReason: reasonRaw.flatMap(TranscriptionFinalizationReason.init(rawValue:)),
      finalizationStartedAt: row["finalizationStartedAt"],
      finalizationCompletedAt: row["finalizationCompletedAt"],
      title: row["title"],
      isTitleManuallyEdited: row["isTitleManuallyEdited"],
      overview: row["overview"],
      emoji: row["emoji"],
      commitmentsJson: row["commitmentsJson"],
      starred: row["starred"],
      folderId: row["folderId"],
      createdAt: row["createdAt"],
      updatedAt: row["updatedAt"],
      contentGeneration: row["contentGeneration"],
      segments: try fetchLocalSegments(database, sessionId: sessionId),
      speakerLabels: labels)
  }

  private static func makeLocalConversationSummary(_ row: Row) -> LocalConversationSummary {
    LocalConversationSummary(
      conversationId: row["conversationId"],
      startedAt: row["startedAt"],
      finishedAt: row["finishedAt"],
      status: ConversationLifecycleState(rawValue: row["status"]) ?? .failed,
      title: row["title"],
      overview: row["overview"],
      emoji: row["emoji"],
      starred: row["starred"],
      folderId: row["folderId"],
      segmentCount: row["segmentCount"],
      createdAt: row["createdAt"],
      updatedAt: row["updatedAt"],
      contentGeneration: row["contentGeneration"])
  }

  private static func localConversationPredicate(
    query: ConversationLocalQuery
  ) -> (sql: String, arguments: StatementArguments) {
    var clauses: [String] = []
    var arguments: StatementArguments = []
    if let statuses = query.statuses, !statuses.isEmpty {
      clauses.append("s.status IN (\(statuses.map { _ in "?" }.joined(separator: ", ")))")
      for status in statuses {
        arguments += [status.rawValue]
      }
    } else {
      clauses.append("s.status NOT IN ('recording', 'merging')")
    }
    if query.starredOnly {
      clauses.append("s.starred = 1")
    }
    if let startDate = query.startDate {
      clauses.append("s.startedAt >= ?")
      arguments += [startDate]
    }
    if let endDate = query.endDate {
      clauses.append("s.startedAt < ?")
      arguments += [endDate]
    }
    if let folderId = query.folderId {
      clauses.append("s.folderId = ?")
      arguments += [folderId]
    }
    return (clauses.joined(separator: " AND "), arguments)
  }

  private static func normalizedFolderName(_ name: String) throws -> String {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.count <= 100 else {
      throw TranscriptionStorageError.invalidState("folder name must be 1 through 100 characters")
    }
    return normalized
  }

  private static func commonFolderId(_ rows: [Row]) -> String? {
    let folders = rows.map { $0["folderId"] as String? }
    guard let first = folders.first, folders.dropFirst().allSatisfy({ $0 == first }) else { return nil }
    return first
  }

  static func admitWork(
    _ database: Database,
    conversationId: String,
    generation: Int,
    kind: ConversationEnrichmentKind,
    now: Date
  ) throws {
    try database.execute(
      sql: """
        INSERT OR IGNORE INTO conversation_enrichment_work
          (conversationId, contentGeneration, kind, state, attemptCount, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, 0, ?, ?)
        """,
      arguments: [conversationId, generation, kind.rawValue, ConversationEnrichmentState.pending.rawValue, now, now])
  }

  private static func completeConversationWhenEnrichmentIsTerminal(
    _ database: Database,
    conversationId: String,
    generation: Int,
    now: Date
  ) throws {
    let unfinished =
      try Int.fetchOne(
        database,
        sql: """
          SELECT COUNT(*) FROM conversation_enrichment_work
          WHERE conversationId = ? AND contentGeneration = ?
            AND kind IN (?, ?) AND state IN (?, ?)
          """,
        arguments: [
          conversationId, generation,
          ConversationEnrichmentKind.structure.rawValue,
          ConversationEnrichmentKind.actionItems.rawValue,
          ConversationEnrichmentState.pending.rawValue,
          ConversationEnrichmentState.running.rawValue,
        ]) ?? 0
    guard unfinished == 0 else { return }
    try database.execute(
      sql:
        "UPDATE transcription_sessions SET status = ?, updatedAt = ? WHERE conversationId = ? AND contentGeneration = ?",
      arguments: [ConversationLifecycleState.completed.rawValue, now, conversationId, generation])
  }

  private static func supersedeDiscardAndReadmit(
    _ database: Database,
    conversationId: String,
    oldGeneration: Int,
    currentGeneration: Int
  ) throws {
    let now = Date()
    try database.execute(
      sql: """
          UPDATE conversation_enrichment_work SET state = ?, updatedAt = ?
          WHERE conversationId = ? AND contentGeneration = ? AND kind = ?
        """,
      arguments: [
        ConversationEnrichmentState.superseded.rawValue, now, conversationId, oldGeneration,
        ConversationEnrichmentKind.discard.rawValue,
      ])
    try admitWork(
      database, conversationId: conversationId, generation: currentGeneration, kind: .discard, now: now)
  }

  private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  private static func decodeJSON<T: Decodable>(_ type: T.Type, from value: String?) -> T? {
    guard let value, let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}
