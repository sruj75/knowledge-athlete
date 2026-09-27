import CoreGraphics
import Foundation

enum SystemInputIdleClock {
  static func seconds(
    sinceLastEvent: (CGEventSourceStateID, CGEventType) -> TimeInterval =
      CGEventSource.secondsSinceLastEventType
  ) -> TimeInterval {
    // Quartz's kCGAnyInputEventType includes keyboard, mouse and tablet input.
    // A null event has its own clock and can stay old while the user is active.
    guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else {
      return .infinity
    }
    return sinceLastEvent(.hidSystemState, anyInputEvent)
  }
}
