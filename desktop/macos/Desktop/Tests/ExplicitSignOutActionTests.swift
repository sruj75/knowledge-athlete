import XCTest

@testable import Omi_Computer

@MainActor
final class ExplicitSignOutActionTests: XCTestCase {
  func testMenuBarStopsMonitoringBeforeSigningOutWithoutChangingCapture() async {
    var events: [String] = []
    let action = ExplicitSignOutAction(
      stopTranscription: { events.append("stop_transcription") },
      stopMonitoring: { events.append("stop_monitoring") },
      signOut: { events.append("sign_out") })

    await action.perform(from: .menuBar).value

    XCTAssertEqual(events, ["stop_monitoring", "sign_out"])
  }

  func testSettingsStopsCaptureAndMonitoringBeforeSigningOut() async {
    var events: [String] = []
    let action = ExplicitSignOutAction(
      stopTranscription: { events.append("stop_transcription") },
      stopMonitoring: { events.append("stop_monitoring") },
      signOut: { events.append("sign_out") })

    await action.perform(from: .settings).value

    XCTAssertEqual(events, ["stop_transcription", "stop_monitoring", "sign_out"])
  }
}
