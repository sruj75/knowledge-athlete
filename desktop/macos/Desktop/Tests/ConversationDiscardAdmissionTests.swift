import Foundation
import GRDB
import XCTest

@testable import Omi_Computer

private actor DiscardComputerStub: ConversationDiscardComputing {
  enum Behavior: Sendable {
    case decision(Bool)
    case failure
  }

  private let behavior: Behavior
  private(set) var requests: [ConversationDiscardComputeRequest] = []

  init(_ behavior: Behavior) {
    self.behavior = behavior
  }

  func computeDiscard(
    _ request: ConversationDiscardComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationDiscardComputeResponse {
    requests.append(request)
    switch behavior {
    case .decision(let discard):
      return ConversationDiscardComputeResponse(generationId: request.generationId, discard: discard)
    case .failure:
      throw APIError.invalidResponse
    }
  }

  func callCount() -> Int { requests.count }
}

private actor BlockingDiscardComputer: ConversationDiscardComputing {
  private var request: ConversationDiscardComputeRequest?
  private var requestWaiters: [CheckedContinuation<ConversationDiscardComputeRequest, Never>] = []
  private var responseContinuation: CheckedContinuation<ConversationDiscardComputeResponse, Never>?

  func computeDiscard(
    _ request: ConversationDiscardComputeRequest,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot?
  ) async throws -> ConversationDiscardComputeResponse {
    self.request = request
    requestWaiters.forEach { $0.resume(returning: request) }
    requestWaiters.removeAll()
    return await withCheckedContinuation { responseContinuation = $0 }
  }

  func waitForRequest() async -> ConversationDiscardComputeRequest {
    if let request { return request }
    return await withCheckedContinuation { requestWaiters.append($0) }
  }

  func reply(discard: Bool) {
    guard let request else { return }
    responseContinuation?.resume(
      returning: ConversationDiscardComputeResponse(generationId: request.generationId, discard: discard))
    responseContinuation = nil
  }
}

final class ConversationDiscardAdmissionTests: XCTestCase {
  func testEmptyTranscriptDeletesLocallyWithoutComputeOrDerivations() async throws {
    let owner = try makeStorage()
    defer { owner.cleanup() }
    let handle = try await finishedConversation(owner.storage, text: nil)
    let computer = DiscardComputerStub(.decision(false))
    let admission = ConversationDiscardAdmission(
      storage: owner.storage, computer: computer, requiresOwnerAuthorization: false)

    let result = await admission.process(conversationId: handle.conversationId)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)
    let callCount = await computer.callCount()

    XCTAssertEqual(result, .deleted)
    XCTAssertNil(detail)
    XCTAssertEqual(work, [])
    XCTAssertEqual(callCount, 0)
  }

  func testMoreThanOneHundredWordsKeepsWithoutComputeAndAdmitsIndependentWork() async throws {
    let owner = try makeStorage()
    defer { owner.cleanup() }
    let transcript = (0...100).map { "word-\($0)" }.joined(separator: " ")
    let handle = try await finishedConversation(owner.storage, text: transcript)
    let computer = DiscardComputerStub(.decision(true))
    let admission = ConversationDiscardAdmission(
      storage: owner.storage, computer: computer, requiresOwnerAuthorization: false)

    let result = await admission.process(conversationId: handle.conversationId)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let callCount = await computer.callCount()
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(result, .kept)
    XCTAssertNotNil(detail)
    XCTAssertEqual(callCount, 0)
    XCTAssertEqual(work.map(\.kind), [.discard, .structure, .actionItems])
    XCTAssertEqual(work.map(\.state), [.succeeded, .pending, .pending])
  }

  func testAffirmativeCurrentGenerationDeletesAndCreatesNoDerivations() async throws {
    let owner = try makeStorage()
    defer { owner.cleanup() }
    let handle = try await finishedConversation(owner.storage, text: "okay")
    let computer = DiscardComputerStub(.decision(true))
    let admission = ConversationDiscardAdmission(
      storage: owner.storage, computer: computer, requiresOwnerAuthorization: false)

    let result = await admission.process(conversationId: handle.conversationId)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let callCount = await computer.callCount()

    XCTAssertEqual(result, .deleted)
    XCTAssertNil(detail)
    XCTAssertEqual(callCount, 1)
  }

  func testClassifierFailureKeepsAndTerminalAttemptDoesNotRunAgain() async throws {
    let owner = try makeStorage()
    defer { owner.cleanup() }
    let handle = try await finishedConversation(owner.storage, text: "a useful reminder")
    let computer = DiscardComputerStub(.failure)
    let admission = ConversationDiscardAdmission(
      storage: owner.storage, computer: computer, requiresOwnerAuthorization: false)

    let first = await admission.process(conversationId: handle.conversationId)
    let second = await admission.process(conversationId: handle.conversationId)
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)
    let callCount = await computer.callCount()
    let work = try await owner.storage.enrichmentWork(conversationId: handle.conversationId)

    XCTAssertEqual(first, .failedKeep)
    XCTAssertEqual(second, .noPendingWork)
    XCTAssertNotNil(detail)
    XCTAssertEqual(callCount, 1)
    XCTAssertEqual(work.map(\.kind), [.discard, .structure, .actionItems])
    XCTAssertEqual(work.map(\.state), [.failed, .pending, .pending])
  }

  func testNewerContentGenerationFencesAffirmativeInFlightResponse() async throws {
    let owner = try makeStorage()
    defer { owner.cleanup() }
    let handle = try await finishedConversation(owner.storage, text: "keep the newer text")
    let computer = BlockingDiscardComputer()
    let admission = ConversationDiscardAdmission(
      storage: owner.storage, computer: computer, requiresOwnerAuthorization: false)

    let task = Task { await admission.process(conversationId: handle.conversationId) }
    _ = await computer.waitForRequest()
    try await owner.pool.write { database in
      try database.execute(
        sql: "UPDATE transcription_sessions SET contentGeneration = contentGeneration + 1 WHERE conversationId = ?",
        arguments: [handle.conversationId])
    }
    await computer.reply(discard: true)
    let result = await task.value
    let detail = try await owner.storage.conversationDetail(id: handle.conversationId)

    XCTAssertEqual(result, .stale)
    XCTAssertNotNil(detail)
  }

  private func finishedConversation(
    _ storage: TranscriptionStorage,
    text: String?
  ) async throws -> ConversationCaptureHandle {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let handle = try await storage.beginConversation(configuration: .testDefault, startedAt: startedAt)
    if let text {
      try await storage.upsertSegments(
        conversationId: handle.conversationId,
        segments: [
          ConversationSegmentInput(
            segmentId: nil, speakerId: 0, text: text, startTime: 0, endTime: 5, isUser: true,
            translations: [])
        ])
    }
    _ = try await storage.finishConversation(
      sessionId: handle.sessionId, reason: .userStop, finishedAt: startedAt.addingTimeInterval(5))
    return handle
  }

  private func makeStorage() throws -> StorageOwner {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConversationDiscardAdmissionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pool = try DatabasePool(path: directory.appendingPathComponent("omi.db").path)
    var migrator = DatabaseMigrator()
    RewindDatabase.registerConversationsLocalAuthoritativeMigration(on: &migrator)
    try migrator.migrate(pool)
    return StorageOwner(directory: directory, pool: pool, storage: TranscriptionStorage(databasePool: pool))
  }
}

private struct StorageOwner: @unchecked Sendable {
  let directory: URL
  let pool: DatabasePool
  let storage: TranscriptionStorage

  func cleanup() {
    try? pool.close()
    try? FileManager.default.removeItem(at: directory)
  }
}
