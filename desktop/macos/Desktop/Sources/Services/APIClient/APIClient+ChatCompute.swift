import Foundation

// MARK: - Transient Chat Compute

extension APIClient {
  /// Generate a greeting from bounded Mac-owned context without server identity.
  func getInitialMessage(
    profileText: String,
    memories: [String],
    expectedOwnerId: String? = nil
  ) async throws
    -> InitialMessageResponse
  {
    let body = OmiAPI.InitialMessageRequest(
      memories: memories.prefix(20).map { String($0.prefix(1_000)) },
      profileText: String(profileText.prefix(8_000))
    )
    guard let expectedOwnerId else {
      let response: OmiAPI.InitialMessageResponse = try await post(
        "v2/chat/initial-message", body: body)
      return InitialMessageResponse(message: response.message)
    }
    guard let url = URL(string: baseURL + "v2/chat/initial-message") else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: true,
      expectedAuthOwnerId: expectedOwnerId
    )
    request.httpBody = try transport.encoder.encode(body)
    let response: OmiAPI.InitialMessageResponse = try await performRequest(
      request, authPolicy: .ownerBound(expectedOwnerId))
    return InitialMessageResponse(message: response.message)
  }

  /// Generate a title from only the first real local user/assistant pair.
  func generateSessionTitle(
    userText: String,
    assistantText: String,
    expectedOwnerId: String? = nil
  ) async throws -> GenerateTitleResponse {
    let body = OmiAPI.GenerateTitleRequest(
      assistantText: String(assistantText.prefix(12_000)),
      userText: String(userText.prefix(12_000))
    )
    guard let expectedOwnerId else {
      let response: OmiAPI.GenerateTitleResponse = try await post(
        "v2/chat/generate-title", body: body)
      return GenerateTitleResponse(title: response.title)
    }
    guard let url = URL(string: baseURL + "v2/chat/generate-title") else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: true,
      expectedAuthOwnerId: expectedOwnerId
    )
    request.httpBody = try transport.encoder.encode(body)
    let response: OmiAPI.GenerateTitleResponse = try await performRequest(
      request, authPolicy: .ownerBound(expectedOwnerId))
    return GenerateTitleResponse(title: response.title)
  }
}

struct GenerateTitleResponse: Codable, Sendable {
  let title: String
}

struct InitialMessageResponse: Codable, Sendable {
  let message: String
}
