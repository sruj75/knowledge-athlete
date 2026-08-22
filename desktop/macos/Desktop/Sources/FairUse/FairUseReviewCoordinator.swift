import Foundation

struct FairUseClassificationReceipt: Codable, Equatable, Sendable {
  let reviewId: String
  let accepted: Bool
  let idempotent: Bool
  let action: String
  let stage: String
  let caseRef: String

  enum CodingKeys: String, CodingKey {
    case reviewId = "review_id"
    case accepted, idempotent, action, stage
    case caseRef = "case_ref"
  }
}

protocol FairUseEvidenceReading: Sendable {
  func fairUseEvidence(
    now: Date,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [FairUseConversationEvidence]
}

protocol FairUseReviewSubmitting: Sendable {
  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt
}

extension TranscriptionStorage: FairUseEvidenceReading {}

extension APIClient: FairUseReviewSubmitting {
  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt {
    guard UUID(uuidString: reviewId) != nil else { throw APIError.invalidResponse }
    let formatter = ISO8601DateFormatter()
    let body = OmiAPI.FairUseClassificationRequest(
      conversations: conversations.prefix(30).map { evidence in
        OmiAPI.FairUseConversationEvidence(
          category: evidence.category,
          conversationId: evidence.conversationId,
          createdAt: formatter.string(from: evidence.createdAt),
          durationMinutes: evidence.durationMinutes,
          overview: evidence.overview,
          source: evidence.source,
          title: evidence.title)
      })
    let response: OmiAPI.FairUseClassificationResponse = try await post(
      "/v1/fair-use/reviews/\(reviewId.lowercased())/classify",
      body: body,
      authorizationSnapshot: authorizationSnapshot)
    return FairUseClassificationReceipt(
      reviewId: response.reviewId,
      accepted: response.accepted,
      idempotent: response.idempotent,
      action: response.action,
      stage: response.stage.rawValue,
      caseRef: response.caseRef ?? "")
  }
}

actor FairUseReviewCoordinator {
  static let shared = FairUseReviewCoordinator(storage: TranscriptionStorage.shared, submitter: APIClient.shared)

  private static let maximumSubmissionAttempts = 5

  private let storage: any FairUseEvidenceReading
  private let submitter: any FairUseReviewSubmitting
  private let captureAuthorization: @Sendable () -> RuntimeOwnerAuthorizationSnapshot?
  private let isAuthorizationCurrent: @Sendable (RuntimeOwnerAuthorizationSnapshot) -> Bool
  private let now: @Sendable () -> Date
  private let recordFailure: @Sendable (String) -> Void
  private let retryDelay: @Sendable (Int) async -> Void
  private let presentReceipt:
    @Sendable (
      FairUseClassificationReceipt, RuntimeOwnerAuthorizationSnapshot
    ) async -> Bool
  private var inFlight = Set<String>()
  private var completed = Set<String>()
  private var retryTasks: [String: Task<Void, Never>] = [:]
  private var submissionAttempts: [String: Int] = [:]

  init(
    storage: any FairUseEvidenceReading,
    submitter: any FairUseReviewSubmitting,
    captureAuthorization: @escaping @Sendable () -> RuntimeOwnerAuthorizationSnapshot? = {
      RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    },
    isAuthorizationCurrent: @escaping @Sendable (RuntimeOwnerAuthorizationSnapshot) -> Bool = {
      RuntimeOwnerIdentity.isAuthorizationCurrent($0)
    },
    now: @escaping @Sendable () -> Date = { Date() },
    retryDelay: @escaping @Sendable (Int) async -> Void = { attempt in
      let seconds = min(30 * (1 << max(0, attempt - 1)), 300)
      try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
    },
    presentReceipt:
      @escaping @Sendable (
        FairUseClassificationReceipt, RuntimeOwnerAuthorizationSnapshot
      ) async -> Bool = { receipt, authorization in
        if receipt.action == "none" { return true }
        return await FairUseWarningNotificationPresenter.shared.present(
          receipt, authorization: authorization)
      },
    recordFailure: @escaping @Sendable (String) -> Void = { reason in
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "fair_use_review", from: "local_evidence", to: "pending_replay",
        reason: reason, outcome: .degraded)
    }
  ) {
    self.storage = storage
    self.submitter = submitter
    self.captureAuthorization = captureAuthorization
    self.isAuthorizationCurrent = isAuthorizationCurrent
    self.now = now
    self.retryDelay = retryDelay
    self.presentReceipt = presentReceipt
    self.recordFailure = recordFailure
  }

  func handle(_ request: FairUseReviewRequest) async {
    let admittedAt = now()
    guard request.classifierContract == "openai/gpt-5.1:prompt-v2", admittedAt < request.expiresAt,
      let authorization = captureAuthorization(),
      !completed.contains(request.reviewId),
      retryTasks[request.reviewId] == nil
    else { return }
    await attempt(request, authorization: authorization)
  }

  private func attempt(
    _ request: FairUseReviewRequest,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async {
    guard now() < request.expiresAt, isAuthorizationCurrent(authorization),
      !completed.contains(request.reviewId),
      inFlight.insert(request.reviewId).inserted
    else { return }
    defer { inFlight.remove(request.reviewId) }

    do {
      let evidence = try await storage.fairUseEvidence(
        now: request.requestedAt, authorizationSnapshot: authorization)
      guard isAuthorizationCurrent(authorization), now() < request.expiresAt else { return }
      let receipt = try await submitter.classifyFairUseReview(
        reviewId: request.reviewId,
        conversations: Array(evidence.prefix(30)),
        authorizationSnapshot: authorization)
      guard isAuthorizationCurrent(authorization) else { return }
      let presented = await presentReceipt(receipt, authorization)
      guard isAuthorizationCurrent(authorization) else { return }
      guard presented else {
        let attempt = submissionAttempts[request.reviewId, default: 0] + 1
        submissionAttempts[request.reviewId] = attempt
        guard attempt < Self.maximumSubmissionAttempts else {
          recordFailure("presentation_failed_permanent")
          submissionAttempts.removeValue(forKey: request.reviewId)
          retryTasks.removeValue(forKey: request.reviewId)?.cancel()
          return
        }
        recordFailure("presentation_failed_retryable")
        scheduleRetry(request, authorization: authorization, attempt: attempt)
        return
      }
      completed.insert(request.reviewId)
      submissionAttempts.removeValue(forKey: request.reviewId)
      retryTasks.removeValue(forKey: request.reviewId)?.cancel()
    } catch LocalMutationAuthorizationError.revoked {
      retryTasks.removeValue(forKey: request.reviewId)?.cancel()
      return
    } catch {
      guard isAuthorizationCurrent(authorization) else { return }
      let attempt = submissionAttempts[request.reviewId, default: 0] + 1
      submissionAttempts[request.reviewId] = attempt
      guard Self.isRetryableSubmissionError(error), attempt < Self.maximumSubmissionAttempts else {
        recordFailure("submission_failed_permanent")
        submissionAttempts.removeValue(forKey: request.reviewId)
        retryTasks.removeValue(forKey: request.reviewId)?.cancel()
        return
      }
      recordFailure("submission_failed_retryable")
      scheduleRetry(request, authorization: authorization, attempt: attempt)
    }
  }

  private static func isRetryableSubmissionError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
      return [
        .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
        .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable,
      ].contains(urlError.code)
    }
    guard case APIError.httpError(let statusCode, _) = error else { return false }
    return statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429
      || (500...599).contains(statusCode)
  }

  private func scheduleRetry(
    _ request: FairUseReviewRequest,
    authorization: RuntimeOwnerAuthorizationSnapshot,
    attempt: Int
  ) {
    guard now() < request.expiresAt, retryTasks[request.reviewId] == nil else { return }
    let delay = retryDelay
    retryTasks[request.reviewId] = Task { [weak self] in
      await delay(attempt)
      guard !Task.isCancelled else { return }
      await self?.runScheduledRetry(request, authorization: authorization)
    }
  }

  private func runScheduledRetry(
    _ request: FairUseReviewRequest,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async {
    retryTasks.removeValue(forKey: request.reviewId)
    await attempt(request, authorization: authorization)
  }
}
