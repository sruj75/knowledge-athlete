import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

final class ConversationIngestionTests: XCTestCase {
  func testAudioSinkBuffersAcrossProducerHandoffAndReplaysToOnlyTheNewProducer() {
    let sink = LocalTranscriptionAudioSink()
    let previous = LocalAudioReceiverStub()
    let next = LocalAudioReceiverStub()
    let first = Data([1])
    let duringHandoff = Data([2])

    sink.completeHandoff(to: previous)
    sink.append(first)
    sink.beginHandoff()
    sink.append(duringHandoff)
    sink.completeHandoff(to: next)

    XCTAssertEqual(previous.values, [first])
    XCTAssertEqual(next.values, [duringHandoff])
  }

  func testAudioSinkWaitsForAnAdmittedAppendBeforeHandoffReturns() {
    let sink = LocalTranscriptionAudioSink()
    let previous = BlockingLocalAudioReceiverStub()
    let value = Data([1])
    let appendReturned = DispatchSemaphore(value: 0)
    let handoffAttempted = DispatchSemaphore(value: 0)
    let handoffReturned = DispatchSemaphore(value: 0)

    sink.completeHandoff(to: previous)
    DispatchQueue.global().async {
      sink.append(value)
      appendReturned.signal()
    }
    XCTAssertEqual(previous.firstAppendStarted.wait(timeout: .now() + 1), .success)

    DispatchQueue.global().async {
      handoffAttempted.signal()
      sink.beginHandoff()
      handoffReturned.signal()
    }
    XCTAssertEqual(handoffAttempted.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(handoffReturned.wait(timeout: .now() + 0.2), .timedOut)

    previous.releaseFirstAppend()
    XCTAssertEqual(appendReturned.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(handoffReturned.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(previous.snapshot(), [value])
  }

  func testAudioSinkReplaysBufferedAudioBeforePublishingTheNewReceiver() {
    let sink = LocalTranscriptionAudioSink()
    let next = BlockingLocalAudioReceiverStub()
    let bufferedValue = Data([1])
    let liveValue = Data([2])
    let handoffReturned = DispatchSemaphore(value: 0)
    let liveAppendAttempted = DispatchSemaphore(value: 0)
    let liveAppendReturned = DispatchSemaphore(value: 0)

    sink.beginHandoff()
    sink.append(bufferedValue)
    DispatchQueue.global().async {
      sink.completeHandoff(to: next)
      handoffReturned.signal()
    }
    XCTAssertEqual(next.firstAppendStarted.wait(timeout: .now() + 1), .success)

    DispatchQueue.global().async {
      liveAppendAttempted.signal()
      sink.append(liveValue)
      liveAppendReturned.signal()
    }
    XCTAssertEqual(liveAppendAttempted.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(liveAppendReturned.wait(timeout: .now() + 0.2), .timedOut)

    next.releaseFirstAppend()
    XCTAssertEqual(handoffReturned.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(liveAppendReturned.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(next.snapshot(), [bufferedValue, liveValue])
  }

  func testEquivalentProducersUseOneStableIdempotentLocalShapeAndSnapshotPreferences() async throws {
    let ownerA = try makeStorage()
    let ownerB = try makeStorage()
    defer {
      try? ownerA.pool.close()
      try? ownerB.pool.close()
      try? FileManager.default.removeItem(at: ownerA.directory)
      try? FileManager.default.removeItem(at: ownerB.directory)
    }

    var configuration = ConversationCaptureConfiguration(
      language: "fr",
      autoDetectLanguage: true,
      vocabulary: ["Omi", "Hypermind"],
      timezone: "Europe/Paris",
      inputDeviceName: "Studio Mic",
      location: ConversationLocationSnapshot(latitude: 48.8566, longitude: 2.3522, label: nil))
    let conversationA = try await ownerA.storage.beginConversation(configuration: configuration)
    let conversationB = try await ownerB.storage.beginConversation(configuration: configuration)
    XCTAssertNotNil(UUID(uuidString: conversationA.conversationId))
    XCTAssertNotNil(UUID(uuidString: conversationB.conversationId))

    let incoming = [
      ConversationSegmentInput(
        segmentId: "30000000-0000-4000-8000-000000000001",
        speakerId: 0,
        text: " Hello  , world . ",
        startTime: 0,
        endTime: 1,
        isUser: true,
        translations: [ConversationSegmentTranslation(language: "fr", text: "Bonjour")])
    ]
    try await ownerA.storage.upsertSegments(conversationId: conversationA.conversationId, segments: incoming)
    try await ownerB.storage.upsertSegments(conversationId: conversationB.conversationId, segments: incoming)

    var correction = incoming[0]
    correction.text = "Hello, corrected world."
    try await ownerA.storage.upsertSegments(conversationId: conversationA.conversationId, segments: [correction])

    configuration.language = "de"
    configuration.vocabulary = ["changed"]
    let loadedA = try await ownerA.storage.conversationDetail(id: conversationA.conversationId)
    let loadedB = try await ownerB.storage.conversationDetail(id: conversationB.conversationId)
    let detailA = try XCTUnwrap(loadedA)
    let detailB = try XCTUnwrap(loadedB)

    XCTAssertEqual(detailA.language, "fr")
    XCTAssertEqual(detailA.timezone, "Europe/Paris")
    XCTAssertEqual(detailA.inputDeviceName, "Studio Mic")
    XCTAssertTrue(detailA.autoDetectLanguage)
    XCTAssertEqual(detailA.vocabulary, ["Omi", "Hypermind"])
    XCTAssertEqual(detailA.location?.latitude, 48.8566)
    XCTAssertEqual(detailA.segments.count, 1)
    XCTAssertEqual(detailA.segments[0].segmentId, incoming[0].segmentId)
    XCTAssertEqual(detailA.segments[0].speakerId, 0)
    XCTAssertEqual(detailA.segments[0].text, "Hello, corrected world.")
    XCTAssertEqual(detailA.segments[0].translations, incoming[0].translations)

    XCTAssertEqual(detailB.segments.map(\.speakerId), [0])
    XCTAssertEqual(detailB.segments.map(\.text), ["Hello, world."])
    XCTAssertEqual(detailB.segments.map(\.translations), [incoming[0].translations])
  }

  func testMissingProviderIdBecomesDeterministicAndRepeatedDeliveryDoesNotDuplicate() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let conversation = try await owner.storage.beginConversation(configuration: .testDefault)
    let input = ConversationSegmentInput(
      segmentId: nil, speakerId: 2, text: "stable", startTime: 4, endTime: 5, isUser: false, translations: [])

    try await owner.storage.upsertSegments(conversationId: conversation.conversationId, segments: [input])
    try await owner.storage.upsertSegments(conversationId: conversation.conversationId, segments: [input])

    let loaded = try await owner.storage.conversationDetail(id: conversation.conversationId)
    let detail = try XCTUnwrap(loaded)
    XCTAssertEqual(detail.segments.count, 1)
    XCTAssertNotNil(UUID(uuidString: detail.segments[0].segmentId))
  }

  func testTransientTranslationAttachesOnlyToTheRequestedLocalSegment() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let conversation = try await owner.storage.beginConversation(configuration: .testDefault)
    let firstId = "40000000-0000-4000-8000-000000000001"
    let secondId = "40000000-0000-4000-8000-000000000002"
    try await owner.storage.upsertSegments(
      sessionId: conversation.sessionId,
      segments: [
        ConversationSegmentInput(
          segmentId: firstId, speakerId: 0, text: "First.", startTime: 0, endTime: 1,
          isUser: false, translations: []),
        ConversationSegmentInput(
          segmentId: secondId, speakerId: 1, text: "Second.", startTime: 2, endTime: 3,
          isUser: false, translations: []),
      ])

    try await owner.storage.attachTranslation(
      sessionId: conversation.sessionId,
      segmentId: secondId,
      translation: ConversationSegmentTranslation(language: "es", text: "Segundo."),
      authorization: .unrestricted)

    let loaded = try await owner.storage.conversationDetail(id: conversation.conversationId)
    let detail = try XCTUnwrap(loaded)
    XCTAssertEqual(detail.segments.first { $0.segmentId == firstId }?.translations, [])
    XCTAssertEqual(
      detail.segments.first { $0.segmentId == secondId }?.translations,
      [ConversationSegmentTranslation(language: "es", text: "Segundo.")])
  }

  func testRedeliveryAndCorrectionOfJoinedFragmentRemainIdempotent() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let conversation = try await owner.storage.beginConversation(configuration: .testDefault)
    let first = ConversationSegmentInput(
      segmentId: "60000000-0000-4000-8000-000000000001", speakerId: 0,
      text: "hello", startTime: 0, endTime: 1, isUser: true, translations: [])
    var folded = ConversationSegmentInput(
      segmentId: "60000000-0000-4000-8000-000000000002", speakerId: 0,
      text: "world.", startTime: 1, endTime: 2, isUser: true, translations: [])

    try await owner.storage.upsertSegments(
      conversationId: conversation.conversationId, segments: [first, folded])
    try await owner.storage.upsertSegments(
      conversationId: conversation.conversationId, segments: [folded])
    let redelivered = try await owner.storage.conversationDetail(id: conversation.conversationId)
    XCTAssertEqual(redelivered?.segments.map(\.text), ["hello world."])

    folded.text = "there."
    try await owner.storage.upsertSegments(
      conversationId: conversation.conversationId, segments: [folded])

    let corrected = try await owner.storage.conversationDetail(id: conversation.conversationId)
    XCTAssertEqual(corrected?.segments.map(\.text), ["hello there."])
  }

  func testOrderedAsyncOperationQueueDrainsRegisteredTailInOrder() async {
    let queue = OrderedAsyncOperationQueue()
    let recorder = OrderedOperationRecorder()

    queue.submit { await recorder.recordFirstAfterRelease() }
    await recorder.waitUntilFirstStarted()
    queue.submit { await recorder.recordSecond() }

    let drain = Task { await queue.drain() }
    await recorder.releaseFirst()
    await drain.value

    let values = await recorder.values()
    XCTAssertEqual(values, [1, 2])
  }

  func testLateLocationSnapshotCannotMutateFinishedConversation() async throws {
    let owner = try makeStorage()
    defer {
      try? owner.pool.close()
      try? FileManager.default.removeItem(at: owner.directory)
    }
    let handle = try await owner.storage.beginConversation(configuration: .testDefault)
    let admitted = try await owner.storage.setConversationLocation(
      id: handle.conversationId,
      location: ConversationLocationSnapshot(latitude: 1, longitude: 2, label: "Initial"),
      authorization: .unrestricted)
    XCTAssertTrue(admitted)

    _ = try await owner.storage.finishConversation(sessionId: handle.sessionId, reason: .userStop)
    let late = try await owner.storage.setConversationLocation(
      id: handle.conversationId,
      location: ConversationLocationSnapshot(latitude: 3, longitude: 4, label: "Late"),
      authorization: .unrestricted)

    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    XCTAssertFalse(late)
    XCTAssertEqual(detail?.location?.label, "Initial")
  }

  private func makeStorage() throws -> (directory: URL, pool: DatabasePool, storage: TranscriptionStorage) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationIngestionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return (directory, pool, TranscriptionStorage(databasePool: pool))
  }
}

private final class LocalAudioReceiverStub: LocalTranscriptionAudioReceiving, @unchecked Sendable {
  private(set) var values: [Data] = []

  func appendAudio(_ data: Data) {
    values.append(data)
  }
}

private final class BlockingLocalAudioReceiverStub: LocalTranscriptionAudioReceiving, @unchecked Sendable {
  let firstAppendStarted = DispatchSemaphore(value: 0)

  private let lock = NSLock()
  private let firstAppendRelease = DispatchSemaphore(value: 0)
  private var hasStartedFirstAppend = false
  private var values: [Data] = []

  func appendAudio(_ data: Data) {
    let isFirstAppend = lock.withLock {
      guard !hasStartedFirstAppend else { return false }
      hasStartedFirstAppend = true
      return true
    }
    if isFirstAppend {
      firstAppendStarted.signal()
      firstAppendRelease.wait()
    }
    lock.withLock {
      values.append(data)
    }
  }

  func releaseFirstAppend() {
    firstAppendRelease.signal()
  }

  func snapshot() -> [Data] {
    lock.withLock { values }
  }
}

private actor OrderedOperationRecorder {
  private var recordedValues: [Int] = []
  private var firstStarted = false
  private var firstRelease: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func recordFirstAfterRelease() async {
    firstStarted = true
    startWaiters.forEach { $0.resume() }
    startWaiters.removeAll()
    await withCheckedContinuation { firstRelease = $0 }
    recordedValues.append(1)
  }

  func recordSecond() {
    recordedValues.append(2)
  }

  func waitUntilFirstStarted() async {
    guard !firstStarted else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func releaseFirst() {
    firstRelease?.resume()
    firstRelease = nil
  }

  func values() -> [Int] { recordedValues }
}
