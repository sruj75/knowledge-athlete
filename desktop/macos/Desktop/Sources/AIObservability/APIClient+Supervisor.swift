import Foundation

extension APIClient {
  func evaluateSupervisor(
    request: SupervisorEvaluationRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> SupervisorEvaluationResponse {
    let policy = RequestAuthPolicy.ownerBound(authorizationSnapshot)
    try validateExpectedOwner(policy)
    let body = try transport.encoder.encode(request)
    guard body.count <= 4_000_000 else { throw SupervisorRequestError.payloadTooLarge }
    guard let url = URL(string: baseURL + "v1/supervisor/evaluate") else { throw APIError.invalidResponse }
    var wire = URLRequest(url: url)
    wire.httpMethod = "POST"
    wire.timeoutInterval = 30
    wire.allHTTPHeaderFields = try await buildHeaders(expectedAuthOwnerId: authorizationSnapshot.ownerID)
    try validateExpectedOwner(policy)
    wire.httpBody = body
    let (data, response) = try await performAuthenticatedData(for: wire, authPolicy: policy)
    if response.statusCode == 429,
      let quota = try? decoder.decode(SupervisorQuotaResponse.self, from: data),
      ["daily_quota", "burst_quota"].contains(quota.detail.reason),
      (1...86_400).contains(quota.detail.retryAfterSeconds)
    {
      throw SupervisorRequestError.rateLimited(
        reason: quota.detail.reason, retryAfterSeconds: quota.detail.retryAfterSeconds)
    }
    guard (200...299).contains(response.statusCode) else {
      throw APIError.httpError(statusCode: response.statusCode)
    }
    return try decoder.decode(SupervisorEvaluationResponse.self, from: data)
  }

  /// Best-effort telemetry never refreshes authentication, invalidates login or
  /// replays a content-bearing body. Recheck consent after token lookup and
  /// before encoding the actual wire payload.
  func submitAIObservation(
    _ observation: AIEvaluationObservation,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    permitsContent: @escaping @MainActor @Sendable () -> Bool
  ) async throws {
    let policy = RequestAuthPolicy.ownerBound(authorizationSnapshot)
    try validateExpectedOwner(policy)
    guard let url = URL(string: baseURL + "v1/ai/observations") else { throw APIError.invalidResponse }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.allHTTPHeaderFields = try await buildHeaders(expectedAuthOwnerId: authorizationSnapshot.ownerID)
    try validateExpectedOwner(policy)
    try Task.checkCancellation()
    let sharing = await permitsContent()
    request.httpBody = try observation.encoded(sharing: sharing)
    try Task.checkCancellation()
    let (_, response) = try await session.data(for: request)
    try validateExpectedOwner(policy)
    guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    guard (200...299).contains(response.statusCode) else {
      throw APIError.httpError(statusCode: response.statusCode)
    }
  }
}

private struct SupervisorQuotaResponse: Decodable {
  struct Detail: Decodable {
    let reason: String
    let retryAfterSeconds: Int
    enum CodingKeys: String, CodingKey {
      case reason
      case retryAfterSeconds = "retry_after_seconds"
    }
  }
  let detail: Detail
}
