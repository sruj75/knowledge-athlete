import FluidAudio
import XCTest

@testable import Omi_Computer

private actor LocalTranscriptionFailureProbe {
  private var observed: LocalTranscriptionService.FailureReason?
  private var waiters: [CheckedContinuation<LocalTranscriptionService.FailureReason, Never>] = []

  func record(_ reason: LocalTranscriptionService.FailureReason) {
    observed = reason
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume(returning: reason) }
  }

  func wait() async -> LocalTranscriptionService.FailureReason {
    if let observed { return observed }
    return await withCheckedContinuation { waiters.append($0) }
  }
}

private actor SuspendedLocalTranscriptionModelLoad {
  private var continuation: CheckedContinuation<AsrManager, Error>?
  private var cancelled = false

  func load() async throws -> AsrManager {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if cancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          self.continuation = continuation
        }
      }
    } onCancel: {
      Task { await self.cancel() }
    }
  }

  private func cancel() {
    cancelled = true
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }
}

final class LocalTranscriptionServiceReadinessTests: XCTestCase {
  func testWaitUntilReadyReturnsOnlyAfterTheInjectedModelLoaderSucceeds() async {
    let service = LocalTranscriptionService(
      modelLoader: { _ in AsrManager() })
    service.start(onSegments: { _ in })

    let ready = await service.waitUntilReady()
    XCTAssertTrue(ready)
    service.discardBufferedAudio()
  }

  func testWaitUntilReadyReportsModelLoadFailure() async {
    let service = LocalTranscriptionService(
      modelLoader: { _ in throw URLError(.cannotConnectToHost) })
    service.start(onSegments: { _ in })

    let ready = await service.waitUntilReady()
    XCTAssertFalse(ready)
    XCTAssertEqual(service.terminalFailureReason, .modelLoad)
    service.discardBufferedAudio()
  }

  func testWaitUntilReadyHasABoundedDeadline() async {
    let suspendedLoad = SuspendedLocalTranscriptionModelLoad()
    let service = LocalTranscriptionService(
      modelLoader: { _ in try await suspendedLoad.load() })
    service.start(onSegments: { _ in })

    let ready = await service.waitUntilReady(timeoutNanoseconds: 1_000_000)

    XCTAssertFalse(ready)
    service.discardBufferedAudio()
  }

  func testPreReadinessAudioOverflowFailsInsteadOfGrowingWithoutBound() async {
    let suspendedLoad = SuspendedLocalTranscriptionModelLoad()
    let service = LocalTranscriptionService(
      maxBufferedSeconds: 0.001,
      modelLoader: { _ in try await suspendedLoad.load() })
    service.start(onSegments: { _ in })

    service.appendAudio(Data(repeating: 0, count: 64))

    let ready = await service.waitUntilReady()
    XCTAssertFalse(ready)
    XCTAssertEqual(service.terminalFailureReason, .bufferExhausted)
    service.discardBufferedAudio()
  }

  func testPostReadinessOverflowRevokesUsabilityAndPublishesFailure() async {
    let failure = LocalTranscriptionFailureProbe()
    let service = LocalTranscriptionService(
      maxBufferedSeconds: 0.001,
      modelLoader: { _ in AsrManager() })
    service.start(
      onSegments: { _ in },
      onFailure: { reason in Task { await failure.record(reason) } })
    let ready = await service.waitUntilReady()
    XCTAssertTrue(ready)

    service.appendAudio(Data(repeating: 0, count: 64))
    let reason = await failure.wait()

    XCTAssertEqual(reason, .bufferExhausted)
    XCTAssertEqual(service.terminalFailureReason, .bufferExhausted)
    XCTAssertFalse(service.isUsableForCapture)
    service.discardBufferedAudio()
  }

  func testInferenceFailureRevokesUsabilityAndPublishesTypedFailure() async {
    let failure = LocalTranscriptionFailureProbe()
    let service = LocalTranscriptionService(
      maxBufferedSeconds: 11,
      modelLoader: { _ in AsrManager() },
      windowTranscriber: { _, _ in throw URLError(.cannotDecodeContentData) })
    service.start(
      onSegments: { _ in },
      onFailure: { reason in Task { await failure.record(reason) } })
    let ready = await service.waitUntilReady()
    XCTAssertTrue(ready)

    service.appendAudio(Data(repeating: 0x7f, count: 320_000))
    await service.processBufferedAudioForTesting()
    let reason = await failure.wait()

    XCTAssertEqual(reason, .inference)
    XCTAssertEqual(service.terminalFailureReason, .inference)
    XCTAssertFalse(service.isUsableForCapture)
    service.discardBufferedAudio()
  }
}
