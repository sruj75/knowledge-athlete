import XCTest

@testable import Omi_Computer

// MARK: - Request-capturing protocol for routing verification

/// Captured request info: URL + HTTP method.
private struct CapturedRequest {
  let url: URL
  let method: String
  let headers: [String: String]
  let body: Data?
}

private struct ManagedHeaderResponse: Decodable {}

private struct ManagedHeaderBody: Encodable {
  let value: String
}

/// Intercepts HTTP requests, records their URL and method, then returns 403
/// so APIClient throws .httpError (not 401, which triggers AuthService refresh).
private final class URLCapture: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var _requests: [CapturedRequest] = []
  private nonisolated(unsafe) static var _statusCode = 403
  private nonisolated(unsafe) static var _responseBody = Data("{\"detail\":\"test\"}".utf8)

  static var capturedRequests: [CapturedRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _requests
  }

  static func reset() {
    lock.lock()
    _requests.removeAll()
    _statusCode = 403
    _responseBody = Data("{\"detail\":\"test\"}".utf8)
    lock.unlock()
  }

  static func setResponse(statusCode: Int, body: Data) {
    lock.lock()
    _statusCode = statusCode
    _responseBody = body
    lock.unlock()
  }

  private static func record(_ req: CapturedRequest) {
    lock.lock()
    _requests.append(req)
    lock.unlock()
  }

  private static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
      return body
    }

    guard let stream = request.httpBodyStream else {
      return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
      let readCount = stream.read(buffer, maxLength: bufferSize)
      if readCount > 0 {
        data.append(buffer, count: readCount)
      } else if readCount < 0 {
        return nil
      } else {
        break
      }
    }

    return data.isEmpty ? nil : data
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if let url = request.url {
      URLCapture.record(
        CapturedRequest(
          url: url,
          method: request.httpMethod ?? "GET",
          headers: request.allHTTPHeaderFields ?? [:],
          body: Self.bodyData(from: request)
        ))
    }
    let (statusCode, body) = Self.response()
    let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func response() -> (Int, Data) {
    lock.lock()
    defer { lock.unlock() }
    return (_statusCode, _responseBody)
  }
}

// MARK: - Assertion helpers

private func assertRoutes(
  _ reqs: [CapturedRequest],
  host: String,
  port: Int,
  pathContains: String,
  method: String,
  label: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(reqs.count, 1, "\(label): expected 1 request, got \(reqs.count)", file: file, line: line)
  guard let req = reqs.first else { return }
  XCTAssertEqual(req.url.host, host, "\(label): wrong host", file: file, line: line)
  XCTAssertEqual(req.url.port, port, "\(label): wrong port", file: file, line: line)
  XCTAssertTrue(
    req.url.absoluteString.contains(pathContains),
    "\(label): path should contain '\(pathContains)', got \(req.url.absoluteString)", file: file, line: line)
  XCTAssertEqual(req.method, method, "\(label): wrong HTTP method", file: file, line: line)
}

private func assertCapturedPath(
  _ expectedPath: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let requests = URLCapture.capturedRequests
  XCTAssertEqual(requests.count, 1, file: file, line: line)
  XCTAssertEqual(requests.first?.url.path, expectedPath, file: file, line: line)
}

// MARK: - Tests

final class APIClientRoutingTests: XCTestCase {
  private let ownedProductionBackendURL = "https://api.heyintentive.com/"

  // MARK: - URL property tests

  func testBackendBaseURLUsesOneCanonicalOverride() {
    XCTAssertEqual(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: true,
        environmentValue: "http://canonical.test:8080",
        productionMetadataValue: nil
      ),
      "http://canonical.test:8080/"
    )
    XCTAssertEqual(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: false,
        environmentValue: "http://contaminated.test:8080",
        productionMetadataValue: ownedProductionBackendURL
      ),
      ownedProductionBackendURL
    )
  }

  func testNonProductionAppDefaultsToDevelopmentBackend() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: true,
      environmentValue: nil,
      productionMetadataValue: nil)
    XCTAssertEqual(url, DesktopBackendEnvironment.developmentBackendURL)
  }

  func testInheritedOmiBackendOverrideIsRejected() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: true,
      environmentValue: "https://api.omi.me",
      productionMetadataValue: nil
    )
    XCTAssertEqual(url, DesktopBackendEnvironment.developmentBackendURL)
  }

  func testMalformedDevelopmentOverrideIsRejected() {
    for candidate in ["ftp://example.test", "https://user:secret@example.test", "https://example.test/#fragment"] {
      XCTAssertEqual(
        DesktopBackendEnvironment.resolvedBackendBaseURL(
          useDevelopmentBackends: true,
          environmentValue: candidate,
          productionMetadataValue: nil),
        DesktopBackendEnvironment.developmentBackendURL
      )
    }
  }

  func testDevelopmentDefaultUsesOwnedCloudRunBackendWithoutOverride() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: true,
      environmentValue: nil,
      productionMetadataValue: nil
    )
    XCTAssertEqual(url, "https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app/")
  }

  func testProductionAuthUsesSignedOwnedBackendMetadata() {
    let url = DesktopBackendEnvironment.resolvedAuthBaseURL(
      useDevelopmentBackends: false,
      environmentValue: nil,
      productionMetadataValue: ownedProductionBackendURL)
    XCTAssertEqual(url, ownedProductionBackendURL)
  }

  func testDevelopmentAuthBackendCanBeExplicitlyOverridden() {
    let url = DesktopBackendEnvironment.resolvedAuthBaseURL(
      useDevelopmentBackends: true,
      environmentValue: "http://localhost:8080",
      productionMetadataValue: nil
    )
    XCTAssertEqual(url, "http://localhost:8080/")
  }

  func testStableProductionBundleKeepsProductionBackend() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: false,
      environmentValue: "https://api.omi.me",
      productionMetadataValue: ownedProductionBackendURL
    )
    XCTAssertEqual(url, ownedProductionBackendURL)
  }

  func testDevelopmentDefaultsDoNotOverwriteExplicitBackendURL() {
    let originalBackend = ProcessInfo.processInfo.environment["OMI_PYTHON_API_URL"]
    defer {
      if let originalBackend {
        setenv("OMI_PYTHON_API_URL", originalBackend, 1)
      } else {
        unsetenv("OMI_PYTHON_API_URL")
      }
    }

    setenv("OMI_PYTHON_API_URL", "http://canonical-override:8080", 1)
    DesktopBackendEnvironment.applyReleaseChannelDefaults()

    XCTAssertEqual(
      ProcessInfo.processInfo.environment["OMI_PYTHON_API_URL"],
      "http://canonical-override:8080"
    )
  }

  func testBundleEnvironmentDoesNotOverwriteExplicitLaunchBackendURL() {
    let launchEnvironment = [
      "OMI_PYTHON_API_URL": "http://127.0.0.1:8080"
    ]

    XCTAssertFalse(
      BundleEnvironment.shouldApplyBundledValue(
        for: "OMI_PYTHON_API_URL",
        launchEnvironment: launchEnvironment
      ))
    XCTAssertTrue(
      BundleEnvironment.shouldApplyBundledValue(
        for: "FIREBASE_API_KEY",
        launchEnvironment: launchEnvironment
      ))
  }

  func testBetaProductionChannelUsesProductionBackendRatherThanDevelopment() {
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.productionBundleIdentifier,
        updateChannel: "beta"
      ))
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.productionBundleIdentifier,
        updateChannel: "staging"
      ))
    XCTAssertEqual(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: false,
        environmentValue: nil,
        productionMetadataValue: ownedProductionBackendURL
      ),
      ownedProductionBackendURL
    )
  }

  func testStableProductionBundleKeepsProductionBackends() {
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.productionBundleIdentifier,
        updateChannel: "stable"
      ))
  }

  func testBetaIdentityBundleUsesTheProductionBackend() {
    // The Intentive Beta app is production-family: its isolated app identity does not
    // create a second backend environment.
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.betaProductionBundleIdentifier,
        updateChannel: "beta"
      ))
    XCTAssertEqual(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: false,
        environmentValue: nil,
        productionMetadataValue: ownedProductionBackendURL),
      ownedProductionBackendURL
    )
  }

  func testNonProductionBundlesDefaultToDevelopmentBackends() {
    XCTAssertTrue(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.desktopDevBundleIdentifier,
        updateChannel: "beta"
      ))
    XCTAssertTrue(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: "com.heyintentive.intentive.dev.beta-test",
        updateChannel: "stable"
      ))
  }

  func testProductionFamilyHasNoDevelopmentOverrideSeam() {
    XCTAssertTrue(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.desktopDevBundleIdentifier,
        updateChannel: "stable"
      ))
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.productionBundleIdentifier,
        updateChannel: "stable"
      ))
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: AppBuild.productionBundleIdentifier,
        updateChannel: "beta"
      ))
  }

  func testProductionFamilyIgnoresContaminatedProcessEndpoints() {
    XCTAssertEqual(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: false,
        environmentValue: "https://staging.example.test",
        productionMetadataValue: ownedProductionBackendURL
      ),
      ownedProductionBackendURL
    )
    XCTAssertEqual(
      DesktopBackendEnvironment.resolvedAuthBaseURL(
        useDevelopmentBackends: false,
        environmentValue: "https://staging.example.test",
        productionMetadataValue: ownedProductionBackendURL
      ),
      ownedProductionBackendURL
    )
  }

  func testMissingOrInheritedProductionMetadataFailsClosed() {
    XCTAssertNil(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: false,
        environmentValue: nil,
        productionMetadataValue: nil))
    XCTAssertNil(
      DesktopBackendEnvironment.resolvedBackendBaseURL(
        useDevelopmentBackends: false,
        environmentValue: nil,
        productionMetadataValue: "https://api.omi.me"))
  }

  func testForeignOmiBundleDoesNotInheritDevelopmentRouting() {
    XCTAssertFalse(
      DesktopBackendEnvironment.shouldUseDevelopmentBackends(
        bundleIdentifier: "com.omi.computer-macos",
        updateChannel: "stable"))
  }

  func testBaseURLReadsFromPythonEnvVar() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: true,
      environmentValue: "http://localhost:8080",
      productionMetadataValue: nil)
    XCTAssertEqual(url, "http://localhost:8080/")
  }

  func testBaseURLAddsTrailingSlash() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: true,
      environmentValue: "http://localhost:8080",
      productionMetadataValue: nil)
    XCTAssertTrue(url?.hasSuffix("/") == true)
  }

  func testBaseURLPreservesExistingTrailingSlash() {
    let url = DesktopBackendEnvironment.resolvedBackendBaseURL(
      useDevelopmentBackends: true,
      environmentValue: "http://localhost:8080/",
      productionMetadataValue: nil)
    XCTAssertEqual(url, "http://localhost:8080/")
  }

  func testRealtimeMintStructuredFailurePreservesDiagnostics() async throws {
    let previousOwner = UserDefaults.standard.object(forKey: .authUserId)
    let previousOverride = UserDefaults.standard.object(forKey: .automationOwnerOverride)
    UserDefaults.standard.set("realtime-routing-owner", forKey: .authUserId)
    UserDefaults.standard.removeObject(forKey: .automationOwnerOverride)
    defer {
      if let previousOwner {
        UserDefaults.standard.set(previousOwner, forKey: .authUserId)
      } else {
        UserDefaults.standard.removeObject(forKey: .authUserId)
      }
      if let previousOverride {
        UserDefaults.standard.set(previousOverride, forKey: .automationOwnerOverride)
      } else {
        UserDefaults.standard.removeObject(forKey: .automationOwnerOverride)
      }
    }
    let body = Data(
      """
      {
        "error": "quota exhausted",
        "reason": "provider_quota_exceeded",
        "provider": "gemini",
        "backend_route": "/v2/realtime/session",
        "upstream_status_code": 429,
        "retryable": true,
        "code": "insufficient_quota"
      }
      """.utf8)
    URLCapture.setResponse(statusCode: 429, body: body)
    let client = await makeTestClient()

    do {
      _ = try await client.mintRealtimeToken(expectedOwnerID: "realtime-routing-owner")
      XCTFail("Expected structured realtime mint failure")
    } catch let error as RealtimeTokenMintError {
      XCTAssertEqual(error.statusCode, 429)
      XCTAssertEqual(error.payload?.reason, "provider_quota_exceeded")
      XCTAssertEqual(error.payload?.backendRoute, "/v2/realtime/session")
      XCTAssertEqual(error.payload?.upstreamStatusCode, 429)
      XCTAssertEqual(error.payload?.retryable, true)
      XCTAssertEqual(error.healthError.failureClass.logValue, "provider_quota_exceeded")
      XCTAssertTrue(error.localizedDescription.contains("status: 429"))
      XCTAssertTrue(error.localizedDescription.contains("reason: provider_quota_exceeded"))
      XCTAssertTrue(error.localizedDescription.contains("code: insufficient_quota"))
    }
  }

  // MARK: - Routing behavior: canonical backend endpoints

  private func makeTestClient() async -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLCapture.self]
    let session = URLSession(configuration: config)
    let client = APIClient(session: session)
    await client.setTestAuthHeader("Bearer test-token")
    return client
  }

  override func setUp() {
    super.setUp()
    URLCapture.reset()
    setenv("OMI_PYTHON_API_URL", "http://canonical-test:9001", 1)
  }

  override func tearDown() {
    unsetenv("OMI_PYTHON_API_URL")
    URLCapture.reset()
    super.tearDown()
  }

  func testManagedRequestsNeverEmitLegacyCustomerKeys() async throws {
    let legacyKeys = [
      (storage: "dev_openai_api_key", header: "X-BYOK-OpenAI"),
      (storage: "dev_anthropic_api_key", header: "X-BYOK-Anthropic"),
      (storage: "dev_gemini_api_key", header: "X-BYOK-Gemini"),
      (storage: "dev_deepgram_api_key", header: "X-BYOK-Deepgram"),
    ]
    for legacyKey in legacyKeys {
      UserDefaults.standard.set("legacy-customer-secret", forKey: legacyKey.storage)
    }
    defer {
      for legacyKey in legacyKeys {
        UserDefaults.standard.removeObject(forKey: legacyKey.storage)
      }
    }

    let client = await makeTestClient()
    let baseURL = "http://canonical-test:9001/"
    let _: ManagedHeaderResponse? = try? await client.get("managed-get", customBaseURL: baseURL)
    let _: ManagedHeaderResponse? = try? await client.post(
      "managed-body", body: ManagedHeaderBody(value: "payload"), customBaseURL: baseURL)
    let _: ManagedHeaderResponse? = try? await client.post("managed-post", customBaseURL: baseURL)
    try? await client.delete("managed-delete", customBaseURL: baseURL)

    let requests = URLCapture.capturedRequests
    XCTAssertEqual(requests.map(\.method), ["GET", "POST", "POST", "DELETE"])
    XCTAssertEqual(requests.count, 4)
    for request in requests {
      XCTAssertEqual(request.headers["Authorization"], "Bearer test-token")
      XCTAssertEqual(request.headers["X-App-Platform"], "macos")
      XCTAssertNotNil(request.headers["X-Device-Id-Hash"])
      for legacyKey in legacyKeys {
        XCTAssertNil(request.headers[legacyKey.header])
      }
    }
  }

  // -- Subscription/payments --

  func testGetUserSubscriptionRoutesToPython() async {
    let client = await makeTestClient()
    _ = try? await client.getUserSubscription() as UserSubscriptionResponse
    assertRoutes(
      URLCapture.capturedRequests, host: "canonical-test", port: 9001,
      pathContains: "v1/users/me/subscription", method: "GET",
      label: "getUserSubscription")
  }

  func testLocalComputeRoutesDoNotIntroduceDoubleSlashPaths() async {
    let client = await makeTestClient()
    let requestId = UUID()
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    _ = try? await client.computeDiscard(
      ConversationDiscardComputeRequest(
        generationId: requestId,
        transcript: "A complete local transcript.",
        durationSeconds: 1
      ),
      authorizationSnapshot: nil)
    assertCapturedPath("/v1/conversation-compute/discard")

    URLCapture.reset()
    _ = try? await client.computeStructure(
      ConversationStructureComputeRequest(
        generationId: requestId,
        transcript: "A complete local transcript.",
        startedAt: startedAt,
        language: "en",
        outputLanguage: "en",
        timezone: "UTC"
      ),
      authorizationSnapshot: nil)
    assertCapturedPath("/v1/conversation-compute/structure")

    URLCapture.reset()
    _ = try? await client.computeActionItems(
      ConversationActionItemsComputeRequest(
        generationId: requestId,
        transcript: "A complete local transcript.",
        startedAt: startedAt,
        language: "en",
        outputLanguage: "en",
        timezone: "UTC",
        relatedTasks: []
      ),
      authorizationSnapshot: nil)
    assertCapturedPath("/v1/conversation-compute/action-items")

    URLCapture.reset()
    _ = try? await client.normalizeMemory(
      MemoryNormalizeComputeRequest(
        requestId: requestId,
        revision: 1,
        assertion: "The user prefers concise answers.",
        source: "manual",
        sourceAttribution: "user",
        provenanceTokens: []
      ),
      authorizationSnapshot: nil)
    assertCapturedPath("/v1/memory/compute/normalize")

    URLCapture.reset()
    _ = try? await client.extractMemories(
      MemoryExtractComputeRequest(
        requestId: requestId,
        generation: 1,
        segments: [],
        language: "en"
      ),
      authorizationSnapshot: nil)
    assertCapturedPath("/v1/memory/compute/extract")

    URLCapture.reset()
    _ = try? await client.consolidateMemories(
      MemoryConsolidateComputeRequest(
        requestId: requestId,
        generation: 1,
        candidates: [],
        activeMemories: []
      ),
      authorizationSnapshot: nil)
    assertCapturedPath("/v1/memory/compute/consolidate")
  }

  // -- Config/API keys --

  func testFetchApiKeysRoutesToCanonicalBackend() async {
    let client = await makeTestClient()
    _ = try? await client.fetchApiKeys() as APIClient.ApiKeysResponse
    assertRoutes(
      URLCapture.capturedRequests, host: "canonical-test", port: 9001,
      pathContains: "v1/config/api-keys", method: "GET",
      label: "fetchApiKeys")
  }

  func testSynthesizeSpeechRoutesToCanonicalBackend() async {
    let client = await makeTestClient()
    _ = try? await client.synthesizeSpeech(
      request: APIClient.TtsSynthesizeRequest(
        text: "Hello",
        voiceId: "onyx",
        instructions: "Speak naturally"
      )
    )

    let requests = URLCapture.capturedRequests
    assertRoutes(
      requests, host: "canonical-test", port: 9001,
      pathContains: "v1/tts/synthesize", method: "POST",
      label: "synthesizeSpeech")

    let body = requests.first?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    XCTAssertEqual(body?["text"] as? String, "Hello")
    XCTAssertEqual(body?["voice_id"] as? String, "onyx")
    XCTAssertEqual(body?["instructions"] as? String, "Speak naturally")
  }

  // MARK: - Remaining manual URL builders

  // -- Chat AI endpoints (migrated from Rust to Python) --

  func testGetInitialMessageRoutesToPython() async {
    let client = await makeTestClient()
    _ = try? await client.getInitialMessage(profileText: "Local profile", memories: ["Local memory"])
    assertRoutes(
      URLCapture.capturedRequests, host: "canonical-test", port: 9001,
      pathContains: "v2/chat/initial-message", method: "POST",
      label: "getInitialMessage")
  }

  func testGenerateSessionTitleRoutesToPython() async {
    let client = await makeTestClient()
    _ = try? await client.generateSessionTitle(userText: "hi", assistantText: "hello")
    assertRoutes(
      URLCapture.capturedRequests, host: "canonical-test", port: 9001,
      pathContains: "v2/chat/generate-title", method: "POST",
      label: "generateSessionTitle")
  }

  func testRealtimeUsageReportContainsOnlyTokenCounts() async {
    let client = await makeTestClient()

    await client.reportRealtimeUsage(
      inputText: 11,
      inputAudio: 12,
      inputCached: 13,
      outputText: 14,
      outputAudio: 15)

    let requests = URLCapture.capturedRequests
    assertRoutes(
      requests, host: "canonical-test", port: 9001,
      pathContains: "v2/realtime/usage", method: "POST",
      label: "reportRealtimeUsage")
    let body = requests.first?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    XCTAssertEqual(
      Set(body?.keys.map { $0 } ?? []),
      Set([
        "input_text_tokens", "input_audio_tokens", "input_cached_tokens", "output_text_tokens",
        "output_audio_tokens",
      ]))
    XCTAssertEqual(body?["input_cached_tokens"] as? Int, 13)
  }

  // MARK: - Billing routing and server-owned offer body tests

  func testCreateCheckoutSessionSendsOnlyOfferIdentity() async {
    let client = await makeTestClient()
    _ = try? await client.createCheckoutSession(offerId: "synthetic-monthly")

    let requests = URLCapture.capturedRequests
    assertRoutes(
      requests, host: "canonical-test", port: 9001,
      pathContains: "v1/payments/checkout-session", method: "POST",
      label: "createCheckoutSession")

    let body = requests.first?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    XCTAssertEqual(body?["offer_id"] as? String, "synthetic-monthly")
    XCTAssertEqual(body?.count, 1)
  }

  func testHttpErrorPreservesDetailFromResponse() async {
    let client = await makeTestClient()
    do {
      _ = try await client.createCheckoutSession(offerId: "invalid-offer")
      XCTFail("Expected httpError to be thrown")
    } catch let error as APIError {
      // URLCapture returns 403 with {"detail":"test"} — verify detail is preserved
      XCTAssertEqual(error.detail, "test")
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}

// MARK: - Helper extension to set testAuthHeader from async context

extension APIClient {
  func setTestAuthHeader(_ header: String) async {
    self.testAuthHeader = header
  }
}
