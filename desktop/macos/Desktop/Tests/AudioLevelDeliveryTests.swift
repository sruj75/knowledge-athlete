import XCTest

@testable import Omi_Computer

private final class ManualAudioLevelQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var work: [@MainActor @Sendable () -> Void] = []
  private var samples: [Float] = []
  func schedule(_ operation: @escaping @MainActor @Sendable () -> Void) { lock.withLock { work.append(operation) } }
  func record(_ sample: Float) { lock.withLock { samples.append(sample) } }
  var pending: Int { lock.withLock { work.count } }
  var delivered: [Float] { lock.withLock { samples } }
  @MainActor func runNext() { lock.withLock { work.removeFirst() }() }
}

@MainActor
final class AudioLevelDeliveryTests: XCTestCase {
  func testBusyUIKeepsOnlyOnePendingMeterDeliveryAndTheLatestValue() {
    let queue = ManualAudioLevelQueue()
    let delivery = AudioLevelDelivery(schedule: queue.schedule)
    for value in 0..<1000 { delivery.submit(Float(value), to: queue.record) }
    XCTAssertEqual(queue.pending, 1)
    queue.runNext()
    XCTAssertEqual(queue.delivered, [999])
    delivery.submit(1000, to: queue.record)
    XCTAssertEqual(queue.pending, 1)
    queue.runNext()
    XCTAssertEqual(queue.delivered, [999, 1000])
  }

  func testStopInvalidatesQueuedOldCaptureWithoutDiscardingRestartedCapture() {
    let queue = ManualAudioLevelQueue()
    let delivery = AudioLevelDelivery(schedule: queue.schedule)
    delivery.submit(1, to: queue.record)
    delivery.reset()
    delivery.submit(2, to: queue.record)
    queue.runNext()
    XCTAssertTrue(queue.delivered.isEmpty)
    queue.runNext()
    XCTAssertEqual(queue.delivered, [2])
  }
}
