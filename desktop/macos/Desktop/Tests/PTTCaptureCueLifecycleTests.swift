import XCTest

@testable import Omi_Computer

final class PTTCaptureCueLifecycleTests: XCTestCase {
  func testEnabledCaptureStartsAudiblyBeforeMutingAndCompletesAfterRestore() {
    var events: [String] = []
    let lifecycle = PTTCaptureAudioTransition(
      playStartCue: { events.append("start") },
      playEndCue: { events.append("end") },
      muteOutput: { events.append("mute") },
      restoreOutput: { events.append("restore") })

    lifecycle.begin(soundsEnabled: true, muteEnabled: true)
    lifecycle.end(.completed)

    XCTAssertEqual(events, ["start", "mute", "restore", "end"])
  }

  func testDisabledSoundsStillMuteAndRestoreWithoutPlayingCues() {
    var events: [String] = []
    let lifecycle = PTTCaptureAudioTransition(
      playStartCue: { events.append("start") },
      playEndCue: { events.append("end") },
      muteOutput: { events.append("mute") },
      restoreOutput: { events.append("restore") })

    lifecycle.begin(soundsEnabled: false, muteEnabled: true)
    lifecycle.end(.completed)

    XCTAssertEqual(events, ["mute", "restore"])
  }

  func testCancelledFailedAndOwnerChangedCaptureRestoreWithoutSuccessCue() {
    for terminal in [
      PTTCaptureAudioTransition.Terminal.cancelled,
      .failed,
      .ownerChanged,
    ] {
      var events: [String] = []
      let lifecycle = PTTCaptureAudioTransition(
        playStartCue: { events.append("start") },
        playEndCue: { events.append("end") },
        muteOutput: { events.append("mute") },
        restoreOutput: { events.append("restore") })

      lifecycle.begin(soundsEnabled: true, muteEnabled: true)
      lifecycle.end(terminal)

      XCTAssertEqual(events, ["start", "mute", "restore"], "terminal=\(terminal)")
    }
  }

  func testPhysicalCaptureRestoresBeforeAdmissionAndRejectedAudioGetsNoEndCue() {
    var events: [String] = []
    let lifecycle = PTTCaptureAudioTransition(
      playStartCue: { events.append("start") },
      playEndCue: { events.append("end") },
      muteOutput: { events.append("mute") },
      restoreOutput: { events.append("restore") })

    lifecycle.begin(soundsEnabled: true, muteEnabled: true)
    lifecycle.finishCapture()
    XCTAssertEqual(events, ["start", "mute", "restore"])

    lifecycle.end(.failed)
    XCTAssertEqual(events, ["start", "mute", "restore"])
  }

  func testAdmittedAudioPlaysEndCueAfterEarlyRestore() {
    var events: [String] = []
    let lifecycle = PTTCaptureAudioTransition(
      playStartCue: { events.append("start") },
      playEndCue: { events.append("end") },
      muteOutput: { events.append("mute") },
      restoreOutput: { events.append("restore") })

    lifecycle.begin(soundsEnabled: true, muteEnabled: true)
    lifecycle.finishCapture()
    lifecycle.end(.completed)

    XCTAssertEqual(events, ["start", "mute", "restore", "end"])
  }

  func testVoiceTerminalReasonsMapToNamedCaptureSemantics() {
    XCTAssertEqual(PTTCaptureAudioTransition.terminal(for: .success), .completed)
    XCTAssertEqual(PTTCaptureAudioTransition.terminal(for: .ownerChanged), .ownerChanged)
    XCTAssertEqual(PTTCaptureAudioTransition.terminal(for: .cancelled), .cancelled)
    XCTAssertEqual(PTTCaptureAudioTransition.terminal(for: .tooShort), .failed)
    XCTAssertEqual(PTTCaptureAudioTransition.terminal(for: .providerFailed), .failed)
  }

  func testEndWithoutAStartedCaptureOnlyRestoresOutput() {
    var events: [String] = []
    let lifecycle = PTTCaptureAudioTransition(
      playStartCue: { events.append("start") },
      playEndCue: { events.append("end") },
      muteOutput: { events.append("mute") },
      restoreOutput: { events.append("restore") })

    lifecycle.end(.completed)

    XCTAssertEqual(events, ["restore"])
  }
}
