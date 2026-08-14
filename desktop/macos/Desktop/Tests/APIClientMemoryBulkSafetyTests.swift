import XCTest

@testable import Omi_Computer

private struct BulkCapturedRequest {
  let url: URL
  let method: String
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected async expression to throw", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}

private final class BulkURLCapture: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var requests: [BulkCapturedRequest] = []

  static var capturedRequests: [BulkCapturedRequest] {
    lock.withLock { requests }
  }

  static func reset() {
    lock.withLock { requests.removeAll() }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if let url = request.url {
      Self.lock.withLock {
        Self.requests.append(BulkCapturedRequest(url: url, method: request.httpMethod ?? "GET"))
      }
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("{}".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class APIClientMemoryBulkSafetyTests: XCTestCase {
  override func setUp() {
    super.setUp()
    BulkURLCapture.reset()
    setenv("OMI_PYTHON_API_URL", "http://python-test:9001", 1)
  }

  override func tearDown() {
    unsetenv("OMI_PYTHON_API_URL")
    BulkURLCapture.reset()
    super.tearDown()
  }

  func testDeleteAllMemoriesDefaultScopeUsesUnscopedEndpoint() async {
    let client = await makeClient()
    await XCTAssertThrowsErrorAsync({ try await client.deleteAllMemories(scope: .defaultAccess) })
    XCTAssertEqual(BulkURLCapture.capturedRequests.first?.method, "DELETE")
    XCTAssertEqual(BulkURLCapture.capturedRequests.first?.url.path, "/v3/memories")
  }

  func testMarkAllMemoriesReadScopeThrowsBeforeNetworkRequest() async {
    let client = await makeClient()
    await XCTAssertThrowsErrorAsync({ try await client.markAllMemoriesRead(scope: .defaultAccess) })
    XCTAssertEqual(BulkURLCapture.capturedRequests.count, 0)
  }

  func testChunkedUsesMemoryBatchMaxSizeBoundaries() {
    let values = Array(0..<(APIClient.memoriesBatchMaxSize + 2))
    let chunks = values.chunked(maxSize: APIClient.memoriesBatchMaxSize)
    XCTAssertEqual(chunks.count, 2)
    XCTAssertEqual(chunks[0].count, APIClient.memoriesBatchMaxSize)
  }

  private func makeClient() async -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BulkURLCapture.self]
    let client = APIClient(session: URLSession(configuration: config))
    await client.setTestAuthHeader("Bearer test-token")
    return client
  }
}
