import Accelerate
import Foundation

/// Actor-based service for embeddings using Gemini (3072-dim)
actor EmbeddingService {
  static let shared = EmbeddingService()

  /// Gemini embedding-001 outputs 3072 dimensions by default
  static let embeddingDimension = 3072
  static var modelName: String { ModelQoS.Gemini.embedding }

  /// Backend proxy base URL (from the canonical backend resolver).
  private static var proxyBaseURL: String {
    DesktopBackendEnvironment.backendBaseURL()
  }

  /// Get Firebase auth header for proxy requests
  private func authHeader() async throws -> String {
    let authService = await MainActor.run { AuthService.shared }
    return try await authService.getAuthHeader()
  }

  private func authorizedAuthHeader(
    _ snapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> String {
    if !RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) {
      throw LocalMutationAuthorizationError.revoked
    }
    let header = try await authHeader()
    if !RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) {
      throw LocalMutationAuthorizationError.revoked
    }
    return header
  }

  private init() {}

  // MARK: - Embedding API

  /// Generate embedding for a single text using Gemini (3072-dim)
  /// - Parameters:
  ///   - text: Text to embed
  ///   - taskType: Optional Gemini task type (e.g. "RETRIEVAL_DOCUMENT", "RETRIEVAL_QUERY")
  func embed(
    text: String,
    taskType: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [Float] {
    guard !Self.proxyBaseURL.isEmpty else {
      throw EmbeddingError.missingAPIKey
    }

    let modelName = Self.modelName
    var requestBody: [String: Any] = [
      "model": "models/\(modelName)",
      "content": [
        "parts": [["text": text]]
      ],
    ]
    if let taskType = taskType {
      requestBody["taskType"] = taskType
    }

    let url = URL(
      string: "\(Self.proxyBaseURL)v1/proxy/gemini/models/\(modelName):embedContent"
    )!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      try await authorizedAuthHeader(authorizationSnapshot),
      forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    if !RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
      throw LocalMutationAuthorizationError.revoked
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }

    // Check HTTP status before parsing — non-JSON error bodies (HTML 401/500)
    // cause "data couldn't be read" errors that mask the real problem.
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
      let body = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
      throw EmbeddingError.serverError(statusCode: httpResponse.statusCode, body: body)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let embedding = json["embedding"] as? [String: Any],
      let values = embedding["values"] as? [Double]
    else {
      throw EmbeddingError.invalidResponse
    }

    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    let floats = values.map { Float($0) }
    return normalize(floats)
  }

  /// Batch embed multiple texts using Gemini (3072-dim, up to 100 per call)
  /// - Parameters:
  ///   - texts: Texts to embed
  ///   - taskType: Optional Gemini task type (e.g. "RETRIEVAL_DOCUMENT", "RETRIEVAL_QUERY")
  func embedBatch(
    texts: [String],
    taskType: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [[Float]] {
    guard !Self.proxyBaseURL.isEmpty else {
      throw EmbeddingError.missingAPIKey
    }

    let modelName = Self.modelName
    let requests = texts.map { text in
      var req: [String: Any] = [
        "model": "models/\(modelName)",
        "content": [
          "parts": [["text": text]]
        ],
      ]
      if let taskType = taskType {
        req["taskType"] = taskType
      }
      return req
    }

    let requestBody: [String: Any] = ["requests": requests]

    let url = URL(
      string: "\(Self.proxyBaseURL)v1/proxy/gemini/models/\(modelName):batchEmbedContents"
    )!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      try await authorizedAuthHeader(authorizationSnapshot),
      forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 60
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    if !RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) {
      throw LocalMutationAuthorizationError.revoked
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }

    // Check HTTP status before parsing — non-JSON error bodies (HTML 401/500)
    // cause "data couldn't be read" errors that mask the real problem.
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
      let body = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
      throw EmbeddingError.serverError(statusCode: httpResponse.statusCode, body: body)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let embeddings = json["embeddings"] as? [[String: Any]]
    else {
      throw EmbeddingError.invalidResponse
    }

    // Gemini returns embeddings 1:1 in request order. Callers zip results back to
    // their input texts by position (backfill, OCR indexing), so a dropped or
    // extra entry would silently persist an embedding onto the WRONG task. Fail
    // the batch on any count mismatch or malformed entry instead of compactMap-ing
    // (which would shift every subsequent embedding by one).
    guard embeddings.count == texts.count else {
      throw EmbeddingError.invalidResponse
    }
    let normalized = try embeddings.map { embedding in
      guard let values = embedding["values"] as? [Double] else {
        throw EmbeddingError.invalidResponse
      }
      return normalize(values.map { Float($0) })
    }
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
    return normalized
  }

  // MARK: - Shared embedding codecs

  private func normalize(_ vector: [Float]) -> [Float] {
    var norm: Float = 0
    vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
    norm = sqrt(norm)
    guard norm > 0 else { return vector }
    var result = [Float](repeating: 0, count: vector.count)
    var divisor = norm
    vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
    return result
  }

  /// Convert [Float] to Data (for SQLite BLOB storage)
  func floatsToData(_ floats: [Float]) -> Data {
    return floats.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
  }

  /// Convert Data (BLOB) back to [Float] (expects 3072-dim Gemini embeddings)
  func dataToFloats(_ data: Data) -> [Float]? {
    let floatSize = MemoryLayout<Float>.size
    let floatCount = data.count / floatSize

    guard floatCount == Self.embeddingDimension else {
      return nil
    }

    return data.withUnsafeBytes { raw in
      Array(raw.bindMemory(to: Float.self))
    }
  }

  // MARK: - Errors

  enum EmbeddingError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case serverError(statusCode: Int, body: String)

    var reasonCode: String {
      switch self {
      case .missingAPIKey:
        return "missing_api_key"
      case .invalidResponse:
        return "malformed_response"
      case .serverError(let statusCode, let body):
        let lower = body.lowercased()
        if statusCode == 402 || lower.contains("trial_expired") || lower.contains("trial expired")
          || lower.contains("payment required") || lower.contains("usage limit")
        {
          return "product_gate"
        }
        if statusCode == 429 || lower.contains("rate limit") || lower.contains("resource exhausted") {
          return "rate_limited"
        }
        if (500...599).contains(statusCode) || lower.contains("temporarily unavailable")
          || lower.contains("service unavailable") || lower.contains("overloaded")
        {
          return "temporarily_unavailable"
        }
        return "http_\(statusCode)"
      }
    }

    var isExpectedProductState: Bool { reasonCode == "product_gate" }
    var isTransient: Bool { reasonCode == "rate_limited" || reasonCode == "temporarily_unavailable" }
    var isNonActionableForSentry: Bool { isExpectedProductState || isTransient }

    var errorDescription: String? {
      switch self {
      case .missingAPIKey:
        return "AI features are not configured. Please update the app."
      case .invalidResponse:
        return "Embedding API returned an unexpected response."
      case .serverError:
        switch reasonCode {
        case "product_gate":
          return "Embedding API unavailable: an active plan is required."
        case "rate_limited":
          return "Embedding API rate limited. Will retry later."
        case "temporarily_unavailable":
          return "Embedding API temporarily unavailable. Will retry later."
        default:
          return "Embedding API error (\(reasonCode))."
        }
      }
    }

    /// Expected product-gating / backend-limit states (paywall/trial-expired, rate-limited).
    /// These are not actionable bugs: they should be logged locally rather than reported to
    /// Sentry as high-priority errors, and must not drive tight retry loops.
    var isExpectedBackendState: Bool {
      if case .serverError(let statusCode, _) = self {
        return statusCode == 402 || statusCode == 429
      }
      return false
    }
  }
}
