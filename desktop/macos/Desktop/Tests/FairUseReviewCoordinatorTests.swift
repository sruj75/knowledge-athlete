import Foundation
import XCTest

@testable import Omi_Computer

private actor FairUseEvidenceReaderStub: FairUseEvidenceReading {
  let evidence: [FairUseConversationEvidence]
  let onRead: @Sendable () -> Void
  private(set) var readDates: [Date] = []

  init(evidence: [FairUseConversationEvidence], onRead: @escaping @Sendable () -> Void = {}) {
    self.evidence = evidence
    self.onRead = onRead
  }

  func fairUseEvidence(
    now: Date,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [FairUseConversationEvidence] {
    readDates.append(now)
    onRead()
    return evidence
  }
}

private actor FairUseSubmitterStub: FairUseReviewSubmitting {
  private(set) var submissions: [(String, [FairUseConversationEvidence])] = []

  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt {
    submissions.append((reviewId, conversations))
    return FairUseClassificationReceipt(
      reviewId: reviewId, accepted: true, idempotent: false, action: "none", stage: "none", caseRef: "")
  }
}

private actor FlakyFairUseSubmitterStub: FairUseReviewSubmitting {
  private(set) var attempts = 0

  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt {
    attempts += 1
    if attempts == 1 { throw URLError(.timedOut) }
    return FairUseClassificationReceipt(
      reviewId: reviewId, accepted: true, idempotent: false, action: "none", stage: "none", caseRef: "")
  }
}

private actor PermanentlyFailingFairUseSubmitterStub: FairUseReviewSubmitting {
  private(set) var attempts = 0

  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt {
    attempts += 1
    throw APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad")))
  }
}

private final class FairUseAuthorizationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var current = true

  func revoke() { lock.withLock { current = false } }
  func isCurrent() -> Bool { lock.withLock { current } }
}

private final class FairUseFailureRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []

  func append(_ value: String) { lock.withLock { values.append(value) } }
  func isEmpty() -> Bool { lock.withLock { values.isEmpty } }
}

final class FairUseReviewCoordinatorTests: XCTestCase {
  @MainActor
  func testOneCapturedAuthorizationCarriesBoundedEvidenceIntoOneSubmission() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "fair-use-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let evidence = FairUseConversationEvidence(
      conversationId: "22222222-2222-4222-8222-222222222222",
      title: "Planning", overview: "Local evidence", category: "work", durationMinutes: 12,
      source: "desktop", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    let reader = FairUseEvidenceReaderStub(evidence: [evidence])
    let submitter = FairUseSubmitterStub()
    let coordinator = FairUseReviewCoordinator(
      storage: reader, submitter: submitter,
      captureAuthorization: { snapshot },
      now: { Date(timeIntervalSince1970: 1_800_000_000) })
    let request = makeRequest()

    await coordinator.handle(request)
    await coordinator.handle(request)

    let submissions = await submitter.submissions
    XCTAssertEqual(submissions.count, 1)
    XCTAssertEqual(submissions[0].0, request.reviewId)
    XCTAssertEqual(submissions[0].1, [evidence])
    let readDates = await reader.readDates
    XCTAssertEqual(readDates, [request.requestedAt])
  }

  @MainActor
  func testRevocationAfterLocalReadPreventsSubmissionAndTelemetry() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "fair-use-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let gate = FairUseAuthorizationGate()
    let reader = FairUseEvidenceReaderStub(evidence: []) { gate.revoke() }
    let submitter = FairUseSubmitterStub()
    let failures = FairUseFailureRecorder()
    let coordinator = FairUseReviewCoordinator(
      storage: reader, submitter: submitter,
      captureAuthorization: { snapshot },
      isAuthorizationCurrent: { _ in gate.isCurrent() },
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      recordFailure: { reason in failures.append(reason) })

    await coordinator.handle(makeRequest())

    let submissions = await submitter.submissions
    XCTAssertTrue(submissions.isEmpty)
    XCTAssertTrue(failures.isEmpty())
  }

  @MainActor
  func testTransientSubmissionFailureRetriesWithoutAnotherSocketEvent() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "fair-use-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let reader = FairUseEvidenceReaderStub(evidence: [])
    let submitter = FlakyFairUseSubmitterStub()
    DesktopDiagnosticsManager.shared.resetForTests()
    let coordinator = FairUseReviewCoordinator(
      storage: reader,
      submitter: submitter,
      captureAuthorization: { snapshot },
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      retryDelay: { _ in })

    await coordinator.handle(makeRequest())
    for _ in 0..<100 {
      if await submitter.attempts >= 2 { break }
      await Task.yield()
    }

    let attempts = await submitter.attempts
    XCTAssertEqual(attempts, 2)
    let reads = await reader.readDates
    XCTAssertEqual(reads, [makeRequest().requestedAt, makeRequest().requestedAt])
    let retryableFailure = try XCTUnwrap(
      DesktopDiagnosticsManager.shared.currentSnapshotsForSentry().first {
        $0["event"] as? String == "fallback_triggered"
      })
    XCTAssertEqual(retryableFailure["area"] as? String, "fair_use_review")
    XCTAssertEqual(retryableFailure["reason"] as? String, "submission_failed_retryable")
    DesktopDiagnosticsManager.shared.resetForTests()
  }

  @MainActor
  func testPermanentSubmissionFailureDoesNotEnterRetryLoop() async throws {
    let fixture = RuntimeOwnerAuthorityTestFixture()
    await fixture.establish(authOwnerID: "fair-use-owner-a")
    defer { Task { @MainActor in await fixture.restore() } }
    let snapshot = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let reader = FairUseEvidenceReaderStub(evidence: [])
    let submitter = PermanentlyFailingFairUseSubmitterStub()
    DesktopDiagnosticsManager.shared.resetForTests()
    let coordinator = FairUseReviewCoordinator(
      storage: reader,
      submitter: submitter,
      captureAuthorization: { snapshot },
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      retryDelay: { _ in XCTFail("permanent failures must not schedule retry") })

    await coordinator.handle(makeRequest())
    for _ in 0..<10 { await Task.yield() }

    let attempts = await submitter.attempts
    let reads = await reader.readDates
    XCTAssertEqual(attempts, 1)
    XCTAssertEqual(reads, [makeRequest().requestedAt])
    let permanentFailure = try XCTUnwrap(
      DesktopDiagnosticsManager.shared.currentSnapshotsForSentry().first {
        $0["event"] as? String == "fallback_triggered"
      })
    XCTAssertEqual(permanentFailure["area"] as? String, "fair_use_review")
    XCTAssertEqual(permanentFailure["reason"] as? String, "submission_failed_permanent")
    DesktopDiagnosticsManager.shared.resetForTests()
  }

  private func makeRequest() -> FairUseReviewRequest {
    FairUseReviewRequest(
      reviewId: "11111111-1111-4111-8111-111111111111", trigger: "daily",
      windowSpeechMs: ["daily_ms": 7_200_001, "three_day_ms": 7_200_001, "weekly_ms": 7_200_001],
      thresholdsMs: ["daily_ms": 7_200_000, "three_day_ms": 28_800_000, "weekly_ms": 36_000_000],
      classifierContract: "openai/gpt-5.1:prompt-v2",
      requestedAt: Date(timeIntervalSince1970: 1_800_000_000 - 60),
      expiresAt: Date(timeIntervalSince1970: 1_800_000_000 + 3_600))
  }
}
