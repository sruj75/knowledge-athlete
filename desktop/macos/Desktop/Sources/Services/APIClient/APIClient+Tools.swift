import Foundation

extension APIClient {
  // MARK: - Platform Tools (backend RAG)

  struct ToolResponse: Decodable {
    let toolName: String
    let resultText: String
    let isError: Bool

    enum CodingKeys: String, CodingKey {
      case toolName = "tool_name"
      case resultText = "result_text"
      case isError = "is_error"
    }
  }

  struct SearchRequest: Encodable {
    let query: String
    let startDate: String?
    let endDate: String?
    let limit: Int
    let includeTranscript: Bool?

    enum CodingKeys: String, CodingKey {
      case query
      case startDate = "start_date"
      case endDate = "end_date"
      case limit
      case includeTranscript = "include_transcript"
    }
  }

  struct MemorySearchRequest: Encodable {
    let query: String
    let limit: Int
  }

  /// Percent-encode a date string for use in query parameters.
  /// `.urlQueryAllowed` does not encode `+`, but servers decode `+` as space in query strings.
  /// This encodes `+` as `%2B` so timezone offsets like `+07:00` survive round-trip.
  private func encodeQueryDate(_ date: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+")
    return date.addingPercentEncoding(withAllowedCharacters: allowed) ?? date
  }

  func toolGetConversations(
    startDate: String? = nil,
    endDate: String? = nil,
    limit: Int = 20,
    offset: Int = 0,
    includeTranscript: Bool = true,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> ToolResponse {
    var params =
      "v1/tools/conversations?limit=\(limit)&offset=\(offset)&include_transcript=\(includeTranscript)"
    if let sd = startDate { params += "&start_date=\(encodeQueryDate(sd))" }
    if let ed = endDate { params += "&end_date=\(encodeQueryDate(ed))" }
    return try await get(
      params,
      customBaseURL: nil,
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
  }

  func toolSearchConversations(
    query: String,
    startDate: String? = nil,
    endDate: String? = nil,
    limit: Int = 5,
    includeTranscript: Bool = true,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> ToolResponse {
    let body = SearchRequest(
      query: query, startDate: startDate, endDate: endDate, limit: limit,
      includeTranscript: includeTranscript)
    return try await post(
      "v1/tools/conversations/search",
      body: body,
      customBaseURL: nil,
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
  }

  func toolGetMemories(
    limit: Int = 50,
    offset: Int = 0,
    startDate: String? = nil,
    endDate: String? = nil,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> ToolResponse {
    var params = "v1/tools/memories?limit=\(limit)&offset=\(offset)"
    if let sd = startDate { params += "&start_date=\(encodeQueryDate(sd))" }
    if let ed = endDate { params += "&end_date=\(encodeQueryDate(ed))" }
    return try await get(
      params,
      customBaseURL: nil,
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
  }

  func toolSearchMemories(
    query: String,
    limit: Int = 5,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> ToolResponse {
    let body = MemorySearchRequest(query: query, limit: limit)
    return try await post(
      "v1/tools/memories/search",
      body: body,
      customBaseURL: nil,
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
  }

}
