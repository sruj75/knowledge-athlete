import CoreGraphics
import XCTest

@testable import Omi_Computer

private final class WindowQueryReceipt: @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0
  private var onMain = false
  func record() -> Int {
    lock.withLock {
      calls += 1
      onMain = onMain || Thread.isMainThread
      return calls
    }
  }
  var count: Int { lock.withLock { calls } }
  var usedMainThread: Bool { lock.withLock { onMain } }
}

@MainActor
final class SystemCaptureModeProbeTests: XCTestCase {
  func testWindowServerLookupDoesNotRunOnMainThread() async {
    let receipt = WindowQueryReceipt()
    let probe = SystemCaptureModeProbe(lookup: {
      _ = receipt.record()
      return true
    })
    await probe.refresh().value
    XCTAssertFalse(receipt.usedMainThread)
    XCTAssertTrue(probe.blocksCapture(frontmostBundleID: "test.app"))
  }

  func testStuckLookupLeavesMainActorFreeAndCoalescesRefreshes() async {
    let started = expectation(description: "background lookup started")
    let gate = DispatchSemaphore(value: 0)
    let receipt = WindowQueryReceipt()
    let probe = SystemCaptureModeProbe(lookup: {
      _ = receipt.record()
      started.fulfill()
      gate.wait()
      return true
    })
    let task = probe.refresh()
    await fulfillment(of: [started], timeout: 2)
    for _ in 0..<100 {
      XCTAssertFalse(probe.blocksCapture(frontmostBundleID: "test.app"))
      probe.refresh()
    }
    XCTAssertEqual(receipt.count, 1)
    XCTAssertFalse(receipt.usedMainThread)
    gate.signal()
    await task.value
    XCTAssertTrue(probe.blocksCapture(frontmostBundleID: "test.app"))
  }

  func testExpiredBlockedSnapshotCannotPauseCaptureForever() async {
    let receipt = WindowQueryReceipt()
    let started = expectation(description: "second lookup started")
    let gate = DispatchSemaphore(value: 0)
    var fallbackCount = 0
    let probe = SystemCaptureModeProbe(
      lookup: {
        if receipt.record() == 1 { return true }
        started.fulfill()
        gate.wait()
        return false
      }, onFallback: { fallbackCount += 1 })
    await probe.refresh().value
    let task = probe.refresh()
    await fulfillment(of: [started], timeout: 2)
    XCTAssertFalse(probe.blocksCapture(frontmostBundleID: "test.app", now: Date().addingTimeInterval(10)))
    XCTAssertFalse(probe.blocksCapture(frontmostBundleID: "test.app", now: Date().addingTimeInterval(11)))
    XCTAssertEqual(fallbackCount, 1)
    gate.signal()
    await task.value
    XCTAssertFalse(probe.blocksCapture(frontmostBundleID: "test.app"))
  }

  func testForegroundDockNeedsNoWindowServerLookup() {
    let receipt = WindowQueryReceipt()
    let probe = SystemCaptureModeProbe(lookup: {
      _ = receipt.record()
      return false
    })
    XCTAssertTrue(probe.blocksCapture(frontmostBundleID: "com.apple.dock"))
    XCTAssertEqual(receipt.count, 0)
  }

  func testUnavailableLookupReportsFallbackWithoutInventingABlockingMode() async {
    var fallbacks = 0
    let probe = SystemCaptureModeProbe(lookup: { nil }, onFallback: { fallbacks += 1 })
    await probe.refresh().value
    XCTAssertEqual(fallbacks, 1)
  }

  func testOverlayDetectionPreservesMissionControlAndNotificationCenterRules() {
    let dock: [String: Any] = [
      kCGWindowOwnerName as String: "Dock",
      kCGWindowBounds as String: ["Width": CGFloat(900), "Height": CGFloat(600)],
    ]
    XCTAssertTrue(SystemCaptureModeProbe.containsBlockingOverlay([dock]))
    XCTAssertTrue(
      SystemCaptureModeProbe.containsBlockingOverlay([[kCGWindowOwnerName as String: "NotificationCenter"]]))
    XCTAssertFalse(SystemCaptureModeProbe.containsBlockingOverlay([]))
    var namedDock = dock
    namedDock[kCGWindowName as String] = "ordinary window"
    XCTAssertFalse(SystemCaptureModeProbe.containsBlockingOverlay([namedDock]))
  }
}
