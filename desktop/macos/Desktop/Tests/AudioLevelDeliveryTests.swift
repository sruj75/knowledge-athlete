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
    delivery.activate(delivery.invalidate())
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
    delivery.activate(delivery.invalidate())
    delivery.submit(1, to: queue.record)
    let nextCapture = delivery.invalidate()
    delivery.submit(99, to: queue.record)  // HAL may still be winding down.
    delivery.activate(nextCapture)
    delivery.submit(2, to: queue.record)
    queue.runNext()
    XCTAssertTrue(queue.delivered.isEmpty)
    queue.runNext()
    XCTAssertEqual(queue.delivered, [2])
  }

  func testProductionStopInvalidatesMeterBeforeEarlyReturnOrPhysicalTeardown() {
    let queue = ManualAudioLevelQueue()
    let delivery = AudioLevelDelivery(schedule: queue.schedule)
    let capture = delivery.invalidate()
    delivery.activate(capture)
    let service = AudioCaptureService(audioLevelDelivery: delivery)
    delivery.submit(1, to: queue.record)
    service.stopCapture()
    // A pending start cannot reopen delivery after stop invalidates its receipt.
    delivery.activate(capture)
    delivery.submit(99, to: queue.record)
    XCTAssertEqual(queue.pending, 1)
    queue.runNext()
    XCTAssertTrue(queue.delivered.isEmpty)
  }
}
