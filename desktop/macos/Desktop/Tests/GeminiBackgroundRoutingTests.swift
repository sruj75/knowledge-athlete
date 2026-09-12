import XCTest

@testable import Omi_Computer

/// #102: exercise the actual managed HTTP request, not only model constants.
private final class BackgroundGeminiURLStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let available = request.url?.path == "/v1/proxy/gemini/models/gemini-3.7-flash:generateContent"
    let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only"
    let status = !authorized ? 401 : (available ? 200 : 404)
    let body =
      available && authorized
      ? #"{"candidates":[{"content":{"parts":[{"text":"generated note"}]}}]}"#
      : #"{"error":{"message":"model unavailable"}}"#
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class GeminiBackgroundRoutingTests: XCTestCase {
  private func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BackgroundGeminiURLStub.self]
    return URLSession(configuration: configuration)
  }

  func testDefaultLiveNotesClientUsesAvailableAuthenticatedRoute() async throws {
    let session = session()
    defer { session.invalidateAndCancel() }
    let client = try GeminiClient(session: session, authHeaderProvider: { "Bearer test-only" })
    let note = try await client.sendTextRequest(prompt: "test fact", systemPrompt: "Summarize", maxRetries: 0)
    XCTAssertEqual(note, "generated note")
  }

  func testEachBackgroundRoleUsesAvailableAuthenticatedRoute() async throws {
    let session = session()
    defer { session.invalidateAndCancel() }
    for model in [
      ModelQoS.Gemini.proactive, ModelQoS.Gemini.taskExtraction,
      ModelQoS.Gemini.insight, ModelQoS.Gemini.suggestions,
    ] {
      let client = try GeminiClient(model: model, session: session, authHeaderProvider: { "Bearer test-only" })
      let result = try await client.sendTextRequest(prompt: "test", systemPrompt: "Summarize", maxRetries: 0)
      XCTAssertEqual(result, "generated note")
    }
  }

  func testUnavailableModelRemainsAnErrorRatherThanAnEmptySuccess() async throws {
    let session = session()
    defer { session.invalidateAndCancel() }
    let client = try GeminiClient(
      model: "gemini-2.5-flash", session: session, authHeaderProvider: { "Bearer test-only" })
    do {
      _ = try await client.sendTextRequest(prompt: "test", systemPrompt: "Summarize", maxRetries: 0)
      XCTFail("Unavailable models must propagate the provider failure")
    } catch let error as GeminiClient.GeminiClientError {
      guard case .apiError(let message) = error else { return XCTFail("Expected HTTP failure") }
      XCTAssertTrue(message.hasPrefix("HTTP 404:"))
    }
  }
}
