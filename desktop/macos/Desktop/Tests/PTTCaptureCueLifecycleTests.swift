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
    XCTAssertEqual(PushToTalkManager.captureTerminal(for: .success), .completed)
    XCTAssertEqual(PushToTalkManager.captureTerminal(for: .ownerChanged), .ownerChanged)
    XCTAssertEqual(PushToTalkManager.captureTerminal(for: .cancelled), .cancelled)
    XCTAssertEqual(PushToTalkManager.captureTerminal(for: .tooShort), .failed)
    XCTAssertEqual(PushToTalkManager.captureTerminal(for: .providerFailed), .failed)
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
