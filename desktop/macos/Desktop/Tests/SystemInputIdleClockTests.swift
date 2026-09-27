import CoreGraphics
import XCTest

@testable import Omi_Computer

final class SystemInputIdleClockTests: XCTestCase {
  func testRecentPhysicalInputAllowsCaptureEvenWhenNullEventClockIsOld() {
    var queriedEventTypes: [UInt32] = []
    let idleSeconds = SystemInputIdleClock.seconds { state, event in
      XCTAssertEqual(state, .hidSystemState)
      queriedEventTypes.append(event.rawValue)
      // A real click updates the any-input clock without creating a null event.
      return event.rawValue == UInt32.max ? 2 : 700
    }
    var trigger = ProactiveCaptureTrigger(
      idleThreshold: 60, heartbeatInterval: 3, appSwitchDebounce: 0.5)

    XCTAssertEqual(queriedEventTypes, [UInt32.max])
    XCTAssertEqual(
      trigger.nextDecision(
        app: "Dia", windowTitle: "Controlled voice check", idleSeconds: idleSeconds,
        now: Date(timeIntervalSinceReferenceDate: 5_000)),
      .capture)
  }

  func testActualInputInactivityStillPausesCaptureAtSixtySeconds() {
    let idleSeconds = SystemInputIdleClock.seconds { state, event in
      XCTAssertEqual(state, .hidSystemState)
      XCTAssertEqual(event.rawValue, UInt32.max)
      return 60
    }
    var trigger = ProactiveCaptureTrigger(
      idleThreshold: 60, heartbeatInterval: 3, appSwitchDebounce: 0.5)

    XCTAssertEqual(
      trigger.nextDecision(
        app: "Dia", windowTitle: "Controlled voice check", idleSeconds: idleSeconds,
        now: Date(timeIntervalSinceReferenceDate: 5_000)),
      .skip)
  }
}
