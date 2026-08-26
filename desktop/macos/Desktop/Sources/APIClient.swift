import Foundation

actor APIClient {
  static let shared = APIClient()
  // Primary data backend URL — Python backend is the single source of truth for all data CRUD.
  // Beta release channel uses the dev service; stable uses production or explicit local env.
  var baseURL: String {
    DesktopBackendEnvironment.pythonBaseURL()
  }

  // Python desktop backend URL — used only for config/api-keys and local test
  // subscription. All data CRUD,
  // chat AI, and title generation are on Python.
  // Set via OMI_DESKTOP_API_URL env var (in .env).
  var rustBackendURL: String {
    let resolved = DesktopBackendEnvironment.rustBackendURL()
    if !resolved.isEmpty { return resolved }

    NSLog("OMI API: OMI_DESKTOP_API_URL not set — Python desktop backend calls will fail")
    return ""
  }

  let session: URLSession
  var transport: OmiHTTPTransport

  /// When set, `buildHeaders` uses this instead of calling AuthService (test-only).
  var testAuthHeader: String? {
    get { transport.testAuthHeader }
    set { transport.testAuthHeader = newValue }
  }

  init() {
    let transport = OmiHTTPTransport()
    self.transport = transport
    self.session = transport.session
  }

  /// Test-only initializer that accepts a custom URLSession for request interception.
  init(session: URLSession) {
    let transport = OmiHTTPTransport(session: session)
    self.transport = transport
    self.session = session
  }

  var decoder: JSONDecoder { transport.decoder }

  // MARK: - Request Building

  func buildHeaders(
    requireAuth: Bool = true,
    forceRefreshAuth: Bool = false,
    expectedAuthOwnerId: String? = nil
  ) async throws -> [String: String] {
    try await transport.buildHeaders(
      requireAuth: requireAuth,
      forceRefreshAuth: forceRefreshAuth,
      expectedAuthOwnerId: expectedAuthOwnerId
    )
  }

  // MARK: - HTTP Methods

  func get<T: Decodable>(
    _ endpoint: String,
    requireAuth: Bool = true,
    customBaseURL: String? = nil,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> T {
    let authPolicy = try resolvedRequestAuthPolicy(
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
    let authOwnerId = authPolicy.expectedAuthOwnerId
    try validateExpectedOwner(authPolicy)
    let base = customBaseURL ?? baseURL
    guard let url = URL(string: base + endpoint) else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: requireAuth,
      expectedAuthOwnerId: authOwnerId)
    try validateExpectedOwner(authPolicy)

    return try await performRequest(
      request,
      authPolicy: authPolicy)
  }

  func post<T: Decodable, B: Encodable>(
    _ endpoint: String,
    body: B,
    requireAuth: Bool = true,
    customBaseURL: String? = nil,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> T {
    let authPolicy = try resolvedRequestAuthPolicy(
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
    let authOwnerId = authPolicy.expectedAuthOwnerId
    try validateExpectedOwner(authPolicy)
    let base = customBaseURL ?? baseURL
    guard let url = URL(string: base + endpoint) else {
      throw APIError.invalidResponse
    }
    log("APIClient: POST \(url.absoluteString)")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: requireAuth,
      expectedAuthOwnerId: authOwnerId)
    try validateExpectedOwner(authPolicy)
    request.httpBody = try transport.encoder.encode(body)

    return try await performRequest(
      request,
      authPolicy: authPolicy)
  }

  func post<T: Decodable>(
    _ endpoint: String,
    requireAuth: Bool = true,
    customBaseURL: String? = nil,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> T {
    let authPolicy = try resolvedRequestAuthPolicy(
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
    let authOwnerId = authPolicy.expectedAuthOwnerId
    try validateExpectedOwner(authPolicy)
    let base = customBaseURL ?? baseURL
    guard let url = URL(string: base + endpoint) else {
      throw APIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: requireAuth,
      expectedAuthOwnerId: authOwnerId)
    try validateExpectedOwner(authPolicy)

    return try await performRequest(
      request,
      authPolicy: authPolicy)
  }

  /// Phase 2 realtime hub: ask the backend to mint a short-lived ephemeral token
  /// for `provider` ("openai"|"gemini"). The backend gates on auth + paywall.
  /// Credential failures are typed so the hub can recover deterministically instead
  /// of treating every failure as a silent fallback.
  func mintRealtimeToken(
    provider: String,
    expectedOwnerID: String,
    customBaseURL: String? = nil
  ) async throws -> String {
    struct Resp: Decodable { let token: String }
    let base = customBaseURL ?? rustBackendURL
    guard !base.isEmpty else {
      throw CredentialHealthError.backendTransient(
        statusCode: nil,
        message: "Desktop backend URL is not configured.")
    }
    let normalized = base.hasSuffix("/") ? base : base + "/"
    guard let url = URL(string: normalized + "v2/realtime/session") else {
      throw CredentialHealthError.backendTransient(statusCode: nil, message: "Invalid desktop backend URL.")
    }

    let providerType = CredentialHealthManager.realtimeProvider(from: provider)
    let authPolicy = RequestAuthPolicy.ownerBound(expectedOwnerID)
    try validateExpectedOwner(authPolicy)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: true,
      expectedAuthOwnerId: expectedOwnerID)
    request.httpBody = try JSONEncoder().encode(["provider": provider])

    do {
      return try await performRealtimeMintRequest(
        request,
        provider: providerType,
        authPolicy: authPolicy,
        retriedAuth: false)
    } catch let error as RealtimeTokenMintError {
      log("APIClient: realtime token mint failed for \(provider): \(error.localizedDescription)")
      throw error
    } catch let error as CredentialHealthError {
      log("APIClient: realtime token mint failed for \(provider): \(error.localizedDescription)")
      throw error
    } catch let error as AuthError {
      log("APIClient: realtime token mint rejected after owner change for \(provider)")
      throw error
    } catch {
      log("APIClient: realtime token mint failed for \(provider): \(error.localizedDescription)")
      throw CredentialHealthError.backendTransient(statusCode: nil, message: error.localizedDescription)
    }
  }

  private func performRealtimeMintRequest(
    _ request: URLRequest,
    provider: RealtimeHubProvider?,
    authPolicy: RequestAuthPolicy,
    retriedAuth: Bool
  ) async throws -> String {
    struct Resp: Decodable { let token: String }
    try validateExpectedOwner(authPolicy)
    let (data, response) = try await session.data(for: request)
    try validateExpectedOwner(authPolicy)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CredentialHealthError.backendTransient(
        statusCode: nil, message: APIError.invalidResponse.localizedDescription)
    }

    if httpResponse.statusCode == 401,
      Self.isProviderCredentialFailure(statusCode: httpResponse.statusCode, data: data)
    {
      let payload = OmiHTTPTransport.extractErrorPayload(from: data)
      let healthError = CredentialHealthManager.classifyHTTPFailure(
        statusCode: httpResponse.statusCode,
        payload: payload,
        provider: provider)
      throw RealtimeTokenMintError(
        statusCode: httpResponse.statusCode,
        healthError: healthError,
        payload: payload)
    }

    if httpResponse.statusCode == 401, !retriedAuth {
      guard
        let retry = try await authorizedRetryRequest(
          from: request,
          retriedAuth: false,
          authPolicy: authPolicy
        )
      else {
        throw CredentialHealthError.requiresLogin(message: "Please sign in again to use voice responses.")
      }
      do {
        let token = try await performRealtimeMintRequest(
          retry,
          provider: provider,
          authPolicy: authPolicy,
          retriedAuth: true)
        log("CredentialHealth: context=realtime_mint_auth_retry failure_class=retry_succeeded")
        return token
      } catch let error as RealtimeTokenMintError {
        throw error
      } catch let error as CredentialHealthError {
        throw error
      } catch {
        throw CredentialHealthError.backendTransient(statusCode: nil, message: error.localizedDescription)
      }
    }

    if httpResponse.statusCode == 401 {
      await invalidateSessionAfterUnauthorized(
        endpoint: endpointLabel(for: request),
        signOutOn401: authPolicy.signOutOn401)
      throw CredentialHealthError.requiresLogin(message: "Please sign in again to use voice responses.")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let payload = OmiHTTPTransport.extractErrorPayload(from: data)
      let healthError = CredentialHealthManager.classifyHTTPFailure(
        statusCode: httpResponse.statusCode,
        payload: payload,
        provider: provider)
      throw RealtimeTokenMintError(statusCode: httpResponse.statusCode, healthError: healthError, payload: payload)
    }

    let resp = try decoder.decode(Resp.self, from: data)
    guard !resp.token.isEmpty else {
      throw CredentialHealthError.backendTransient(
        statusCode: httpResponse.statusCode, message: "Realtime token was empty.")
    }
    return resp.token
  }

  /// Report a managed realtime turn's token usage so the backend can price it and record
  /// it into the llm_usage cost ledger. Fire-and-forget; failures are
  /// logged and dropped (the backend reconciler is the eventual safety net).
  func reportRealtimeUsage(
    provider: String,
    model: String,
    inputText: Int,
    inputAudio: Int,
    inputCached: Int,
    outputText: Int,
    outputAudio: Int
  ) async {
    let base = rustBackendURL
    guard !base.isEmpty else { return }
    let normalized = base.hasSuffix("/") ? base : base + "/"
    guard let url = URL(string: normalized + "v2/realtime/usage") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    do {
      let headers = try await buildHeaders(requireAuth: true)
      for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
      let body: [String: Any] = [
        "provider": provider,
        "model": model,
        "input_text_tokens": inputText,
        "input_audio_tokens": inputAudio,
        "input_cached_tokens": inputCached,
        "output_text_tokens": outputText,
        "output_audio_tokens": outputAudio,
      ]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      _ = try await session.data(for: request)
    } catch {
      log("APIClient: realtime usage report failed: \(error.localizedDescription)")
    }
  }

  func performVoidRequest(
    _ request: URLRequest,
    authPolicy: RequestAuthPolicy = .default,
    retriedAuth: Bool = false
  ) async throws {
    let (_, httpResponse) = try await performAuthenticatedData(
      for: request,
      authPolicy: authPolicy,
      retriedAuth: retriedAuth
    )

    guard (200...299).contains(httpResponse.statusCode) else {
      throw APIError.httpError(statusCode: httpResponse.statusCode)
    }
  }

  func delete(
    _ endpoint: String,
    requireAuth: Bool = true,
    customBaseURL: String? = nil,
    authPolicy: RequestAuthPolicy = .default,
    expectedAuthOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws {
    let effectiveAuthPolicy = try resolvedRequestAuthPolicy(
      expectedOwnerId: expectedAuthOwnerId,
      authorizationSnapshot: authorizationSnapshot,
      fallback: authPolicy)
    let authOwnerId = effectiveAuthPolicy.expectedAuthOwnerId
    try validateExpectedOwner(effectiveAuthPolicy)
    let base = customBaseURL ?? baseURL
    let url = URL(string: base + endpoint)!
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: requireAuth,
      expectedAuthOwnerId: authOwnerId
    )
    try validateExpectedOwner(effectiveAuthPolicy)

    try await performVoidRequest(request, authPolicy: effectiveAuthPolicy)
  }

  // MARK: - Request Execution

  func invalidateSessionAfterUnauthorized(endpoint: String, signOutOn401: Bool) async {
    guard signOutOn401 else { return }
    await AuthSessionCoordinator.shared.handleHTTPUnauthorized(
      endpoint: endpoint,
      signOutOn401: true,
      auth: AuthService.shared
    )
  }

  func endpointLabel(for request: URLRequest) -> String {
    request.url?.path ?? request.url?.absoluteString ?? "unknown"
  }

  /// Refresh auth and build a retry request. Returns nil when already retried (caller should throw).
  private func authorizedRetryRequest(
    from request: URLRequest,
    retriedAuth: Bool,
    authPolicy: RequestAuthPolicy
  ) async throws -> URLRequest? {
    if retriedAuth {
      await invalidateSessionAfterUnauthorized(
        endpoint: endpointLabel(for: request),
        signOutOn401: authPolicy.signOutOn401
      )
      return nil
    }
    let authService = await MainActor.run { AuthService.shared }
    do {
      var retry = request
      let authHeader: String
      if let expectedOwnerId = authPolicy.expectedAuthOwnerId {
        authHeader = try await authService.getAuthHeader(
          forceRefresh: true,
          expectedUserId: expectedOwnerId
        )
      } else {
        authHeader = try await authService.getAuthHeader(forceRefresh: true)
      }
      try validateExpectedOwner(authPolicy)
      retry.setValue(authHeader, forHTTPHeaderField: "Authorization")
      return retry
    } catch AuthError.notSignedIn {
      await invalidateSessionAfterUnauthorized(
        endpoint: endpointLabel(for: request),
        signOutOn401: authPolicy.signOutOn401
      )
      return nil
    }
  }

  func performAuthenticatedData(
    for request: URLRequest,
    authPolicy: RequestAuthPolicy = .default,
    retriedAuth: Bool = false
  ) async throws -> (Data, HTTPURLResponse) {
    try validateExpectedOwner(authPolicy)
    let endpoint = endpointLabel(for: request)
    let (data, response) = try await session.data(for: request)
    try validateExpectedOwner(authPolicy)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }

    if httpResponse.statusCode == 401 {
      if authPolicy.returnsPersistent401Response,
        Self.isProviderCredentialFailure(statusCode: httpResponse.statusCode, data: data)
      {
        return (data, httpResponse)
      }
      if retriedAuth, authPolicy.returnsPersistent401Response {
        return (data, httpResponse)
      }
      if !retriedAuth, authPolicy.recordsAuthRetryTelemetry {
        DesktopDiagnosticsManager.shared.recordApiAuthRetry(endpoint: endpoint, outcome: "retrying")
      }
      guard
        let retryRequest = try await authorizedRetryRequest(
          from: request,
          retriedAuth: retriedAuth,
          authPolicy: authPolicy
        )
      else {
        if authPolicy.recordsAuthRetryTelemetry {
          DesktopDiagnosticsManager.shared.recordApiAuthRetry(endpoint: endpoint, outcome: "unauthorized")
        }
        throw APIError.unauthorized
      }
      do {
        let result = try await performAuthenticatedData(
          for: retryRequest,
          authPolicy: authPolicy,
          retriedAuth: true
        )
        let (_, retryResponse) = result
        let outcome = (200...299).contains(retryResponse.statusCode) ? "succeeded" : "failed"
        if authPolicy.recordsAuthRetryTelemetry {
          DesktopDiagnosticsManager.shared.recordApiAuthRetry(endpoint: endpoint, outcome: outcome)
        }
        return result
      } catch {
        if case APIError.unauthorized = error {
          throw error
        }
        if authPolicy.recordsAuthRetryTelemetry {
          DesktopDiagnosticsManager.shared.recordApiAuthRetry(endpoint: endpoint, outcome: "failed")
        }
        throw error
      }
    }

    return (data, httpResponse)
  }

  /// Provider proxies preserve this wire shape when the caller's Firebase credential was
  /// accepted but the managed upstream credential was rejected. Inspect it before refreshing
  /// Firebase so a provider-key failure cannot become an account-session invalidation.
  nonisolated static func isProviderCredentialFailure(statusCode: Int, data: Data) -> Bool {
    // session-preserving: this 401 belongs to the managed provider credential, not Firebase.
    guard statusCode == 401, let payload = OmiHTTPTransport.extractErrorPayload(from: data) else {
      return false
    }
    if payload.managedProviderFailureReason == .authFailed,
      payload.provider != nil,
      payload.upstreamStatusCode == 401
    {
      return true
    }
    return false
  }

  /// An owner-bound request may finish after the app has signed out or switched
  /// accounts. The authorization header still belongs to the original owner,
  /// so never let that response flow into the new owner's local state.
  nonisolated func validateExpectedOwner(_ authPolicy: RequestAuthPolicy) throws {
    if let authorizationSnapshot = authPolicy.authorizationSnapshot {
      guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
        throw AuthError.userChangedDuringRequest
      }
      return
    }
    guard let expectedOwnerId = authPolicy.expectedAuthOwnerId else { return }
    guard AuthorizedToolExecution.isOwnerCurrent(expectedOwnerId) else {
      throw AuthError.userChangedDuringRequest
    }
  }

  func performRequest<T: Decodable>(
    _ request: URLRequest,
    authPolicy: RequestAuthPolicy = .default,
    retriedAuth: Bool = false
  ) async throws -> T {
    let (data, httpResponse) = try await performAuthenticatedData(
      for: request,
      authPolicy: authPolicy,
      retriedAuth: retriedAuth
    )

    guard (200...299).contains(httpResponse.statusCode) else {
      let detail = OmiHTTPTransport.extractErrorDetail(from: data)
      throw APIError.httpError(statusCode: httpResponse.statusCode, detail: detail)
    }

    do {
      let decoded = try decoder.decode(T.self, from: data)
      try validateExpectedOwner(authPolicy)
      return decoded
    } catch let decodingError as DecodingError {
      // Log detailed decoding error for debugging
      switch decodingError {
      case .keyNotFound(let key, let context):
        logError(
          "Decoding error - key '\(key.stringValue)' not found: \(context.debugDescription)",
          error: decodingError)
      case .typeMismatch(let type, let context):
        logError(
          "Decoding error - type mismatch for \(type): \(context.debugDescription)",
          error: decodingError)
      case .valueNotFound(let type, let context):
        logError(
          "Decoding error - value not found for \(type): \(context.debugDescription)",
          error: decodingError)
      case .dataCorrupted(let context):
        logError(
          "Decoding error - data corrupted: \(context.debugDescription)", error: decodingError)
      @unknown default:
        logError("Decoding error", error: decodingError)
      }
      throw decodingError
    }
  }
}

struct RealtimeTokenMintError: LocalizedError {
  let statusCode: Int
  let healthError: CredentialHealthError
  let payload: APIErrorPayload?

  var errorDescription: String? {
    var description = healthError.localizedDescription
    description += " [status: \(statusCode)"
    if let reason = payload?.reason {
      description += ", reason: \(reason)"
    }
    if let code = payload?.code {
      description += ", code: \(code)"
    }
    description += "]"
    return description
  }
}

extension APIClient {
  // MARK: - PATCH helper

  func patch<T: Decodable, B: Encodable>(
    _ endpoint: String,
    body: B,
    requireAuth: Bool = true,
    customBaseURL: String? = nil,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> T {
    let authPolicy = try resolvedRequestAuthPolicy(
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
    let authOwnerId = authPolicy.expectedAuthOwnerId
    try validateExpectedOwner(authPolicy)
    let base = customBaseURL ?? baseURL
    let url = URL(string: base + endpoint)!
    var request = URLRequest(url: url)
    request.httpMethod = "PATCH"
    request.allHTTPHeaderFields = try await buildHeaders(
      requireAuth: requireAuth,
      expectedAuthOwnerId: authOwnerId)
    try validateExpectedOwner(authPolicy)
    request.httpBody = try JSONEncoder().encode(body)

    return try await performPatchRequest(
      request,
      authPolicy: authPolicy)
  }

  private func performPatchRequest<T: Decodable>(
    _ request: URLRequest,
    authPolicy: RequestAuthPolicy = .default
  ) async throws -> T {
    // Delegate to performRequest so PATCH gets the same 401 refresh-and-retry as
    // GET/POST. PATCH previously threw `.unauthorized` on the first 401, which
    // surfaced as a user-visible failure (e.g. the onboarding language step)
    // whenever the ID token was momentarily stale right after sign-in.
    return try await performRequest(request, authPolicy: authPolicy)
  }
}
