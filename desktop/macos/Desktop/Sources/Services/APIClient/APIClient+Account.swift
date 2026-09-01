import Foundation

// MARK: - Account API

extension APIClient {

  func getUserSubscription() async throws -> UserSubscriptionResponse {
    return try await get("v1/users/me/subscription")
  }

  func getTrialMetadata() async throws -> TrialMetadataResponse {
    return try await get("v1/users/me/trial")
  }

  func createCheckoutSession(offerId: String) async throws
    -> CheckoutSessionResponse
  {
    struct Request: Encodable {
      let offerId: String

      enum CodingKeys: String, CodingKey {
        case offerId = "offer_id"
      }
    }

    return try await post(
      "v1/payments/checkout-session",
      body: Request(offerId: offerId))
  }

  func createCustomerPortalSession() async throws -> CustomerPortalResponse {
    return try await post("v1/payments/customer-portal")
  }

  // MARK: - Chat Usage Quota

  /// Current-month chat usage + the plan's cap. Backed by Python backend
  /// endpoint `/v1/users/me/usage-quota` which reads `users/{uid}/llm_usage/*`.
  struct ChatUsageQuota: Decodable {
    let plan: String  // server-owned display name
    let planType: String  // normalized id: "free" | "bounded" | "unlimited"
    let unit: String  // "questions" | "cost_usd"
    let used: Double
    let limit: Double?  // nil means unlimited
    let percent: Double
    let allowed: Bool
    let resetAt: Int?  // unix seconds — start of next UTC month

    enum CodingKeys: String, CodingKey {
      case plan
      case planType = "plan_type"
      case unit
      case used
      case limit
      case percent
      case allowed
      case resetAt = "reset_at"
    }
  }

  func fetchChatUsageQuota(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async -> ChatUsageQuota? {
    do {
      let res: ChatUsageQuota = try await get(
        "v1/users/me/usage-quota",
        authorizationSnapshot: authorizationSnapshot)
      log(
        "APIClient: Quota plan=\(res.plan) unit=\(res.unit) used=\(res.used) limit=\(res.limit ?? -1) allowed=\(res.allowed)"
      )
      return res
    } catch {
      log("APIClient: Chat quota fetch failed: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - API Keys

  struct ApiKeysResponse: Decodable {
    let deepgramApiKey: String?
    let firebaseApiKey: String?
    let googleCalendarApiKey: String?

    enum CodingKeys: String, CodingKey {
      case deepgramApiKey = "deepgram_api_key"
      case firebaseApiKey = "firebase_api_key"
      case googleCalendarApiKey = "google_calendar_api_key"
    }
  }

  func fetchApiKeys() async throws -> ApiKeysResponse {
    return try await get("v1/config/api-keys")
  }

  struct TtsSynthesizeRequest: Encodable {
    let text: String
    let voiceId: String
    let instructions: String?

    enum CodingKeys: String, CodingKey {
      case text
      case voiceId = "voice_id"
      case instructions
    }
  }

  func synthesizeSpeech(request body: TtsSynthesizeRequest) async throws -> Data {
    let base = baseURL
    guard !base.isEmpty, let url = URL(string: base + "v1/tts/synthesize") else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.allHTTPHeaderFields = try await buildHeaders()
    request.httpBody = try JSONEncoder().encode(body)

    // This canonical backend route identifies managed upstream failures with the
    // same typed provider boundary as realtime minting. The shared transport
    // inspects that shape before a Firebase refresh so provider credentials can
    // never invalidate the account session.
    let (data, httpResponse) = try await performAuthenticatedData(
      for: request,
      authPolicy: .providerCredentialBoundary
    )

    let payload = OmiHTTPTransport.extractErrorPayload(from: data)
    if payload?.managedProviderFailureReason == .authFailed,
      payload?.provider == "openai",
      payload?.upstreamStatusCode == httpResponse.statusCode
    {
      throw CredentialHealthError.providerAuth(
        provider: .openai,
        mode: .managed,
        message: "OpenAI authentication failed. Voice responses are using fallback."
      )
    }

    if httpResponse.statusCode == 401 {
      await invalidateSessionAfterUnauthorized(
        endpoint: endpointLabel(for: request),
        signOutOn401: true
      )
      throw APIError.unauthorized
    }

    if payload?.managedProviderFailureReason == .quotaExceeded,
      payload?.provider == "openai",
      payload?.upstreamStatusCode == httpResponse.statusCode
    {
      throw CredentialHealthError.providerQuota(
        provider: .openai,
        message: "OpenAI voice quota was exceeded. Voice responses are using fallback."
      )
    }
    if httpResponse.statusCode == 429 {
      throw APIError.httpError(statusCode: httpResponse.statusCode, detail: payload?.preferredMessage)
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw APIError.httpError(statusCode: httpResponse.statusCode)
    }

    return data
  }

}
