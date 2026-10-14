import XCTest

@testable import Omi_Computer

private final class ConversationSocketFixture: RealtimeRawWebSocketTransport, @unchecked Sendable {
  var onOpen: (() -> Void)?
  var onMessage: ((Data) -> Void)?
  var onClose: ((Int, String) -> Void)?
  var onError: ((RealtimeRawWebSocketFailure) -> Void)?
  private let lock = NSLock()
  private var sent: [String] = []
  private var queue: DispatchQueue?
  let setupSent = XCTestExpectation(description: "Live setup sent")
  var messages: [[String: Any]] {
    lock.withLock { sent.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } }
  }
  func install(_ queue: DispatchQueue) { lock.withLock { self.queue = queue } }
  func connect() { onOpen?() }
  func sendText(_ text: String, completion: (@Sendable (Error?) -> Void)?) {
    lock.withLock { sent.append(text) }
    if text.contains("\"setup\"") { setupSent.fulfill() }
    completion?(nil)
  }
  func emit(_ json: String) {
    let queue = lock.withLock { self.queue }
    queue?.async { self.onMessage?(Data(json.utf8)) }
  }
  func close() {}
  func closeAndWait() async {}
}

@MainActor
final class ConversationLiveSessionTests: XCTestCase {
  func testAutomaticVADAndOnlyFixedEndFunctionAndSilentIdleAppend() async throws {
    let socket = ConversationSocketFixture()
    let ready = expectation(description: "Ready")
    let session = ConversationLiveSession(
      token: "fixture", instructions: "pinned A",
      factory: { _, queue in
        socket.install(queue)
        return socket
      }
    ) { _, event in if case .ready = event { ready.fulfill() } }
    session.start()
    await fulfillment(of: [socket.setupSent], timeout: 2)
    let setup = try XCTUnwrap(socket.messages.first?["setup"] as? [String: Any])
    let input = try XCTUnwrap(setup["realtimeInputConfig"] as? [String: Any])
    XCTAssertEqual((input["automaticActivityDetection"] as? [String: Bool])?["disabled"], false)
    XCTAssertEqual(input["activityHandling"] as? String, "START_OF_ACTIVITY_INTERRUPTS")
    let tools = try XCTUnwrap(setup["tools"] as? [[String: Any]])
    let declarations = try XCTUnwrap(tools.first?["functionDeclarations"] as? [[String: Any]])
    XCTAssertEqual(declarations.compactMap { $0["name"] as? String }, ["end_conversation"])
    socket.emit("{\"setupComplete\":{}}")
    await fulfillment(of: [ready], timeout: 2)
    let appended = await session.appendPrivateContext("Private note")
    XCTAssertTrue(appended)
    let content = try XCTUnwrap(socket.messages.last?["clientContent"] as? [String: Any])
    XCTAssertEqual(content["turnComplete"] as? Bool, false)
    session.beginUserTurn("first")
    let activeAppend = await session.appendPrivateContext("Must wait")
    XCTAssertFalse(activeAppend)
    XCTAssertFalse(socket.messages.contains { ($0["realtimeInput"] as? [String: Any])?["activityStart"] != nil })
    session.stop()
  }

  func testBargeInDropsOldAudioUntilProviderInterruptionBoundary() async {
    let socket = ConversationSocketFixture()
    let ready = expectation(description: "Ready")
    let first = expectation(description: "First audio")
    let replacement = expectation(description: "Replacement audio")
    var outputs: [String] = []
    let session = ConversationLiveSession(
      token: "fixture", instructions: "pinned",
      factory: { _, queue in
        socket.install(queue)
        return socket
      }
    ) { _, event in
      switch event {
      case .ready: ready.fulfill()
      case .audio(let id, _):
        outputs.append(id)
        if id == "first" { first.fulfill() }
        if id == "second" { replacement.fulfill() }
      default: break
      }
    }
    session.start()
    await fulfillment(of: [socket.setupSent], timeout: 2)
    socket.emit("{\"setupComplete\":{}}")
    await fulfillment(of: [ready], timeout: 2)
    let audio =
      "{\"serverContent\":{\"modelTurn\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"audio/pcm;rate=24000\",\"data\":\"AAA=\"}}]}}}"
    session.beginUserTurn("first")
    socket.emit(audio)
    await fulfillment(of: [first], timeout: 2)
    session.beginUserTurn("second")
    socket.emit(audio)
    socket.emit("{\"serverContent\":{\"interrupted\":true}}")
    socket.emit(audio)
    await fulfillment(of: [replacement], timeout: 2)
    XCTAssertEqual(outputs, ["first", "second"])
    session.stop()
  }

  func testInterruptedTranscriptionIsQuarantinedAndUsageIsReportedOnce() async {
    let socket = ConversationSocketFixture()
    let ready = expectation(description: "Ready")
    let first = expectation(description: "First output")
    let finished = expectation(description: "Replacement finished")
    var transcripts: [String] = []
    var usage: [ConversationLiveSession.Usage] = []
    let session = ConversationLiveSession(
      token: "fixture", instructions: "pinned",
      factory: { _, queue in
        socket.install(queue)
        return socket
      }
    ) { _, event in
      switch event {
      case .ready: ready.fulfill()
      case .text(let id, _): if id == "first" { first.fulfill() }
      case .transcript(_, let text, _): transcripts.append(text)
      case .finished(let id): if id == "second" { finished.fulfill() }
      case .usage(let counts): usage.append(counts)
      default: break
      }
    }
    session.start()
    await fulfillment(of: [socket.setupSent], timeout: 2)
    socket.emit(#"{"setupComplete":{}}"#)
    await fulfillment(of: [ready], timeout: 2)
    session.beginUserTurn("first")
    socket.emit(#"{"serverContent":{"outputTranscription":{"text":"First answer"}}}"#)
    await fulfillment(of: [first], timeout: 2)
    session.beginUserTurn("second")
    socket.emit(#"{"serverContent":{"interrupted":true,"inputTranscription":{"text":"Late previous text"}}}"#)
    socket.emit(
      #"{"usageMetadata":{"promptTokenCount":10,"responseTokenCount":5},"serverContent":{"outputTranscription":{"text":"Next answer"}}}"#
    )
    socket.emit(
      #"{"usageMetadata":{"promptTokenCount":11,"responseTokenCount":6},"serverContent":{"inputTranscription":{"text":"Ambiguous input"},"turnComplete":true}}"#
    )
    await fulfillment(of: [finished], timeout: 2)
    XCTAssertTrue(transcripts.isEmpty)
    XCTAssertEqual(usage.count, 1)
    XCTAssertEqual(usage.first?.inputText, 11)
    XCTAssertEqual(usage.first?.outputText, 6)
    session.stop()
  }

  func testCachedPromptTokensAreExclusiveRatherThanDoubleCounted() {
    let usage = ConversationLiveSession.Usage([
      "promptTokenCount": 100, "cachedContentTokenCount": 60, "responseTokenCount": 10,
    ])
    XCTAssertEqual(usage.inputText, 40)
    XCTAssertEqual(usage.inputCached, 60)
    XCTAssertEqual(usage.inputText + usage.inputAudio + usage.inputCached + usage.outputText + usage.outputAudio, 110)
    let audio = ConversationLiveSession.Usage([
      "promptTokensDetails": [["modality": "TEXT", "tokenCount": 30], ["modality": "AUDIO", "tokenCount": 70]],
      "cacheTokensDetails": [["modality": "TEXT", "tokenCount": 10], ["modality": "AUDIO", "tokenCount": 50]],
      "cachedContentTokenCount": 60,
    ])
    XCTAssertEqual(audio.inputText, 20)
    XCTAssertEqual(audio.inputAudio, 20)
    XCTAssertEqual(audio.inputCached, 60)
  }

  func testThinkingTokensRemainSeparateFromResponseAndCachedInput() {
    let usage = ConversationLiveSession.Usage([
      "promptTokenCount": 100, "cachedContentTokenCount": 60, "responseTokenCount": 10,
      "thoughtsTokenCount": 7,
    ])
    XCTAssertEqual(usage.thinking, 7)
    XCTAssertEqual(
      usage.inputText + usage.inputAudio + usage.inputCached + usage.outputText + usage.outputAudio + usage.thinking,
      117)
  }

}
