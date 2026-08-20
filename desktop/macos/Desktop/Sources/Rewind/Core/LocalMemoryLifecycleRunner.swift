import Foundation

struct LocalMemoryLifecycleReport: Equatable, Sendable {
  var normalized = 0
  var extracted = 0
  var consolidated = 0
  var finalizedDeletions = 0
  var failures = 0
}

/// Owns retryable Memory processing while `omi.db` remains the only durable authority.
/// External services return proposals; every accepted result crosses the owner/revision
/// fence and commits atomically to the current owner's database.
actor LocalMemoryLifecycleRunner {
  static let shared = LocalMemoryLifecycleRunner(
    storage: .shared,
    conversations: .shared,
    computer: APIClient.shared,
    requiresOwnerAuthorization: true)

  private let storage: MemoryStorage
  private let conversations: TranscriptionStorage
  private let computer: any MemoryComputing
  private let requiresOwnerAuthorization: Bool
  private let clock: @Sendable () -> Date
  private let requestID: @Sendable () -> UUID
  private let cadenceNanoseconds: UInt64
  private var cadenceTask: Task<Void, Never>?

  init(
    storage: MemoryStorage,
    conversations: TranscriptionStorage,
    computer: any MemoryComputing,
    requiresOwnerAuthorization: Bool,
    clock: @escaping @Sendable () -> Date = Date.init,
    requestID: @escaping @Sendable () -> UUID = UUID.init,
    cadenceNanoseconds: UInt64 = 60_000_000_000
  ) {
    self.storage = storage
    self.conversations = conversations
    self.computer = computer
    self.requiresOwnerAuthorization = requiresOwnerAuthorization
    self.clock = clock
    self.requestID = requestID
    self.cadenceNanoseconds = cadenceNanoseconds
  }

  func start() {
    guard cadenceTask == nil else { return }
    cadenceTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        _ = await self.runOnce()
        do { try await Task.sleep(nanoseconds: self.cadenceNanoseconds) } catch { return }
      }
    }
  }

  func stop() {
    cadenceTask?.cancel()
    cadenceTask = nil
  }

  func runOnce() async -> LocalMemoryLifecycleReport {
    let snapshot = requiresOwnerAuthorization ? RuntimeOwnerIdentity.captureAuthorizationSnapshot() : nil
    guard !requiresOwnerAuthorization || snapshot != nil else { return LocalMemoryLifecycleReport() }
    let authorization =
      snapshot.map { captured in
        LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(captured) }
      } ?? .unrestricted

    do { try await RewindDatabase.shared.initialize() } catch {
      return LocalMemoryLifecycleReport(failures: 1)
    }
    let ownerGeneration = await RewindDatabase.shared.poolGeneration()
    var report = LocalMemoryLifecycleReport()
    report.finalizedDeletions = (try? await storage.finalizeExpiredDeletions(now: clock())) ?? 0
    if (try? await storage.enqueueDueLifecycleWork(
      now: clock(), ownerGeneration: ownerGeneration)) == nil
    {
      report.failures += 1
    }
    await processNormalizations(
      snapshot: snapshot, authorization: authorization,
      ownerGeneration: ownerGeneration, report: &report)
    await processExtractions(
      snapshot: snapshot, authorization: authorization,
      ownerGeneration: ownerGeneration, report: &report)
    await processConsolidations(
      snapshot: snapshot, authorization: authorization,
      ownerGeneration: ownerGeneration, report: &report)
    return report
  }

  private func processNormalizations(
    snapshot: RuntimeOwnerAuthorizationSnapshot?,
    authorization: LocalMutationAuthorization,
    ownerGeneration: Int,
    report: inout LocalMemoryLifecycleReport
  ) async {
    let work: [LeasedMemoryWork]
    do {
      work = try await storage.leaseDueWork(
        kind: .normalize, now: clock(), ownerGeneration: ownerGeneration, limit: 8)
    } catch {
      report.failures += 1
      return
    }

    for lease in work {
      guard let memory = lease.memory else {
        await retry(lease.work.id, code: "normalization_memory_missing", report: &report)
        continue
      }
      let requestId = requestID()
      do {
        let response = try await computer.normalizeMemory(
          MemoryNormalizeComputeRequest(
            requestId: requestId,
            revision: lease.work.inputRevision,
            assertion: String(memory.content.prefix(50_000))),
          authorizationSnapshot: snapshot)
        try Self.validateNormalization(response, requestId: requestId, revision: lease.work.inputRevision)
        _ = try await authorization.withCommitLease {
          try await self.storage.completeNormalization(
            workId: lease.work.id,
            memoryId: memory.id,
            expectedRevision: lease.work.inputRevision,
            normalizedContent: response.normalizedContent,
            receiptId: response.requestId.uuidString.lowercased(),
            ownerGeneration: ownerGeneration,
            now: self.clock())
        }
        report.normalized += 1
      } catch LocalMutationAuthorizationError.revoked {
        report.failures += 1
      } catch {
        await retry(lease.work.id, code: "normalization_compute_failed", report: &report)
      }
    }
  }

  private func processExtractions(
    snapshot: RuntimeOwnerAuthorizationSnapshot?,
    authorization: LocalMutationAuthorization,
    ownerGeneration: Int,
    report: inout LocalMemoryLifecycleReport
  ) async {
    let work: [LeasedMemoryWork]
    do {
      work = try await storage.leaseDueWork(
        kind: .extract, now: clock(), ownerGeneration: ownerGeneration, limit: 4)
    } catch {
      report.failures += 1
      return
    }

    for lease in work {
      guard let conversationId = lease.work.conversationId else {
        await retry(lease.work.id, code: "extraction_source_missing", report: &report)
        continue
      }
      do {
        guard let conversation = try await conversations.conversationDetail(id: conversationId),
          conversation.contentGeneration == lease.work.inputGeneration
        else { throw MemoryStorageError.staleRevision }
        let segments = try Self.boundedSegments(conversation)
        let requestId = requestID()
        let response = try await computer.extractMemories(
          MemoryExtractComputeRequest(
            requestId: requestId,
            generation: lease.work.inputGeneration,
            segments: segments,
            language: String(conversation.language.prefix(32))),
          authorizationSnapshot: snapshot)
        let admissions = try Self.validateExtraction(
          response,
          requestId: requestId,
          generation: lease.work.inputGeneration,
          requestSegments: segments,
          sourceSegments: conversation.segments)
        let accepted = try await authorization.withCommitLease {
          try await self.storage.completeExtraction(
            workId: lease.work.id,
            conversationId: conversationId,
            expectedGeneration: lease.work.inputGeneration,
            admissions: admissions,
            receiptId: response.requestId.uuidString.lowercased(),
            ownerGeneration: ownerGeneration,
            now: self.clock())
        }
        report.extracted += accepted.count
      } catch LocalMutationAuthorizationError.revoked {
        report.failures += 1
      } catch {
        await retry(lease.work.id, code: "extraction_compute_failed", report: &report)
      }
    }
  }

  private func processConsolidations(
    snapshot: RuntimeOwnerAuthorizationSnapshot?,
    authorization: LocalMutationAuthorization,
    ownerGeneration: Int,
    report: inout LocalMemoryLifecycleReport
  ) async {
    let leases: [LeasedMemoryWork]
    do {
      leases = try await storage.leaseDueWork(
        kind: .consolidate, now: clock(), ownerGeneration: ownerGeneration, limit: 32)
    } catch {
      report.failures += 1
      return
    }
    guard !leases.isEmpty else { return }
    guard leases.allSatisfy({ $0.memory != nil }) else {
      for lease in leases { await retry(lease.work.id, code: "consolidation_memory_missing", report: &report) }
      return
    }

    let candidateIDs = Set(leases.compactMap { $0.memory?.id })
    do {
      let active = try await storage.list(
        scope: .defaultAccess, includeDismissed: false, limit: 160, offset: 0
      )
      .filter { !candidateIDs.contains($0.id) }
      .prefix(128)
      let candidateTokens = Dictionary(
        uniqueKeysWithValues: leases.enumerated().compactMap { index, lease in
          lease.memory.map { ("c\(index)", (lease, $0)) }
        })
      let activeTokens = Dictionary(
        uniqueKeysWithValues: active.enumerated().map { index, memory in ("m\(index)", memory) })
      let requestId = requestID()
      let request = MemoryConsolidateComputeRequest(
        requestId: requestId,
        generation: ownerGeneration,
        candidates: candidateTokens.sorted(by: { $0.key < $1.key }).map { token, value in
          MemoryConsolidateComputeCandidate(
            token: token, content: String(value.1.content.prefix(50_000)),
            evidenceTokens: [], sensitivityLabels: [])
        },
        activeMemories: activeTokens.sorted(by: { $0.key < $1.key }).map { token, memory in
          MemoryConsolidateComputeActiveMemory(
            token: token, content: String(memory.content.prefix(50_000)),
            layer: memory.layer.rawValue, revision: memory.revision)
        })
      let response = try await computer.consolidateMemories(
        request, authorizationSnapshot: snapshot)
      let applications = try Self.validateConsolidation(
        response,
        requestId: requestId,
        generation: ownerGeneration,
        candidates: candidateTokens,
        active: activeTokens)
      let changed = try await authorization.withCommitLease {
        try await self.storage.completeConsolidation(
          applications: applications,
          receiptId: response.requestId.uuidString.lowercased(),
          ownerGeneration: ownerGeneration,
          now: self.clock())
      }
      report.consolidated += changed.count
    } catch LocalMutationAuthorizationError.revoked {
      report.failures += leases.count
    } catch {
      for lease in leases {
        await retry(lease.work.id, code: "consolidation_compute_failed", report: &report)
      }
    }
  }

  private func retry(
    _ workId: String,
    code: String,
    report: inout LocalMemoryLifecycleReport
  ) async {
    try? await storage.retryWork(id: workId, errorCode: code, now: clock())
    report.failures += 1
  }

  private static func validateNormalization(
    _ response: MemoryNormalizeComputeResponse,
    requestId: UUID,
    revision: Int
  ) throws {
    let content = response.normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowedSubjects = Set([
      "primary_user", "user_owned_project", "user_relationship", "third_party", "unclear",
    ])
    let predicate = response.predicate
    let predicatePattern = try NSRegularExpression(pattern: "^[a-z][a-z0-9_]{0,127}$")
    let predicateRange = NSRange(predicate.startIndex..., in: predicate)
    guard response.requestId == requestId,
      response.revision == revision,
      !content.isEmpty,
      content.count <= 50_000,
      allowedSubjects.contains(response.subject),
      predicatePattern.firstMatch(in: predicate, range: predicateRange) != nil,
      response.arguments.count <= 32,
      response.sensitivityLabels.count <= 16,
      !response.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw MemoryStorageError.invalidTransition("Invalid normalization proposal") }
  }

  private static func boundedSegments(
    _ conversation: LocalConversationDetail
  ) throws -> [MemoryTranscriptComputeSegment] {
    let source = Array(conversation.segments.prefix(500))
    guard !source.isEmpty, source.reduce(0, { $0 + $1.text.count }) <= 1_000_000 else {
      throw MemoryStorageError.invalidTransition("Conversation extraction packet is invalid")
    }
    return source.enumerated().map { index, segment in
      let fallback = segment.isUser ? "Primary user" : "Speaker \(segment.speakerId)"
      let label = conversation.speakerLabels[segment.speakerId]?.name ?? fallback
      return MemoryTranscriptComputeSegment(
        token: "s\(index)", speakerLabel: String(label.prefix(256)),
        text: String(segment.text.prefix(50_000)), isUser: segment.isUser)
    }
  }

  private static func validateExtraction(
    _ response: MemoryExtractComputeResponse,
    requestId: UUID,
    generation: Int,
    requestSegments: [MemoryTranscriptComputeSegment],
    sourceSegments: [LocalTranscriptSegment]
  ) throws -> [MemoryExtractionAdmission] {
    guard response.requestId == requestId, response.generation == generation,
      response.candidates.count <= 32,
      requestSegments.count == sourceSegments.prefix(500).count
    else { throw MemoryStorageError.invalidTransition("Invalid extraction response identity") }
    let indexed = Dictionary(uniqueKeysWithValues: requestSegments.map { ($0.token, $0) })
    let sourceIndexed = Dictionary(
      uniqueKeysWithValues: zip(requestSegments, sourceSegments).map { ($0.0.token, $0.1) })
    var contents = Set<String>()
    return try response.candidates.map { candidate in
      let content = candidate.content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let segment = indexed[candidate.segmentToken],
        let source = sourceIndexed[candidate.segmentToken],
        !content.isEmpty,
        content.count <= 50_000,
        MemoryCategory(rawValue: candidate.category).map({ $0 != .manual }) == true,
        candidate.confidence.isFinite,
        (0...1).contains(candidate.confidence),
        !candidate.quote.isEmpty,
        segment.text.contains(candidate.quote),
        requestSegments.filter({ $0.text.contains(candidate.quote) }).count == 1,
        candidate.subject == (segment.isUser ? "primary_user" : "other_speaker"),
        contents.insert(content).inserted,
        let category = MemoryCategory(rawValue: candidate.category)
      else { throw MemoryStorageError.invalidTransition("Ungrounded extraction candidate") }
      return MemoryExtractionAdmission(
        content: content, category: category, quote: candidate.quote,
        segmentId: source.segmentId, confidence: candidate.confidence)
    }
  }

  private static func validateConsolidation(
    _ response: MemoryConsolidateComputeResponse,
    requestId: UUID,
    generation: Int,
    candidates: [String: (LeasedMemoryWork, MemoryItem)],
    active: [String: MemoryItem]
  ) throws -> [MemoryConsolidationApplication] {
    let returned = response.decisions.map(\.candidateToken)
    guard response.requestId == requestId, response.generation == generation,
      returned.count == Set(returned).count,
      Set(returned) == Set(candidates.keys)
    else { throw MemoryStorageError.invalidTransition("Incomplete consolidation response") }

    return try response.decisions.map { decision in
      guard let candidate = candidates[decision.candidateToken],
        let action = MemoryConsolidationAction(rawValue: decision.action),
        let reconciliation = MemoryReconciliation(rawValue: decision.reconciliation),
        !decision.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        decision.targetMemoryTokens.count <= 8,
        Set(decision.targetMemoryTokens).count == decision.targetMemoryTokens.count,
        decision.targetMemoryTokens.allSatisfy({ active[$0] != nil })
      else { throw MemoryStorageError.invalidTransition("Invalid consolidation decision") }
      let targets = try decision.targetMemoryTokens.map { token -> MemoryConsolidationTarget in
        guard let memory = active[token] else {
          throw MemoryStorageError.invalidTransition("Unknown consolidation target")
        }
        return MemoryConsolidationTarget(memoryId: memory.id, expectedRevision: memory.revision)
      }
      return MemoryConsolidationApplication(
        workId: candidate.0.work.id,
        memoryId: candidate.1.id,
        expectedRevision: candidate.0.work.inputRevision,
        action: action,
        reconciliation: reconciliation,
        targets: targets,
        memoryText: decision.memoryText,
        rationale: decision.rationale)
    }
  }
}
