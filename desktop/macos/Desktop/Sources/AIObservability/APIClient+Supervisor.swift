import Foundation

extension APIClient {
  func evaluateSupervisor(
    request: SupervisorEvaluationRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> SupervisorEvaluationResponse {
    try await post(
      "v1/supervisor/evaluate", body: request, authorizationSnapshot: authorizationSnapshot)
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
