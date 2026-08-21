import XCTest

@testable import Omi_Computer

private actor MemoryComputeStub: MemoryComputing {
  typealias Normalize = @Sendable (MemoryNormalizeComputeRequest) async throws -> MemoryNormalizeComputeResponse
  typealias Extract = @Sendable (MemoryExtractComputeRequest) async throws -> MemoryExtractComputeResponse
  typealias Consolidate =
    @Sendable (MemoryConsolidateComputeRequest) async throws -> MemoryConsolidateComputeResponse

  private let normalizeHandler: Normalize
  private let extractHandler: Extract
  private let consolidateHandler: Consolidate

  init(
    normalize: @escaping Normalize = { _ in throw APIError.invalidResponse },
    extract: @escaping Extract = { _ in throw APIError.invalidResponse },
    consolidate: @escaping Consolidate = { _ in throw APIError.invalidResponse }
  ) {
    normalizeHandler = normalize
    extractHandler = extract
    consolidateHandler = consolidate
  }

  func normalizeMemory(
    _ request: MemoryNormalizeComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryNormalizeComputeResponse {
    try await normalizeHandler(request)
  }

  func extractMemories(
    _ request: MemoryExtractComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryExtractComputeResponse {
    try await extractHandler(request)
  }

  func consolidateMemories(
    _ request: MemoryConsolidateComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> MemoryConsolidateComputeResponse {
    try await consolidateHandler(request)
  }
}

private actor MemoryEmbeddingStub: MemoryEmbeddingComputing {
  private(set) var batches: [[String]] = []

  func embedBatch(
    texts: [String],
    taskType: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [[Float]] {
    batches.append(texts)
    return texts.map { _ in [1, 0] }
  }
}

@MainActor
final class LocalMemoryLifecycleRunnerTests: XCTestCase {
  private var userDir: URL?

  override func setUp() async throws {
    let fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "memory-lifecycle-runner")
    userDir = fixture.userDir
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: userDir)
  }

  func testNormalizationCommitsOnlyTheCurrentRevision() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let accepted = try await MemoryStorage.shared.acceptExplicitAssertion(
      content: "  I prefer dark roast coffee with oat milk.  ",
      now: now)
    let requestID = UUID()
    let computer = MemoryComputeStub(normalize: { request in
      MemoryNormalizeComputeResponse(
        requestId: request.requestId,
        revision: request.revision,
        normalizedContent: "Prefers dark roast coffee with oat milk.",
        subject: "primary_user",
        predicate: "prefers_coffee",
        arguments: ["roast": "dark", "milk": "oat"],
        sensitivityLabels: [],
        rationale: "Preserved every material detail")
    })
    let runner = LocalMemoryLifecycleRunner(
      storage: .shared,
      conversations: .shared,
      computer: computer,
      requiresOwnerAuthorization: false,
      clock: { now },
      requestID: { requestID })

    let report = await runner.runOnce()
    let persisted = try await MemoryStorage.shared.memory(id: accepted.id)
    let saved = try XCTUnwrap(persisted)

    XCTAssertEqual(report.normalized, 1)
    XCTAssertEqual(saved.content, "Prefers dark roast coffee with oat milk.")
    XCTAssertEqual(saved.revision, 2)
  }

  func testGroundedConversationExtractionAdmitsLocallyAndInvalidQuoteCommitsNothing() async throws {
    let storage = TranscriptionStorage.shared
    let validConversation = try await storage.beginConversation(
      configuration: .testDefault, authorization: .unrestricted)
    try await storage.upsertSegments(
      conversationId: validConversation.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: "segment-valid", speakerId: 0,
          text: "I train for a half marathon every Saturday.",
          startTime: 0, endTime: 2, isUser: true, translations: [])
      ], authorization: .unrestricted)
    let generation = await RewindDatabase.shared.poolGeneration()
    try await MemoryStorage.shared.enqueueConversationExtraction(
      conversationId: validConversation.conversationId,
      generation: 0,
      ownerGeneration: generation)

    let computer = MemoryComputeStub(extract: { request in
      MemoryExtractComputeResponse(
        requestId: request.requestId,
        generation: request.generation,
        candidates: [
          MemoryExtractComputeCandidate(
            content: "Trains for a half marathon every Saturday.",
            category: "system",
            quote: "I train for a half marathon every Saturday.",
            segmentToken: "s0",
            speakerLabel: "Primary user",
            subject: "primary_user",
            about: "the user",
            archiveClass: "sensitive",
            riskFlags: ["health"],
            sensitivityLabels: ["intimate"],
            confidence: 0.96)
        ])
    })
    let runner = LocalMemoryLifecycleRunner(
      storage: .shared, conversations: storage, computer: computer,
      requiresOwnerAuthorization: false)

    let report = await runner.runOnce()
    let rows = try await MemoryStorage.shared.list(scope: .defaultAccess, limit: 100, offset: 0)

    XCTAssertEqual(report.extracted, 1)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].source, .conversation)
    XCTAssertEqual(rows[0].conversationId, validConversation.conversationId)
    XCTAssertEqual(rows[0].sourceSegmentId, "segment-valid")
    XCTAssertEqual(Set(rows[0].sensitivityLabels), Set(["health", "intimate", "secret"]))

    let invalidConversation = try await storage.beginConversation(
      configuration: .testDefault, authorization: .unrestricted)
    try await storage.upsertSegments(
      conversationId: invalidConversation.conversationId,
      segments: [
        ConversationSegmentInput(
          segmentId: "segment-invalid", speakerId: 0, text: "I drink tea.",
          startTime: 0, endTime: 1, isUser: true, translations: [])
      ], authorization: .unrestricted)
    try await MemoryStorage.shared.enqueueConversationExtraction(
      conversationId: invalidConversation.conversationId,
      generation: 0,
      ownerGeneration: generation)
    let invalidComputer = MemoryComputeStub(extract: { request in
      MemoryExtractComputeResponse(
        requestId: request.requestId,
        generation: request.generation,
        candidates: [
          MemoryExtractComputeCandidate(
            content: "Drinks coffee.", category: "system", quote: "I drink coffee.",
            segmentToken: "s0", speakerLabel: "Primary user", subject: "primary_user",
            about: "the user", archiveClass: "general", riskFlags: [],
            sensitivityLabels: [], confidence: 0.9)
        ])
    })
    let invalidRunner = LocalMemoryLifecycleRunner(
      storage: .shared, conversations: storage, computer: invalidComputer,
      requiresOwnerAuthorization: false)

    let invalidReport = await invalidRunner.runOnce()
    let afterInvalid = try await MemoryStorage.shared.list(scope: .defaultAccess, limit: 100, offset: 0)
    XCTAssertEqual(invalidReport.extracted, 0)
    XCTAssertEqual(afterInvalid.count, 1)
  }

  func testExtractionReceiptReplayDoesNotDuplicateAcceptedRows() async throws {
    let conversation = try await TranscriptionStorage.shared.beginConversation(
      configuration: .testDefault, authorization: .unrestricted)
    let ownerGeneration = await RewindDatabase.shared.poolGeneration()
    try await MemoryStorage.shared.enqueueConversationExtraction(
      conversationId: conversation.conversationId,
      generation: 0,
      ownerGeneration: ownerGeneration)
    let leases = try await MemoryStorage.shared.leaseDueWork(
      kind: .extract, ownerGeneration: ownerGeneration)
    let lease = try XCTUnwrap(leases.first)
    let admission = MemoryExtractionAdmission(
      content: "Prefers tea.", category: .system, quote: "I prefer tea.",
      segmentId: "segment-1", confidence: 0.95)

    let first = try await MemoryStorage.shared.completeExtraction(
      workId: lease.work.id,
      conversationId: conversation.conversationId,
      expectedGeneration: 0,
      admissions: [admission],
      receiptId: "receipt-extract",
      ownerGeneration: ownerGeneration)
    let replay = try await MemoryStorage.shared.completeExtraction(
      workId: lease.work.id,
      conversationId: conversation.conversationId,
      expectedGeneration: 0,
      admissions: [admission],
      receiptId: "receipt-extract",
      ownerGeneration: ownerGeneration)
    let storedCount = try await MemoryStorage.shared.count()

    XCTAssertEqual(first, replay)
    XCTAssertEqual(storedCount, 1)
  }

  func testConsolidationAppliesOneCompleteDecisionAtomically() async throws {
    let now = Date(timeIntervalSince1970: 2_000)
    let candidate = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(
        content: "Runs every Saturday", category: .system, layer: .shortTerm,
        source: .conversation, subject: "primary_user"),
      now: now)
    let computer = MemoryComputeStub(consolidate: { request in
      MemoryConsolidateComputeResponse(
        requestId: request.requestId,
        generation: request.generation,
        decisions: request.candidates.map {
          MemoryConsolidateComputeDecision(
            candidateToken: $0.token,
            action: "promote",
            reconciliation: "create",
            targetMemoryTokens: [],
            memoryText: "Runs every Saturday.",
            evidenceTokens: $0.evidenceTokens,
            subject: $0.subject,
            predicate: "runs_on_schedule",
            arguments: ["day": "Saturday"],
            sensitivityLabels: $0.sensitivityLabels,
            relationshipToUser: "self",
            aboutness: "primary_user",
            basisForMemory: "explicit",
            confidence: "high",
            rationale: "Stable repeated preference")
        })
    })
    let runner = LocalMemoryLifecycleRunner(
      storage: .shared, conversations: .shared, computer: computer,
      requiresOwnerAuthorization: false, clock: { now })

    let report = await runner.runOnce()
    let persisted = try await MemoryStorage.shared.memory(id: candidate.id)
    let saved = try XCTUnwrap(persisted)

    XCTAssertEqual(report.consolidated, 1)
    XCTAssertEqual(saved.layer, .longTerm)
    XCTAssertEqual(saved.content, "Runs every Saturday.")
    XCTAssertNil(saved.expiresAt)
  }

  func testLeaseRecoveryUsesBoundedBackoffAndStopsAfterThreeFailures() async throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let ownerGeneration = await RewindDatabase.shared.poolGeneration()
    _ = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Runs every Saturday", layer: .shortTerm),
      now: now, ownerGeneration: ownerGeneration)

    let first = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now, ownerGeneration: ownerGeneration)
    XCTAssertEqual(first.count, 1)
    let stillLeased = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(599),
      ownerGeneration: ownerGeneration)
    XCTAssertTrue(stillLeased.isEmpty)

    let recovered = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(600),
      ownerGeneration: ownerGeneration)
    XCTAssertEqual(recovered.map(\.work.id), first.map(\.work.id))
    try await MemoryStorage.shared.retryWork(
      id: recovered[0].work.id, errorCode: "provider", now: now.addingTimeInterval(600))

    let beforeFirstBackoff = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(899),
      ownerGeneration: ownerGeneration)
    XCTAssertTrue(beforeFirstBackoff.isEmpty)
    let second = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(900),
      ownerGeneration: ownerGeneration)
    XCTAssertEqual(second.first?.work.attemptCount, 1)
    try await MemoryStorage.shared.retryWork(
      id: second[0].work.id, errorCode: "provider", now: now.addingTimeInterval(900))

    let beforeSecondBackoff = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(1_499),
      ownerGeneration: ownerGeneration)
    XCTAssertTrue(beforeSecondBackoff.isEmpty)
    let third = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(1_500),
      ownerGeneration: ownerGeneration)
    XCTAssertEqual(third.first?.work.attemptCount, 2)
    try await MemoryStorage.shared.retryWork(
      id: third[0].work.id, errorCode: "provider", now: now.addingTimeInterval(1_500))

    let terminal = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now.addingTimeInterval(10_000),
      ownerGeneration: ownerGeneration)
    XCTAssertTrue(terminal.isEmpty)
  }

  func testReviewDefersExpiryAndRequeuesExactlyOneDueDecision() async throws {
    let now = Date(timeIntervalSince1970: 20_000)
    let ownerGeneration = await RewindDatabase.shared.poolGeneration()
    let candidate = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "A provisional observation", layer: .shortTerm),
      now: now, ownerGeneration: ownerGeneration)
    let leases = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now, ownerGeneration: ownerGeneration)
    let lease = try XCTUnwrap(leases.first)
    let application = MemoryConsolidationApplication(
      workId: lease.work.id, memoryId: candidate.id, expectedRevision: candidate.revision,
      action: .review, reconciliation: .keepBoth, targets: [], memoryText: nil,
      rationale: "Needs more evidence")

    let first = try await MemoryStorage.shared.completeConsolidation(
      applications: [application], receiptId: "receipt-review",
      ownerGeneration: ownerGeneration, now: now)
    let replay = try await MemoryStorage.shared.completeConsolidation(
      applications: [application], receiptId: "receipt-review",
      ownerGeneration: ownerGeneration, now: now)

    XCTAssertEqual(first, replay)
    XCTAssertEqual(first.first?.revision, 2)
    XCTAssertEqual(first.first?.expiresAt, now.addingTimeInterval(MemoryStorage.shortTermLifetime))
    let beforeExpiry = try await MemoryStorage.shared.enqueueDueLifecycleWork(
      now: now.addingTimeInterval(MemoryStorage.shortTermLifetime - 1),
      ownerGeneration: ownerGeneration)
    let atExpiry = try await MemoryStorage.shared.enqueueDueLifecycleWork(
      now: now.addingTimeInterval(MemoryStorage.shortTermLifetime),
      ownerGeneration: ownerGeneration)
    let duplicateSchedule = try await MemoryStorage.shared.enqueueDueLifecycleWork(
      now: now.addingTimeInterval(MemoryStorage.shortTermLifetime),
      ownerGeneration: ownerGeneration)
    XCTAssertEqual(beforeExpiry, 0)
    XCTAssertEqual(atExpiry, 1)
    XCTAssertEqual(duplicateSchedule, 0)
  }

  func testPoolReopenRebindsDurablePendingWork() async throws {
    let now = Date(timeIntervalSince1970: 30_000)
    let originalGeneration = await RewindDatabase.shared.poolGeneration()
    let memory = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "A durable pending observation", subject: "primary_user"),
      now: now,
      ownerGeneration: originalGeneration)
    let reopenedGeneration = originalGeneration + 7

    try await MemoryStorage.shared.recoverLifecycleWork(
      ownerGeneration: reopenedGeneration, now: now)
    let rebound = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now, ownerGeneration: reopenedGeneration)

    XCTAssertEqual(rebound.map { $0.memory?.id }, [memory.id])
    XCTAssertEqual(rebound.first?.work.ownerGeneration, reopenedGeneration)
  }

  func testRunnerBatchEmbedsCurrentRevisionsBeforeSearch() async throws {
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture.establish(authOwnerID: "memory-lifecycle-embedding-owner")
    defer { Task { await ownerFixture.restore() } }
    let memory = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Prefers unusual single-origin coffee", layer: .longTerm))
    let embedder = MemoryEmbeddingStub()
    let runner = LocalMemoryLifecycleRunner(
      storage: .shared,
      conversations: .shared,
      computer: MemoryComputeStub(),
      embedder: embedder,
      requiresOwnerAuthorization: true)
    let authorizationSnapshot = try XCTUnwrap(
      RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    let report = await runner.runOnce()
    let matches = try await MemoryStorage.shared.semanticSearch(
      queryVector: [1, 0],
      authorizationSnapshot: authorizationSnapshot)
    let batches = await embedder.batches

    XCTAssertEqual(report.embedded, 1)
    XCTAssertEqual(matches.map(\.id), [memory.id])
    XCTAssertEqual(batches, [[memory.content]])
  }

  func testConsolidationRejectsTwoDecisionsSupersedingOneRevision() async throws {
    let now = Date(timeIntervalSince1970: 40_000)
    let generation = await RewindDatabase.shared.poolGeneration()
    let target = try await MemoryStorage.shared.acceptAssertion(
      MemoryAssertion(content: "Lives in New York", layer: .longTerm),
      now: now, ownerGeneration: generation)
    var candidates: [MemoryItem] = []
    for content in ["Moved to Tallinn", "Now lives in Tallinn"] {
      candidates.append(
        try await MemoryStorage.shared.acceptAssertion(
          MemoryAssertion(content: content, subject: "primary_user"),
          now: now, ownerGeneration: generation))
    }
    let leases = try await MemoryStorage.shared.leaseDueWork(
      kind: .consolidate, now: now, ownerGeneration: generation)
    let byID = Dictionary(
      lastWriteWins: leases.compactMap { lease in
        lease.memory.map { ($0.id, lease) }
      })
    let applications = try candidates.map { candidate -> MemoryConsolidationApplication in
      let lease = try XCTUnwrap(byID[candidate.id])
      return MemoryConsolidationApplication(
        workId: lease.work.id,
        memoryId: candidate.id,
        expectedRevision: candidate.revision,
        action: .promote,
        reconciliation: .replace,
        targets: [MemoryConsolidationTarget(memoryId: target.id, expectedRevision: target.revision)],
        memoryText: candidate.content,
        rationale: "Conflicting replacement")
    }

    do {
      _ = try await MemoryStorage.shared.completeConsolidation(
        applications: applications, receiptId: "duplicate-target",
        ownerGeneration: generation, now: now)
      XCTFail("two decisions must not supersede the same target revision")
    } catch MemoryStorageError.invalidTransition {
      // Whole-batch validation rejects before the first target mutation.
    }
    let persistedTarget = try await MemoryStorage.shared.memory(id: target.id)
    XCTAssertEqual(persistedTarget?.revision, target.revision)
    XCTAssertEqual(persistedTarget?.layer, .longTerm)
  }
}
