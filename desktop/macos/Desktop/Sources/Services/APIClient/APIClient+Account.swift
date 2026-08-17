import Foundation

// MARK: - Account API

extension APIClient {

  func getUserSubscription() async throws -> UserSubscriptionResponse {
    return try await get("v1/users/me/subscription")
  }

  func getTrialMetadata() async throws -> TrialMetadataResponse {
    return try await get("v1/users/me/trial")
  }

  func getAvailablePlans() async throws -> AvailablePlansResponse {
    return try await get("v1/payments/available-plans")
  }

  func getOverageInfo() async throws -> OverageInfoResponse {
    return try await get("v1/payments/overage-info")
  }

  func createCheckoutSession(priceId: String, promotionCode: String? = nil) async throws
    -> CheckoutSessionResponse
  {
    struct Request: Encodable {
      let priceId: String
      let promotionCode: String?

      enum CodingKeys: String, CodingKey {
        case priceId = "price_id"
        case promotionCode = "promotion_code"
      }
    }

    return try await post(
      "v1/payments/checkout-session",
      body: Request(priceId: priceId, promotionCode: promotionCode))
  }

  func upgradeSubscription(priceId: String, promotionCode: String? = nil) async throws
    -> UpgradeSubscriptionResponse
  {
    struct Request: Encodable {
      let priceId: String
      let promotionCode: String?

      enum CodingKeys: String, CodingKey {
        case priceId = "price_id"
        case promotionCode = "promotion_code"
      }
    }

    return try await post(
      "v1/payments/upgrade-subscription",
      body: Request(priceId: priceId, promotionCode: promotionCode))
  }

  func createCustomerPortalSession() async throws -> CustomerPortalResponse {
    return try await post("v1/payments/customer-portal")
  }

  // MARK: - LLM Usage

  func recordLlmUsage(
    inputTokens: Int,
    outputTokens: Int,
    cacheReadTokens: Int,
    cacheWriteTokens: Int,
    totalTokens: Int,
    costUsd: Double,
    account: String = "omi"
  ) async {
    struct Req: Encodable {
      let input_tokens: Int
      let output_tokens: Int
      let cache_read_tokens: Int
      let cache_write_tokens: Int
      let total_tokens: Int
      let cost_usd: Double
      let account: String
    }
    struct Res: Decodable { let status: String }
    do {
      let _: Res = try await post(
        "v1/users/me/llm-usage",
        body: Req(
          input_tokens: inputTokens,
          output_tokens: outputTokens,
          cache_read_tokens: cacheReadTokens,
          cache_write_tokens: cacheWriteTokens,
          total_tokens: totalTokens,
          cost_usd: costUsd,
          account: account
        ))
    } catch {
      log("APIClient: LLM usage record failed: \(error.localizedDescription)")
    }
  }

  func fetchTotalOmiAICost() async -> Double? {
    struct Res: Decodable { let total_cost_usd: Double }
    do {
      log("APIClient: Fetching total Omi AI cost from backend")
      let res: Res = try await get("v1/users/me/llm-usage/total")
      log(
        "APIClient: Total Omi AI cost from backend: $\(String(format: "%.4f", res.total_cost_usd))")
      return res.total_cost_usd
    } catch {
      log("APIClient: LLM total cost fetch failed: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - Chat Usage Quota

  /// Current-month chat usage + the plan's cap. Backed by Python backend
  /// endpoint `/v1/users/me/usage-quota` which reads `users/{uid}/llm_usage/*`.
  struct ChatUsageQuota: Decodable {
    let plan: String  // display name: "Free" | "Plus" | "Pro"
    let planType: String  // internal id: "basic" | "unlimited" | "architect"
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
    let geminiApiKey: String?
    let firebaseApiKey: String?
    let googleCalendarApiKey: String?

    enum CodingKeys: String, CodingKey {
      case deepgramApiKey = "deepgram_api_key"
      case geminiApiKey = "gemini_api_key"
      case firebaseApiKey = "firebase_api_key"
      case googleCalendarApiKey = "google_calendar_api_key"
    }
  }

  func fetchApiKeys() async throws -> ApiKeysResponse {
    return try await get("v1/config/api-keys", customBaseURL: rustBackendURL)
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
    let base = rustBackendURL
    guard !base.isEmpty, let url = URL(string: base + "v1/tts/synthesize") else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.allHTTPHeaderFields = try await buildHeaders()
    request.httpBody = try JSONEncoder().encode(body)

    // This desktop-backend route can surface upstream OpenAI credential failures
    // as HTTP 401. Refresh the Firebase header once in case it is stale,
    // but never let a voice-only provider failure invalidate the Omi session.
    // Only remap to providerAuth when the body is OpenAI-shaped — a bare/Firebase
    // 401 after refresh is a real login failure and must require re-auth.
    let (data, httpResponse) = try await performAuthenticatedData(
      for: request,
      authPolicy: .providerCredentialBoundary
    )

    if httpResponse.statusCode == 401 {
      let detail = (try? JSONDecoder().decode(APIErrorPayload.self, from: data))?.preferredMessage
      if detail?.hasPrefix("OpenAI TTS request failed:") == true {
        throw CredentialHealthError.providerAuth(
          provider: .openai,
          mode: .managed,
          message: "OpenAI authentication failed. Voice responses are using fallback."
        )
      }
      await invalidateSessionAfterUnauthorized(
        endpoint: endpointLabel(for: request),
        signOutOn401: true
      )
      throw APIError.unauthorized
    }

    if httpResponse.statusCode == 429 {
      let detail = (try? JSONDecoder().decode(APIErrorPayload.self, from: data))?.preferredMessage
      if detail?.hasPrefix("OpenAI TTS request failed:") == true {
        throw CredentialHealthError.providerQuota(
          provider: .openai,
          message: "OpenAI voice quota was exceeded. Voice responses are using fallback."
        )
      }
      throw APIError.httpError(statusCode: httpResponse.statusCode, detail: detail)
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw APIError.httpError(statusCode: httpResponse.statusCode)
    }

    return data
  }

}
