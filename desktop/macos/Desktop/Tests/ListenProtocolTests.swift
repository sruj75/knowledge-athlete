import XCTest

@testable import Omi_Computer

final class ListenProtocolTests: XCTestCase {
  func testConversationURLCarriesOnlyImmutableSnapshot() throws {
    let service = try TranscriptionService(
      language: "multi",
      mode: .conversation,
      translationTarget: "es",
      vocabulary: ["Omi", "Knowledge Athlete"])

    let url = try service.makeBackendWebSocketURL(base: "wss://api.example.test")
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = components.queryItems ?? []

    XCTAssertEqual(components.path, "/v4/listen")
    XCTAssertEqual(queryItems.filter { $0.name == "language" }.compactMap { $0.value }, ["auto"])
    XCTAssertEqual(queryItems.filter { $0.name == "translation_target" }.compactMap { $0.value }, ["es"])
    XCTAssertEqual(
      queryItems.filter { $0.name == "vocabulary" }.compactMap { $0.value },
      ["Omi", "Knowledge Athlete"])
    XCTAssertEqual(Set(queryItems.map { $0.name }), ["language", "translation_target", "vocabulary"])
  }

  func testConversationRequestKeepsOnlyAuthAndCoarsePlatformIdentity() throws {
    let service = try TranscriptionService(language: "en", mode: .conversation)
    let request = try service.makeBackendWebSocketRequest(
      base: "https://api.example.test/", authHeader: "Bearer token")

    XCTAssertEqual(request.url?.scheme, "wss")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Platform"), "macos")
    XCTAssertNil(request.value(forHTTPHeaderField: "X-Device-Id-Hash"))
    XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Version"))
  }

  func testConversationVocabularyKeepsTheProductCapBelowTheProviderCeiling() {
    XCTAssertThrowsError(
      try TranscriptionService(
        language: "en", mode: .conversation,
        vocabulary: (0...100).map { "term-\($0)" }))
  }

  func testParserDispatchesRequiredCanonicalSegmentsEnvelope() throws {
    var received: [TranscriptionService.BackendSegment] = []
    let service = try wiredConversationService(onSegments: { received = $0 })

    service.parseBackendResponse(
      """
      {"type":"segments","segments":[
        {"segmentId":"a1b2c3d4-e5f6-4890-abcd-ef1234567890","speakerId":1,"text":"hello","start":0.0,"end":1.5}
      ]}
      """)

    XCTAssertEqual(received.count, 1)
    XCTAssertEqual(received[0].segmentId, "a1b2c3d4-e5f6-4890-abcd-ef1234567890")
    XCTAssertEqual(received[0].speakerId, 1)
    XCTAssertEqual(received[0].text, "hello")
    XCTAssertFalse(received[0].isUser)
  }

  func testParserRejectsLegacyOrExtraHostedSegmentFields() throws {
    var segmentCalls = 0
    let service = try wiredConversationService(onSegments: { _ in segmentCalls += 1 })
    service.parseBackendResponse(
      """
      {"type":"segments","segments":[
        {"id":"legacy","segmentId":"a1b2c3d4-e5f6-4890-abcd-ef1234567890","speakerId":0,"speaker":"SPEAKER_00","is_user":true,"text":"hello","start":0.0,"end":1.0}
      ]}
      """)
    service.parseBackendResponse(
      """
      {"type":"segments","segments":[{"speakerId":0,"text":"missing UUID","start":0.0,"end":1.0}]}
      """)

    XCTAssertEqual(segmentCalls, 0)
  }

  func testParserDispatchesOnlyRetainedListenEvents() throws {
    var eventTypes: [String] = []
    let service = try wiredConversationService(onEvent: { eventTypes.append($0.type) })

    service.parseBackendResponse("{\"type\":\"service_status\",\"status\":\"ready\"}")
    service.parseBackendResponse(
      "{\"type\":\"service_status\",\"status\":\"stt_failed\",\"status_text\":\"Unavailable\",\"outcome\":\"upstream_error\",\"provider\":\"modulate\",\"retryable\":true,\"reason\":\"initialization_failed\"}"
    )
    service.parseBackendResponse(
      "{\"type\":\"translation\",\"segmentId\":\"a1b2c3d4-e5f6-4890-abcd-ef1234567890\",\"language\":\"es\",\"text\":\"hola\"}"
    )
    service.parseBackendResponse(
      "{\"type\":\"freemium_threshold_reached\",\"remaining_seconds\":120,\"action\":\"setup_on_device_stt\"}")
    service.parseBackendResponse(
      """
      {"type":"fair_use_review_requested","review_id":"11111111-1111-4111-8111-111111111111","trigger":"daily","window_speech_ms":{"daily_ms":7200001,"three_day_ms":7200001,"weekly_ms":7200001},"thresholds_ms":{"daily_ms":7200000,"three_day_ms":28800000,"weekly_ms":36000000},"classifier_contract":"gemini/gemini-3.7-flash:prompt-v2","requested_at":"2026-08-21T08:00:00Z","expires_at":"2026-08-21T20:00:00Z"}
      """)
    service.parseBackendResponse(
      """
      {"type":"fair_use_managed_cloud_exhausted","resets_at":"2026-08-22T00:00:00Z","case_ref":"FU-ABC123DEF456","support_email":"support@heyintentive.com"}
      """)
    service.parseBackendResponse("{\"type\":\"conversation_session\",\"conversation_id\":\"forbidden\"}")
    service.parseBackendResponse("{\"type\":\"speaker_label_suggestion\",\"speaker_id\":0}")
    service.parseBackendResponse("{\"type\":\"future_event\"}")

    XCTAssertEqual(
      eventTypes,
      [
        "service_status", "service_status", "translation", "freemium_threshold_reached",
        "fair_use_review_requested", "fair_use_managed_cloud_exhausted",
      ])
  }

  func testManagedCloudExhaustionParserRejectsExtraContentAndWrongSupportDestination() throws {
    var eventCalls = 0
    let service = try wiredConversationService(onEvent: { _ in eventCalls += 1 })
    let base =
      """
      {"type":"fair_use_managed_cloud_exhausted","resets_at":"2026-08-22T00:00:00Z","case_ref":"FU-ABC123DEF456","support_email":"support@heyintentive.com"
      """

    service.parseBackendResponse(base + ",\"title\":\"must not cross\"}")
    service.parseBackendResponse(
      """
      {"type":"fair_use_managed_cloud_exhausted","resets_at":"2026-08-22T00:00:00Z","case_ref":"FU-ABC123DEF456","support_email":"wrong@example.com"}
      """)

    XCTAssertEqual(eventCalls, 0)
  }

  func testFairUseReviewParserRejectsExtraContentAndServerOwnedPolicyFields() throws {
    var eventCalls = 0
    let service = try wiredConversationService(onEvent: { _ in eventCalls += 1 })
    let base =
      """
      {"type":"fair_use_review_requested","review_id":"11111111-1111-4111-8111-111111111111","trigger":"daily","window_speech_ms":{"daily_ms":7200001,"three_day_ms":7200001,"weekly_ms":7200001},"thresholds_ms":{"daily_ms":7200000,"three_day_ms":28800000,"weekly_ms":36000000},"classifier_contract":"gemini/gemini-3.7-flash:prompt-v2","requested_at":"2026-08-21T08:00:00Z","expires_at":"2026-08-21T20:00:00Z"
      """

    service.parseBackendResponse(base + ",\"title\":\"must not cross\"}")
    service.parseBackendResponse(base + ",\"score\":1.0}")
    service.parseBackendResponse(base + ",\"uid\":\"owner-a\"}")

    XCTAssertEqual(eventCalls, 0)
  }

  func testParserIgnoresHeartbeatAndMalformedPayloads() throws {
    var segmentCalls = 0
    var eventCalls = 0
    let service = try wiredConversationService(
      onSegments: { _ in segmentCalls += 1 }, onEvent: { _ in eventCalls += 1 })

    for payload in ["ping", "  ping  \n", "", "not json", "[]", "42", "{\"data\":1}"] {
      service.parseBackendResponse(payload)
    }

    XCTAssertEqual(segmentCalls, 0)
    XCTAssertEqual(eventCalls, 0)
  }

  func testPTTArrayContractRemainsIntact() throws {
    var received: [TranscriptionService.BackendSegment] = []
    let service = try TranscriptionService(language: "en", mode: .ptt)
    service.start(onSegments: { received = $0 }, onEvent: { _ in })

    service.parseBackendResponse(
      """
      [{"id":"ptt-1","text":"voice command","speaker":"SPEAKER_00","speaker_id":0,"is_user":true,"start":0.0,"end":1.0}]
      """)

    XCTAssertEqual(received.map(\.text), ["voice command"])
  }

  func testHandleDisconnectionPreservesReconnectStateMachine() throws {
    let service = try TranscriptionService(language: "en")
    service.isConnected = true
    service.shouldReconnect = true
    service.reconnectAttempts = 0

    service.handleDisconnection()

    XCTAssertFalse(service.isConnected)
    XCTAssertEqual(service.reconnectAttempts, 1)
  }

  func testFairUseQuiesceRetainsSocketButDisablesAudioAndReconnectOwnership() throws {
    let service = try TranscriptionService(language: "en")
    service.isConnected = true
    service.shouldReconnect = true
    service.reconnectAttempts = 0

    service.quiesceManagedCloudAudioForFairUse()

    XCTAssertTrue(service.isConnected)
    XCTAssertTrue(service.managedCloudAudioQuiesced)
    XCTAssertFalse(service.shouldReconnect)
    service.handleDisconnection()
    XCTAssertEqual(service.reconnectAttempts, 0)
  }

  func testReconnectExhaustionSurfacesError() throws {
    var receivedError: Error?
    let service = try TranscriptionService(language: "en")
    service.start(onSegments: { _ in }, onEvent: { _ in }, onError: { receivedError = $0 })
    service.reconnectAttempts = service.maxReconnectAttempts
    service.isConnected = true
    service.shouldReconnect = true

    service.handleDisconnection()

    XCTAssertNotNil(receivedError)
  }

  private func wiredConversationService(
    onSegments: @escaping ([TranscriptionService.BackendSegment]) -> Void = { _ in },
    onEvent: @escaping (TranscriptionService.ListenEvent) -> Void = { _ in }
  ) throws -> TranscriptionService {
    let service = try TranscriptionService(language: "en", mode: .conversation)
    service.start(onSegments: onSegments, onEvent: onEvent)
    return service
  }
}
