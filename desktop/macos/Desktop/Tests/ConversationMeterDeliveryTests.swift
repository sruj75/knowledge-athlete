import Foundation
import XCTest

@testable import Omi_Computer

private final class ConversationMeterQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var work: [@MainActor @Sendable () -> Void] = []
  private var samples: [Float] = []
  func schedule(_ operation: @escaping @MainActor @Sendable () -> Void) { lock.withLock { work.append(operation) } }
  func record(_ sample: Float) { lock.withLock { samples.append(sample) } }
  var pending: Int { lock.withLock { work.count } }
  var delivered: [Float] { lock.withLock { samples } }
  @MainActor func drain() {
    while pending > 0 { lock.withLock { work.removeFirst() }() }
  }
}

@MainActor
final class ConversationMeterDeliveryTests: XCTestCase {
  func testLateRenderFromStoppedReplyCannotOverwriteReplacementMeterSample() {
    let queue = ConversationMeterQueue()
    let delivery = AudioLevelDelivery(schedule: queue.schedule)
    let old = delivery.invalidate()
    delivery.activate(old)
    delivery.submit(0.8, capture: old, to: queue.record)
    let current = delivery.invalidate()
    delivery.activate(current)
    delivery.submit(0.4, capture: current, to: queue.record)
    delivery.submit(0.9, capture: old, to: queue.record)
    queue.drain()
    XCTAssertEqual(queue.delivered, [0.4])
  }
  func testDuplexReplyStopInvalidatesOnlyOutputAndCloseInvalidatesInputToo() async {
    let inputQueue = ConversationMeterQueue()
    let outputQueue = ConversationMeterQueue()
    let input = AudioLevelDelivery(schedule: inputQueue.schedule)
    let output = AudioLevelDelivery(schedule: outputQueue.schedule)
    let inputCapture = input.invalidate()
    let outputCapture = output.invalidate()
    input.activate(inputCapture)
    output.activate(outputCapture)
    let audio = ConversationDuplexAudio(microphoneLevels: input, playbackLevels: output)
    input.submit(0.4, capture: inputCapture, to: inputQueue.record)
    output.submit(0.8, capture: outputCapture, to: outputQueue.record)
    audio.stopPlayback()
    output.submit(0.9, capture: outputCapture, to: outputQueue.record)
    inputQueue.drain()
    outputQueue.drain()
    XCTAssertEqual(inputQueue.delivered, [0.4])
    XCTAssertTrue(outputQueue.delivered.isEmpty)
    input.submit(0.5, capture: inputCapture, to: inputQueue.record)
    await audio.stopAndWait()
    inputQueue.drain()
    XCTAssertEqual(inputQueue.delivered, [0.4], "Logical close rejects pending microphone samples")
  }

}
