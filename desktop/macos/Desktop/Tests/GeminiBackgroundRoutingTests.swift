import XCTest

@testable import Omi_Computer

/// #102: exercise the actual managed HTTP request, not only model constants.
private final class BackgroundGeminiURLStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let available = request.url?.path == "/v1/proxy/gemini/models/gemini-3.7-flash:generateContent"
    let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only"
    let shape = request.value(forHTTPHeaderField: "X-Test-Shape") ?? "text"
    let payload = (try? JSONSerialization.jsonObject(with: requestBody())) as? [String: Any] ?? [:]
    let config = payload["generation_config"] as? [String: Any] ?? [:]
    let thinking = config["thinking_config"] as? [String: Any] ?? [:]
    let contents = payload["contents"] as? [[String: Any]] ?? []
    let parts = contents.first?["parts"] as? [[String: Any]] ?? []
    let hasImage = parts.contains { $0["inline_data"] != nil }
    let valid: Bool
    switch shape {
    case "image":
      valid =
        hasImage && config["response_schema"] != nil && config["response_mime_type"] as? String == "application/json"
    case "schema":
      valid =
        !hasImage && config["response_schema"] != nil && config["response_mime_type"] as? String == "application/json"
    case "tool":
      let tools = payload["tools"] as? [[String: Any]] ?? []
      valid = hasImage && !tools.isEmpty && payload["tool_config"] != nil
    default:
      valid = !parts.isEmpty
    }
    let validBudget = thinking["thinking_budget"] as? Int == (shape == "tool" ? 1024 : 0)
    let status = !authorized ? 401 : (!available ? 404 : (valid && validBudget ? 200 : 400))
    let body =
      status == 200
      ? (shape == "tool"
        ? #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"inspect","args":{}}}]}}]}"#
        : #"{"candidates":[{"content":{"parts":[{"text":"generated note"}]}}]}"#)
      : #"{"error":{"message":"model unavailable"}}"#
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private func requestBody() -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      result.append(contentsOf: buffer.prefix(count))
    }
    return result
  }
}

final class GeminiBackgroundRoutingTests: XCTestCase {
  private func session(shape: String = "text") -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BackgroundGeminiURLStub.self]
    configuration.httpAdditionalHeaders = ["X-Test-Shape": shape]
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

  func testStructuredTextAndImageRequestsPreserveTheirRealPayloads() async throws {
    let schema = GeminiRequest.GenerationConfig.ResponseSchema(
      type: "OBJECT", properties: ["note": .init(type: "STRING")], required: ["note"])
    for shape in ["image", "schema"] {
      let session = session(shape: shape)
      defer { session.invalidateAndCancel() }
      let client = try GeminiClient(session: session, authHeaderProvider: { "Bearer test-only" })
      let result: String
      if shape == "image" {
        result = try await client.sendRequest(
          prompt: "test", imageData: Data([1, 2, 3]), systemPrompt: "test", responseSchema: schema)
      } else {
        result = try await client.sendRequest(prompt: "test", systemPrompt: "test", responseSchema: schema)
      }
      XCTAssertEqual(result, "generated note")
    }
  }

  func testImageToolRequestPreservesDeclarationsAndDecodesFunctionCall() async throws {
    let session = session(shape: "tool")
    defer { session.invalidateAndCancel() }
    let client = try GeminiClient(session: session, authHeaderProvider: { "Bearer test-only" })
    let result = try await client.sendImageToolLoop(
      contents: [.init(role: "user", parts: [.init(mimeType: "image/jpeg", data: "AQID")])],
      systemPrompt: "test",
      tools: [
        .init(functionDeclarations: [
          .init(
            name: "inspect", description: "test", parameters: .init(type: "OBJECT", properties: [:], required: []))
        ])
      ],
      forceToolCall: true, thinkingBudget: 1024)
    XCTAssertTrue(result.requiresToolExecution)
    XCTAssertEqual(result.toolCalls.map(\.name), ["inspect"])
  }
}
