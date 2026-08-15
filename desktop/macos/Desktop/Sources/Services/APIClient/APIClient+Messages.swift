import Foundation

// MARK: - Insight Models
/// Empty body for POST requests with no body
struct EmptyBody: Encodable {}

// MARK: - Chat Messages API (Persistence)

extension APIClient {

  /// Clear chat message history
  func deleteMessages(
    appId: String? = nil,
    expectedOwnerId: String? = nil
  ) async throws -> MessageDeleteResponse {
    var endpoint = "v2/desktop/messages"
    if let appId = appId {
      endpoint += "?app_id=\(appId)"
    }

    guard let url = URL(string: baseURL + endpoint) else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: true,
      expectedAuthOwnerId: expectedOwnerId
    )

    return try await performRequest(
      request,
      authPolicy: expectedOwnerId.map { .ownerBound($0) } ?? .default
    )
  }

  /// Rate a message (thumbs up/down)
  /// - Parameters:
  ///   - messageId: The message ID to rate
  ///   - rating: 1 for thumbs up, -1 for thumbs down, nil to clear rating
  func rateMessage(messageId: String, rating: Int?) async throws {
    struct RateRequest: Encodable {
      let rating: Int?
      let app_version: String?
    }
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let body = RateRequest(rating: rating, app_version: version)
    let _: MessageStatusResponse = try await patch(
      "v2/desktop/messages/\(messageId)/rating", body: body)
  }

  /// Share chat messages and get a shareable URL
  func shareChatMessages(messageIds: [String]) async throws -> ShareChatResponse {
    struct ShareRequest: Encodable {
      let message_ids: [String]
    }
    let body = ShareRequest(message_ids: messageIds)
    return try await post("v2/messages/share", body: body)
  }

  /// Upload one or more files to be attached to a chat message.
  /// Mirrors the Flutter app's `uploadFilesServer` (lib/backend/http/api/messages.dart) —
  /// same `/v2/files` multipart endpoint, same response shape.
  func uploadChatFiles(
    _ uploads: [(data: Data, fileName: String, mimeType: String)],
    appId: String? = nil
  ) async throws -> [ChatFileResponse] {
    var endpoint = "v2/files"
    if let appId = appId, !appId.isEmpty, appId != "no_selected" {
      endpoint += "?app_id=\(appId)"
    }
    guard let url = URL(string: baseURL + endpoint) else {
      throw APIError.invalidResponse
    }

    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(requireAuth: true)
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    let lineBreak = "\r\n"
    for upload in uploads {
      body.append(Data("--\(boundary)\(lineBreak)".utf8))
      body.append(
        Data(
          "Content-Disposition: form-data; name=\"files\"; filename=\"\(upload.fileName)\"\(lineBreak)"
            .utf8))
      body.append(Data("Content-Type: \(upload.mimeType)\(lineBreak)\(lineBreak)".utf8))
      body.append(upload.data)
      body.append(Data(lineBreak.utf8))
    }
    body.append(Data("--\(boundary)--\(lineBreak)".utf8))
    request.httpBody = body

    return try await performRequest(request)
  }

}
/// Response shape for `POST /v2/files` — mirrors backend `FileChat` model.
struct ChatFileResponse: Codable {
  let id: String
  let name: String?
  let mimeType: String?
  let thumbnail: String?
  let thumbName: String?
  let openaiFileId: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case thumbnail
    case mimeType = "mime_type"
    case thumbName = "thumb_name"
    case openaiFileId = "openai_file_id"
  }
}

/// Response from rating a message
struct MessageStatusResponse: Codable {
  let status: String
}

/// Response from sharing chat messages
struct ShareChatResponse: Codable {
  let url: String
  let token: String
}
