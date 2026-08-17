import XCTest

@testable import Omi_Computer

/// Tests for the Python backend WebSocket protocol parsing.
/// Exercises TranscriptionService.parseBackendResponse() end-to-end with real callback dispatch.
final class ListenProtocolTests: XCTestCase {

  func testConversationListenURLUsesOnlyTransientSTTParameters() throws {
    let service = try TranscriptionService(language: "en", mode: .conversation)

    let url = try service.makeBackendWebSocketURL(base: "wss://api.example.test")
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query: [String: String] = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      })

    XCTAssertEqual(components.path, "/v4/listen")
    XCTAssertEqual(
      query,
      [
        "language": "en",
        "sample_rate": "16000",
        "codec": "linear16",
        "channels": "1",
        "source": "desktop",
        "transient_only": "true",
      ]
    )
    XCTAssertNil(query["client_conversation_id"])
    XCTAssertNil(query["include_speech_profile"])
    XCTAssertNil(query["vad_threshold"])
    XCTAssertNil(query["stt_provider"])
  }

  func testConversationListenRequestKeepsOnlyAuthAndCoarsePlatformIdentity() throws {
    let service = try TranscriptionService(language: "en", mode: .conversation)

    let request = try service.makeBackendWebSocketRequest(
      base: "https://api.example.test/",
      authHeader: "Bearer token"
    )

    XCTAssertEqual(request.url?.scheme, "wss")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Platform"), "macos")
    XCTAssertNil(request.value(forHTTPHeaderField: "X-Device-Id-Hash"))
    XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Version"))
  }

  // MARK: - BackendSegment Decoding

  func testDecodeSegmentWithAllFields() throws {
    let json = """
      [{"id":"seg-1","text":"hello world","speaker":"SPEAKER_00","speaker_id":0,"is_user":true,"start":1.5,"end":3.2}]
      """
    let data = json.data(using: .utf8)!
    let segments = try JSONDecoder().decode([TranscriptionService.BackendSegment].self, from: data)

    XCTAssertEqual(segments.count, 1)
    let seg = segments[0]
    XCTAssertEqual(seg.id, "seg-1")
    XCTAssertEqual(seg.text, "hello world")
    XCTAssertEqual(seg.speaker, "SPEAKER_00")
    XCTAssertEqual(seg.speaker_id, 0)
    XCTAssertTrue(seg.is_user)
    XCTAssertEqual(seg.start, 1.5)
    XCTAssertEqual(seg.end, 3.2)
  }

  func testDecodeSegmentWithNullOptionals() throws {
    let json = """
      [{"id":null,"text":"test","speaker":null,"speaker_id":null,"is_user":false,"start":0.0,"end":1.0}]
      """
    let data = json.data(using: .utf8)!
    let segments = try JSONDecoder().decode([TranscriptionService.BackendSegment].self, from: data)

    XCTAssertEqual(segments.count, 1)
    let seg = segments[0]
    XCTAssertNil(seg.id)
    XCTAssertNil(seg.speaker)
    XCTAssertNil(seg.speaker_id)
    XCTAssertFalse(seg.is_user)
  }

  func testDecodeMultipleSegments() throws {
    let json = """
      [
          {"id":"s1","text":"first","speaker":"SPEAKER_00","speaker_id":0,"is_user":true,"start":0.0,"end":1.0},
          {"id":"s2","text":"second","speaker":"SPEAKER_01","speaker_id":1,"is_user":false,"start":1.0,"end":2.5}
      ]
      """
    let data = json.data(using: .utf8)!
    let segments = try JSONDecoder().decode([TranscriptionService.BackendSegment].self, from: data)

    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments[0].speaker_id, 0)
    XCTAssertTrue(segments[0].is_user)
    XCTAssertEqual(segments[1].speaker_id, 1)
    XCTAssertFalse(segments[1].is_user)
  }

  func testDecodeEmptySegmentArray() throws {
    let json = "[]"
    let data = json.data(using: .utf8)!
    let segments = try JSONDecoder().decode([TranscriptionService.BackendSegment].self, from: data)
    XCTAssertTrue(segments.isEmpty)
  }

  // MARK: - parseBackendResponse: Callback Dispatch

  /// Helper: create a TranscriptionService and wire its callbacks for testing.
  private func makeServiceWithCallbacks(
    onSegments: @escaping ([TranscriptionService.BackendSegment]) -> Void,
    onEvent: @escaping (TranscriptionService.ListenEvent) -> Void
  ) -> TranscriptionService? {
    guard let service = try? TranscriptionService(language: "en") else { return nil }
    service.start(
      onSegments: onSegments,
      onEvent: onEvent,
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )
    return service
  }

  func testParserDispatchesSegmentCallback() throws {
    var receivedSegments: [TranscriptionService.BackendSegment] = []
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { receivedSegments = $0 },
      onEvent: { _ in },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    let json = """
      [{"id":"s1","text":"hello","speaker":"SPEAKER_00","speaker_id":0,"is_user":true,"start":0.0,"end":1.5}]
      """
    service.parseBackendResponse(json)

    XCTAssertEqual(receivedSegments.count, 1)
    XCTAssertEqual(receivedSegments[0].id, "s1")
    XCTAssertEqual(receivedSegments[0].text, "hello")
    XCTAssertTrue(receivedSegments[0].is_user)
  }

  func testParserDispatchesEventCallback() throws {
    var receivedEvent: TranscriptionService.ListenEvent?
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in },
      onEvent: { receivedEvent = $0 },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    let json = """
      {"type":"service_status","status":"ready"}
      """
    service.parseBackendResponse(json)

    XCTAssertEqual(receivedEvent?.type, "service_status")
    XCTAssertEqual(receivedEvent?.raw["status"] as? String, "ready")
  }

  func testParserIgnoresPingHeartbeat() throws {
    var segmentsCalled = false
    var eventCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in segmentsCalled = true },
      onEvent: { _ in eventCalled = true },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    service.parseBackendResponse("ping")
    service.parseBackendResponse("  ping  \n")

    XCTAssertFalse(segmentsCalled, "ping should not trigger segments callback")
    XCTAssertFalse(eventCalled, "ping should not trigger event callback")
  }

  func testParserIgnoresEmptySegmentArray() throws {
    var segmentsCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in segmentsCalled = true },
      onEvent: { _ in },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    service.parseBackendResponse("[]")

    XCTAssertFalse(segmentsCalled, "empty array should not trigger segments callback")
  }

  func testParserHandlesInvalidJsonGracefully() throws {
    var segmentsCalled = false
    var eventCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in segmentsCalled = true },
      onEvent: { _ in eventCalled = true },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    service.parseBackendResponse("not json at all")
    service.parseBackendResponse("{invalid json")
    service.parseBackendResponse("")

    XCTAssertFalse(segmentsCalled)
    XCTAssertFalse(eventCalled)
  }

  func testParserIgnoresObjectWithoutType() throws {
    var eventCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in },
      onEvent: { _ in eventCalled = true },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    // JSON object without "type" field should be silently ignored
    service.parseBackendResponse(
      """
      {"data":"something","value":42}
      """)

    XCTAssertFalse(eventCalled, "object without type should not trigger event callback")
  }

  // MARK: - Parser Boundary Tests

  func testParserHandlesArrayOfInvalidSegments() throws {
    // Valid JSON array but objects don't match BackendSegment schema
    var segmentsCalled = false
    var eventCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in segmentsCalled = true },
      onEvent: { _ in eventCalled = true },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    // Array of objects missing required fields (text, is_user, start, end)
    service.parseBackendResponse(
      """
      [{"foo":"bar","baz":123}]
      """)

    XCTAssertFalse(segmentsCalled, "array with non-decodable objects should not trigger segments")
    XCTAssertFalse(eventCalled)
  }

  func testParserHandlesJsonNumber() throws {
    // Plain number is valid JSON but not array or object
    var segmentsCalled = false
    var eventCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in segmentsCalled = true },
      onEvent: { _ in eventCalled = true },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    service.parseBackendResponse("42")
    service.parseBackendResponse("\"just a string\"")

    XCTAssertFalse(segmentsCalled)
    XCTAssertFalse(eventCalled)
  }

  func testParserHandlesUnknownEventType() throws {
    var receivedEvent: TranscriptionService.ListenEvent?
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in },
      onEvent: { receivedEvent = $0 },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    // Unknown event type should still be dispatched
    service.parseBackendResponse(
      """
      {"type":"future_event_type","data":"something"}
      """)

    XCTAssertEqual(receivedEvent?.type, "future_event_type")
    XCTAssertEqual(receivedEvent?.raw["data"] as? String, "something")
  }

  // MARK: - Reconnection State Machine

  func testHandleDisconnectionRequiresConnected() throws {
    let service = try TranscriptionService(language: "en")
    // Not connected — handleDisconnection should be a no-op
    service.isConnected = false
    service.shouldReconnect = true
    service.reconnectAttempts = 0

    service.handleDisconnection()

    // reconnectAttempts should NOT increment — guard blocked the call
    XCTAssertEqual(service.reconnectAttempts, 0)
  }

  func testHandleDisconnectionIncrementsAttempts() throws {
    let service = try TranscriptionService(language: "en")
    service.isConnected = true
    service.shouldReconnect = true
    service.reconnectAttempts = 0

    service.handleDisconnection()

    XCTAssertFalse(service.isConnected)
    XCTAssertEqual(service.reconnectAttempts, 1)
  }

  func testCleanupAndReconnectWorksWhenNotConnected() throws {
    let service = try TranscriptionService(language: "en")
    // Pre-connect state — isConnected is false
    service.isConnected = false
    service.shouldReconnect = true
    service.reconnectAttempts = 0

    service.cleanupAndReconnect()

    // Should increment attempts even though not connected
    XCTAssertEqual(service.reconnectAttempts, 1)
  }

  func testMaxReconnectAttemptsTriggersError() throws {
    var receivedError: Error?
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in },
      onEvent: { _ in },
      onError: { receivedError = $0 },
      onConnected: nil,
      onDisconnected: nil
    )

    // Set attempts to max
    service.reconnectAttempts = service.maxReconnectAttempts
    service.isConnected = true
    service.shouldReconnect = true

    service.handleDisconnection()

    XCTAssertNotNil(receivedError, "should trigger error when max attempts reached")
  }

  func testCleanupAndReconnectMaxAttemptsTriggersError() throws {
    var receivedError: Error?
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in },
      onEvent: { _ in },
      onError: { receivedError = $0 },
      onConnected: nil,
      onDisconnected: nil
    )

    service.reconnectAttempts = service.maxReconnectAttempts
    service.shouldReconnect = true

    service.cleanupAndReconnect()

    XCTAssertNotNil(receivedError, "should trigger error when max attempts reached (pre-connect)")
  }

  func testHandleDisconnectionCallsOnDisconnected() throws {
    var disconnectedCalled = false
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { _ in },
      onEvent: { _ in },
      onError: nil,
      onConnected: nil,
      onDisconnected: { disconnectedCalled = true }
    )

    service.isConnected = true
    service.shouldReconnect = false  // Don't attempt reconnect

    service.handleDisconnection()

    XCTAssertTrue(disconnectedCalled)
    XCTAssertFalse(service.isConnected)
  }

  // MARK: - Multi-Segment Dispatch

  func testParserDispatchesMultipleSegments() throws {
    var receivedSegments: [TranscriptionService.BackendSegment] = []
    let service = try TranscriptionService(language: "en")
    service.start(
      onSegments: { receivedSegments = $0 },
      onEvent: { _ in },
      onError: nil,
      onConnected: nil,
      onDisconnected: nil
    )

    let json = """
      [
          {"id":"s1","text":"hello","speaker":"SPEAKER_00","speaker_id":0,"is_user":true,"start":0.0,"end":1.0},
          {"id":"s2","text":"world","speaker":"SPEAKER_01","speaker_id":1,"is_user":false,"start":1.0,"end":2.0}
      ]
      """
    service.parseBackendResponse(json)

    XCTAssertEqual(receivedSegments.count, 2)
    XCTAssertEqual(receivedSegments[0].text, "hello")
    XCTAssertEqual(receivedSegments[1].text, "world")
  }
}
