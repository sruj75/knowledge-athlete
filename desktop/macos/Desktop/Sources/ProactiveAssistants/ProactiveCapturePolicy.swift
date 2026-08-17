/// Pure gating policy for scheduled screen-capture ticks. Extracted so the
/// precondition is unit-testable: a scheduled capture may run only while
/// monitoring and neither recovering nor background-polling. This is the
/// contract stopMonitoring must restore — if it fails to clear the recovery /
/// background-polling flags, every subsequent tick is gated off even though
/// monitoring is nominally on.
enum ProactiveCapturePolicy {
  static func captureTickAllowed(
    isMonitoring: Bool,
    isInRecoveryMode: Bool,
    isInBackgroundPolling: Bool
  ) -> Bool {
    isMonitoring && !isInRecoveryMode && !isInBackgroundPolling
  }
}

struct ProactiveMonitoringStartFence {
  private(set) var generation: UInt64 = 0

  mutating func begin() -> UInt64 {
    generation &+= 1
    return generation
  }

  mutating func cancel() { generation &+= 1 }
  func isCurrent(_ candidate: UInt64) -> Bool { candidate == generation }
}
