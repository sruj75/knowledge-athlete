import Foundation

struct LocalMemoryLifecycleReport: Equatable, Sendable {
  var normalized = 0
  var extracted = 0
  var consolidated = 0
  var embedded = 0
  var finalizedDeletions = 0
  var failures = 0
}

protocol MemoryEmbeddingComputing: Sendable {
  func embedBatch(
    texts: [String],
    taskType: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [[Float]]
}

extension EmbeddingService: MemoryEmbeddingComputing {}

/// Owns retryable Memory processing while `heyintentive.db` remains the only durable authority.
/// External services return proposals; every accepted result crosses the owner/revision
/// fence and commits atomically to the current owner's database.
actor LocalMemoryLifecycleRunner {
  static let shared = LocalMemoryLifecycleRunner(
    storage: .shared,
    conversations: .shared,
    computer: APIClient.shared,
    embedder: EmbeddingService.shared,
    requiresOwnerAuthorization: true)

  private let storage: MemoryStorage
  private let conversations: TranscriptionStorage
  private let computer: any MemoryComputing
  private let embedder: (any MemoryEmbeddingComputing)?
  private let requiresOwnerAuthorization: Bool
  private let clock: @Sendable () -> Date
  private let requestID: @Sendable () -> UUID
  private let cadenceNanoseconds: UInt64
  private var cadenceTask: Task<Void, Never>?

  init(
    storage: MemoryStorage,
    conversations: TranscriptionStorage,
    computer: any MemoryComputing,
    embedder: (any MemoryEmbeddingComputing)? = nil,
    requiresOwnerAuthorization: Bool,
    clock: @escaping @Sendable () -> Date = Date.init,
    requestID: @escaping @Sendable () -> UUID = UUID.init,
    cadenceNanoseconds: UInt64 = 60_000_000_000
  ) {
    self.storage = storage
    self.conversations = conversations
    self.computer = computer
    self.embedder = embedder
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
    do {
      try await storage.recoverLifecycleWork(
        ownerGeneration: ownerGeneration, now: clock(), authorization: authorization)
    } catch {
      return LocalMemoryLifecycleReport(failures: 1)
    }
    report.finalizedDeletions =
      (try? await storage.finalizeExpiredDeletions(
        now: clock(), authorization: authorization)) ?? 0
    if (try? await storage.enqueueDueLifecycleWork(
      now: clock(), ownerGeneration: ownerGeneration, authorization: authorization)) == nil
    {
      report.failures += 1
    }
    await processNormalizations(
      snapshot: snapshot, authorization: authorization,
      ownerGeneration: ownerGeneration, report: &report)
    await processExtractions(
      snapshot: snapshot, authorization: authorization,
      ownerGeneration: ownerGeneration, report: &report)
    await processEmbeddings(
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
        kind: .normalize, now: clock(), ownerGeneration: ownerGeneration, limit: 8,
        authorization: authorization)
    } catch {
      report.failures += 1
      return
    }

    for lease in work {
      guard let memory = lease.memory else {
        await retry(
          lease.work.id, code: "normalization_memory_missing", ownerGeneration: ownerGeneration,
          authorization: authorization, report: &report)
        continue
      }
      let requestId = requestID()
      do {
        let response = try await computer.normalizeMemory(
          MemoryNormalizeComputeRequest(
            requestId: requestId,
            revision: lease.work.inputRevision,
            assertion: String(memory.content.prefix(50_000)),
            source: memory.correctedAt == nil ? "manual" : "correction",
            sourceAttribution: memory.subject ?? "primary_user",
            provenanceTokens: Array(memory.evidenceTokens.prefix(16))),
          authorizationSnapshot: snapshot)
        try Self.validateNormalization(response, requestId: requestId, revision: lease.work.inputRevision)
        _ = try await storage.completeNormalization(
          workId: lease.work.id,
          memoryId: memory.id,
          expectedRevision: lease.work.inputRevision,
          normalizedContent: response.normalizedContent,
          subject: response.subject,
          predicate: response.predicate,
          arguments: response.arguments,
          sensitivityLabels: response.sensitivityLabels,
          receiptId: response.requestId.uuidString.lowercased(),
          ownerGeneration: ownerGeneration,
          now: clock(),
          authorization: authorization)
        report.normalized += 1
      } catch LocalMutationAuthorizationError.revoked {
        report.failures += 1
      } catch {
        await retry(
          lease.work.id, code: "normalization_compute_failed", ownerGeneration: ownerGeneration,
          authorization: authorization, report: &report)
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
        kind: .extract, now: clock(), ownerGeneration: ownerGeneration, limit: 4,
        authorization: authorization)
    } catch {
      report.failures += 1
      return
    }

    for lease in work {
      guard let conversationId = lease.work.conversationId else {
        await retry(
          lease.work.id, code: "extraction_source_missing", ownerGeneration: ownerGeneration,
          authorization: authorization, report: &report)
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
        let accepted = try await storage.completeExtraction(
          workId: lease.work.id,
          conversationId: conversationId,
          expectedGeneration: lease.work.inputGeneration,
          admissions: admissions,
          receiptId: response.requestId.uuidString.lowercased(),
          ownerGeneration: ownerGeneration,
          now: clock(),
          authorization: authorization)
        report.extracted += accepted.count
      } catch LocalMutationAuthorizationError.revoked {
        report.failures += 1
      } catch {
        await retry(
          lease.work.id, code: "extraction_compute_failed", ownerGeneration: ownerGeneration,
          authorization: authorization, report: &report)
      }
    }
  }

  private func processEmbeddings(
    snapshot: RuntimeOwnerAuthorizationSnapshot?,
    authorization: LocalMutationAuthorization,
    ownerGeneration: Int,
    report: inout LocalMemoryLifecycleReport
  ) async {
    guard let embedder else { return }
    guard let snapshot else {
      report.failures += 1
      return
    }
    let leases: [LeasedMemoryWork]
    do {
      leases = try await storage.leaseDueWork(
        kind: .embed, now: clock(), ownerGeneration: ownerGeneration, limit: 64,
        authorization: authorization)
    } catch {
      report.failures += 1
      return
    }
    let valid = leases.filter { $0.memory != nil }
    for lease in leases where lease.memory == nil {
      await retry(
        lease.work.id, code: "embedding_memory_missing", ownerGeneration: ownerGeneration,
        authorization: authorization, report: &report)
    }
    guard !valid.isEmpty else { return }
    do {
      let vectors = try await embedder.embedBatch(
        texts: valid.compactMap { $0.memory?.content },
        taskType: "RETRIEVAL_DOCUMENT",
        authorizationSnapshot: snapshot)
      guard vectors.count == valid.count else { throw MemoryStorageError.invalidEmbedding }
      for (lease, vector) in zip(valid, vectors) {
        guard let memory = lease.memory else { continue }
        try await storage.storeEmbedding(
          workId: lease.work.id,
          memoryId: memory.id,
          expectedRevision: lease.work.inputRevision,
          model: EmbeddingService.modelName,
          vector: vector.map(Double.init),
          ownerGeneration: ownerGeneration,
          now: clock(),
          authorization: authorization)
        report.embedded += 1
      }
    } catch LocalMutationAuthorizationError.revoked {
      report.failures += valid.count
    } catch {
      for lease in valid {
        await retry(
          lease.work.id, code: "embedding_compute_failed", ownerGeneration: ownerGeneration,
          authorization: authorization, report: &report)
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
        kind: .consolidate, now: clock(), ownerGeneration: ownerGeneration, limit: 32,
        authorization: authorization)
    } catch {
      report.failures += 1
      return
    }
    guard !leases.isEmpty else { return }
    guard leases.allSatisfy({ $0.memory != nil }) else {
      for lease in leases {
        await retry(
          lease.work.id, code: "consolidation_memory_missing",
          ownerGeneration: ownerGeneration, authorization: authorization, report: &report)
      }
      return
    }

    let candidateIDs = Set(leases.compactMap { $0.memory?.id })
    do {
      let active = try await storage.relevantConsolidationMemories(candidateIDs: candidateIDs)
      var candidateTokens: [String: (LeasedMemoryWork, MemoryItem)] = [:]
      for (index, lease) in leases.enumerated() {
        guard let memory = lease.memory else { continue }
        candidateTokens["c\(index)"] = (lease, memory)
      }
      var activeTokens: [String: MemoryItem] = [:]
      for (index, memory) in active.enumerated() {
        activeTokens["m\(index)"] = memory
      }
      let requestId = requestID()
      let request = MemoryConsolidateComputeRequest(
        requestId: requestId,
        generation: ownerGeneration,
        candidates: candidateTokens.sorted(by: { $0.key < $1.key }).map { token, value in
          MemoryConsolidateComputeCandidate(
            token: token, content: String(value.1.content.prefix(50_000)),
            evidenceTokens: Array(value.1.evidenceTokens.prefix(32)),
            sensitivityLabels: Array(value.1.sensitivityLabels.prefix(16)),
            subject: value.1.subject ?? "unclear",
            predicate: value.1.predicate,
            arguments: value.1.arguments)
        },
        activeMemories: activeTokens.sorted(by: { $0.key < $1.key }).map { token, memory in
          MemoryConsolidateComputeActiveMemory(
            token: token, content: String(memory.content.prefix(50_000)),
            layer: memory.layer.rawValue, revision: memory.revision,
            subject: memory.subject ?? "unclear",
            predicate: memory.predicate,
            arguments: memory.arguments,
            sensitivityLabels: Array(memory.sensitivityLabels.prefix(16)))
        })
      let response = try await computer.consolidateMemories(
        request, authorizationSnapshot: snapshot)
      let applications = try Self.validateConsolidation(
        response,
        requestId: requestId,
        generation: ownerGeneration,
        candidates: candidateTokens,
        active: activeTokens)
      let changed = try await storage.completeConsolidation(
        applications: applications,
        receiptId: response.requestId.uuidString.lowercased(),
        ownerGeneration: ownerGeneration,
        now: clock(),
        authorization: authorization)
      report.consolidated += changed.count
    } catch LocalMutationAuthorizationError.revoked {
      report.failures += leases.count
    } catch {
      for lease in leases {
        await retry(
          lease.work.id, code: "consolidation_compute_failed", ownerGeneration: ownerGeneration,
          authorization: authorization, report: &report)
      }
    }
  }

  private func retry(
    _ workId: String,
    code: String,
    ownerGeneration: Int,
    authorization: LocalMutationAuthorization,
    report: inout LocalMemoryLifecycleReport
  ) async {
    try? await storage.retryWork(
      id: workId, errorCode: code, now: clock(), ownerGeneration: ownerGeneration,
      authorization: authorization)
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
      Self.argumentsAreBounded(response.arguments),
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
    var indexed: [String: MemoryTranscriptComputeSegment] = [:]
    var sourceIndexed: [String: LocalTranscriptSegment] = [:]
    for (requestSegment, sourceSegment) in zip(requestSegments, sourceSegments) {
      indexed[requestSegment.token] = requestSegment
      sourceIndexed[requestSegment.token] = sourceSegment
    }
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
        candidate.speakerLabel == segment.speakerLabel,
        candidate.subject == (segment.isUser ? "primary_user" : "other_speaker"),
        !candidate.about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        ["general", "sensitive"].contains(candidate.archiveClass),
        candidate.riskFlags.count <= 16,
        candidate.sensitivityLabels.count <= 16,
        contents.insert(content).inserted,
        let category = MemoryCategory(rawValue: candidate.category)
      else { throw MemoryStorageError.invalidTransition("Ungrounded extraction candidate") }
      return MemoryExtractionAdmission(
        content: content, category: category, quote: candidate.quote,
        segmentId: source.segmentId, confidence: candidate.confidence,
        evidenceTokens: [candidate.segmentToken],
        sensitivityLabels: candidate.sensitivityLabels,
        subject: candidate.subject == "primary_user" ? "primary_user" : "third_party",
        archiveClass: candidate.archiveClass,
        riskFlags: candidate.riskFlags)
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

    let applications = try response.decisions.map { decision in
      guard let candidate = candidates[decision.candidateToken],
        let action = MemoryConsolidationAction(rawValue: decision.action),
        let reconciliation = MemoryReconciliation(rawValue: decision.reconciliation),
        !decision.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        decision.targetMemoryTokens.count <= 8,
        Set(decision.targetMemoryTokens).count == decision.targetMemoryTokens.count,
        decision.targetMemoryTokens.allSatisfy({ active[$0] != nil }),
        decision.evidenceTokens.count == Set(decision.evidenceTokens).count,
        Set(decision.evidenceTokens).isSubset(of: Set(candidate.1.evidenceTokens)),
        Set(decision.sensitivityLabels) == Set(candidate.1.sensitivityLabels),
        decision.subject == (candidate.1.subject ?? "unclear"),
        ["high", "medium", "low"].contains(decision.confidence)
      else { throw MemoryStorageError.invalidTransition("Invalid consolidation decision") }
      if action == .promote {
        let restricted = Set([
          "credential", "secret", "financial", "health", "intimate", "minor", "minors",
          "workplace_confidential", "identity_authentication",
        ])
        let relationshipIsDurable =
          (decision.relationshipToUser == "self" && decision.aboutness == "primary_user")
          || (decision.relationshipToUser == "owned_work"
            && decision.aboutness == "user_owned_project")
          || (decision.relationshipToUser == "adopted"
            && decision.aboutness == "user_relationship")
          || (decision.relationshipToUser == "other_speaker"
            && decision.aboutness == "user_relationship"
            && decision.basisForMemory == "recurring")
        guard !decision.evidenceTokens.isEmpty,
          restricted.isDisjoint(with: Set(decision.sensitivityLabels)),
          !["third_party", "unclear"].contains(decision.aboutness),
          decision.basisForMemory != "weak_or_none",
          relationshipIsDurable,
          decision.predicate?.range(of: "^[a-z][a-z0-9_]{0,127}$", options: .regularExpression) != nil,
          Self.argumentsAreBounded(decision.arguments)
        else { throw MemoryStorageError.invalidTransition("Unsafe consolidation promotion") }
      }
      guard !(action == .promote && reconciliation == .duplicate),
        action == .promote || ![.replace, .merge, .keepBoth].contains(reconciliation)
      else { throw MemoryStorageError.invalidTransition("Invalid consolidation route") }
      let targets = try decision.targetMemoryTokens.map { token -> MemoryConsolidationTarget in
        guard let memory = active[token] else {
          throw MemoryStorageError.invalidTransition("Unknown consolidation target")
        }
        if reconciliation == .replace || reconciliation == .merge {
          guard memory.layer == .longTerm else {
            throw MemoryStorageError.invalidTransition("Only Long-term targets may be superseded")
          }
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
        evidenceTokens: decision.evidenceTokens,
        subject: decision.subject,
        predicate: decision.predicate,
        arguments: decision.arguments,
        sensitivityLabels: decision.sensitivityLabels,
        relationshipToUser: decision.relationshipToUser,
        aboutness: decision.aboutness,
        basisForMemory: decision.basisForMemory,
        confidence: decision.confidence,
        rationale: decision.rationale)
    }
    let superseded = zip(response.decisions, applications)
      .filter { $0.1.reconciliation == .replace || $0.1.reconciliation == .merge }
      .flatMap { $0.0.targetMemoryTokens }
    guard Set(superseded).count == superseded.count else {
      throw MemoryStorageError.invalidTransition("Two decisions supersede the same target")
    }
    return applications
  }

  private static func argumentsAreBounded(_ arguments: [String: String]) -> Bool {
    guard arguments.count <= 32,
      arguments.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 128 && $0.value.count <= 1_024 }),
      let encoded = try? JSONSerialization.data(withJSONObject: arguments),
      encoded.count <= 8_192
    else { return false }
    return true
  }
}
