import Foundation

private struct ConversationBootstrapRequest: Encodable {
  let conversationID: String
  enum CodingKeys: String, CodingKey { case conversationID = "conversation_id" }
}

private struct ConversationBootstrapResponse: Decodable {
  let conversationID: String
  let prompt: ConversationPromptReceipt
  enum CodingKeys: String, CodingKey {
    case conversationID = "conversation_id"
    case prompt
  }
}

private struct ConversationLiveRequest: Encodable {
  let conversationID: String
  let promptReference: ConversationPromptReference
  enum CodingKeys: String, CodingKey {
    case conversationID = "conversation_id"
    case promptReference = "prompt_ref"
  }
}

private struct ConversationTextDelta: Decodable { let text: String }
private struct ConversationStreamFailure: Decodable {
  let code: String
  let retryable: Bool
}

extension APIClient {
  func bootstrapConversation(
    conversationID: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> ConversationPromptReceipt {
    let response: ConversationBootstrapResponse = try await post(
      "v1/conversation/session",
      body: ConversationBootstrapRequest(conversationID: conversationID),
      authorizationSnapshot: authorizationSnapshot)
    guard response.conversationID == conversationID else { throw APIError.invalidResponse }
    try response.prompt.validate()
    return response.prompt
  }

  func mintConversationLiveSession(
    conversationID: String,
    prompt: ConversationPromptReceipt,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> RealtimeSessionSetup {
    try prompt.validate()
    let policy = RequestAuthPolicy.ownerBound(authorizationSnapshot)
    try validateExpectedOwner(policy)
    guard let url = URL(string: baseURL + "v2/realtime/session") else { throw APIError.invalidResponse }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(expectedAuthOwnerId: authorizationSnapshot.ownerID)
    try validateExpectedOwner(policy)
    request.httpBody = try transport.encoder.encode(
      ConversationLiveRequest(conversationID: conversationID, promptReference: prompt.reference))
    let setup = try await performRealtimeMintRequest(
      request, provider: .gemini, authPolicy: policy, retriedAuth: false)
    guard let resolved = setup.prompt,
      resolved.text == prompt.text, resolved.name == prompt.name,
      resolved.version == prompt.version, resolved.source == prompt.source
    else { throw ConversationAPIError.invalidPromptReceipt }
    return setup
  }

  func respondToConversation(
    request body: ConversationResponseRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    onTextDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws -> ConversationResponseCompletion {
    let policy = RequestAuthPolicy.ownerBound(authorizationSnapshot)
    try validateExpectedOwner(policy)
    guard let url = URL(string: baseURL + "v1/conversation/respond") else { throw APIError.invalidResponse }
    let data = try transport.encoder.encode(body)
    guard data.count <= 4_000_000 else { throw ConversationAPIError.requestTooLarge }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.allHTTPHeaderFields = try await buildHeaders(expectedAuthOwnerId: authorizationSnapshot.ownerID)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.httpBody = data
    try validateExpectedOwner(policy)
    try Task.checkCancellation()
    return try await streamConversation(
      request: request, promptReference: body.promptReference, policy: policy,
      retriedAuth: false, onTextDelta: onTextDelta)
  }

  private func streamConversation(
    request: URLRequest,
    promptReference: ConversationPromptReference,
    policy: RequestAuthPolicy,
    retriedAuth: Bool,
    onTextDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws -> ConversationResponseCompletion {
    try validateExpectedOwner(policy)
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    try validateExpectedOwner(policy)
    guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    if response.statusCode == 401, !retriedAuth,
      let retry = try await authorizedRetryRequest(from: request, retriedAuth: false, authPolicy: policy)
    {
      return try await streamConversation(
        request: retry, promptReference: promptReference, policy: policy,
        retriedAuth: true, onTextDelta: onTextDelta)
    }
    guard (200...299).contains(response.statusCode) else {
      throw APIError.httpError(statusCode: response.statusCode)
    }
    var event = ""
    var receivedBytes = 0
    // The owned endpoint emits one JSON data line per event, including escaped
    // newlines inside text. Never retry after a delta has reached the caller.
    for try await line in bytes.lines {
      try Task.checkCancellation()
      try validateExpectedOwner(policy)
      guard line.utf8.count <= 262_144 else { throw ConversationAPIError.invalidStream }
      if line.hasPrefix("event:") {
        event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        continue
      }
      guard line.hasPrefix("data:") else { continue }
      let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
      switch event {
      case "text_delta":
        let delta = try decoder.decode(ConversationTextDelta.self, from: payload)
        receivedBytes += delta.text.utf8.count
        guard receivedBytes <= 262_144 else { throw ConversationAPIError.invalidStream }
        await onTextDelta(delta.text)
      case "done":
        let result = try decoder.decode(ConversationResponseCompletion.self, from: payload)
        guard result.promptReference == promptReference else { throw ConversationAPIError.invalidPromptReceipt }
        return result
      case "error":
        let failure = try decoder.decode(ConversationStreamFailure.self, from: payload)
        throw ConversationAPIError.provider(code: failure.code, retryable: failure.retryable)
      default:
        throw ConversationAPIError.invalidStream
      }
      event = ""
    }
    throw ConversationAPIError.incompleteResponse
  }
}
