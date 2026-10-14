import XCTest

@testable import Omi_Computer

@available(macOS 14.4, *)
@MainActor
final class AmbientCaptureLifecycleTests: XCTestCase {
  func testListeningStartsMicrophoneAndSystemAudioWithoutAMeeting() async {
    let (state, microphone, system) = makeCapture()

    await state.reconcileCapture()

    XCTAssertTrue(state.isTranscribing)
    XCTAssertTrue(microphone.capturing)
    XCTAssertTrue(system.capturing)
  }

  func testDisablingSystemAudioKeepsMicrophoneListening() async {
    let (state, microphone, system) = makeCapture()
    await state.reconcileCapture()

    AssistantSettings.shared.systemAudioCaptureMode = .never
    await state.reconcileCapture()

    XCTAssertTrue(state.isTranscribing)
    XCTAssertTrue(microphone.capturing)
    XCTAssertFalse(system.capturing)
  }

  func testDisablingMicrophoneKeepsSystemAudioListeningAndReportsEachSource() async {
    let (state, microphone, system) = makeCapture()
    await state.reconcileCapture()

    AssistantSettings.shared.ambientMicrophoneEnabled = false
    await state.reconcileCapture()

    XCTAssertTrue(state.isTranscribing)
    XCTAssertFalse(microphone.capturing)
    XCTAssertTrue(system.capturing)
    XCTAssertEqual(state.supervisorAudioAvailability.0, .disabled)
    XCTAssertEqual(state.supervisorAudioAvailability.1, .available)
  }

  func testDeniedMicrophoneDoesNotPreventSystemCapture() async {
    let (state, microphone, system) = makeCapture()
    state.hasMicrophonePermission = false

    await state.reconcileCapture()

    XCTAssertEqual(microphone.startCount, 0)
    XCTAssertTrue(system.capturing)
    XCTAssertTrue(state.isTranscribing)
  }

  func testBothInputsCanBeDisabledAndIndependentlyReenabledWhileListeningIsArmed() async {
    let (state, microphone, system) = makeCapture()
    AssistantSettings.shared.ambientMicrophoneEnabled = false
    AssistantSettings.shared.systemAudioCaptureMode = .never
    await state.reconcileCapture()
    XCTAssertFalse(microphone.capturing)
    XCTAssertFalse(system.capturing)
    XCTAssertTrue(state.isTranscribing)

    AssistantSettings.shared.ambientMicrophoneEnabled = true
    await state.reconcileCapture()
    XCTAssertTrue(microphone.capturing)
    XCTAssertFalse(system.capturing)
    XCTAssertEqual(state.supervisorAudioAvailability.1, .disabled)
  }

  func testDisabledMicrophoneCannotFinishAnAsyncStartAfterItsConsentChanges() async {
    let entered = expectation(description: "microphone startup suspended")
    let gate = CaptureStartGate(entered: entered)
    let (state, microphone, system) = makeCapture(microphone: TestMicrophone(gate: gate))
    let startup = Task { await state.reconcileCapture() }
    await fulfillment(of: [entered], timeout: 2)
    AssistantSettings.shared.ambientMicrophoneEnabled = false
    await state.reconcileCapture()
    await gate.release()
    await startup.value
    XCTAssertFalse(microphone.capturing)
    XCTAssertTrue(system.capturing)
    XCTAssertTrue(state.isTranscribing)
  }

  func testNoUsableRequestedInputStopsListening() async {
    let (state, microphone, system) = makeCapture(
      microphone: TestMicrophone(fails: true), system: TestSystemAudio(fails: true))
    await state.reconcileCapture()
    await state.transcriptionStopTask?.value
    XCTAssertFalse(state.isTranscribing)
    XCTAssertFalse(microphone.capturing)
    XCTAssertFalse(system.capturing)
  }

  func testStopDuringMicrophoneStartupDoesNotStartAnotherAudioSource() async {
    let entered = expectation(description: "microphone startup suspended")
    let gate = CaptureStartGate(entered: entered)
    let (state, microphone, _) = makeCapture(microphone: TestMicrophone(gate: gate))
    let startup = Task { await state.reconcileCapture() }
    await fulfillment(of: [entered], timeout: 2)

    await state.stopTranscriptionAndWait()
    // Keep the hardware boundary intercepted if a stale reconciliation tries
    // to start system audio after stop cleared its original service slot.
    let system = TestSystemAudio()
    state.systemAudioCaptureService = system
    await gate.release()
    await startup.value

    XCTAssertFalse(state.isTranscribing)
    XCTAssertFalse(microphone.capturing)
    XCTAssertEqual(system.startCount, 0)
    XCTAssertFalse(system.capturing)
  }

  func testCancelledMicrophoneStartupCannotStopReplacementSession() async {
    let entered = expectation(description: "old microphone startup suspended")
    let gate = CaptureStartGate(entered: entered)
    let (state, oldMicrophone, _) = makeCapture(microphone: TestMicrophone(gate: gate))
    let oldStartup = Task { await state.reconcileCapture() }
    await fulfillment(of: [entered], timeout: 2)
    await state.stopTranscriptionAndWait()

    let microphone = TestMicrophone()
    let system = TestSystemAudio()
    state.audioCaptureService = microphone
    state.systemAudioCaptureService = system
    state.isTranscribing = true
    await state.reconcileCapture()
    await gate.release()
    await oldStartup.value

    XCTAssertTrue(state.isTranscribing)
    XCTAssertTrue(microphone.capturing)
    XCTAssertTrue(system.capturing)
    XCTAssertFalse(oldMicrophone.capturing)
  }

  func testMicrophoneFailurePreservesPermittedSystemListening() async {
    let (state, microphone, system) = makeCapture(microphone: TestMicrophone(fails: true))

    await state.reconcileCapture()
    await state.transcriptionStopTask?.value

    XCTAssertTrue(state.isTranscribing)
    XCTAssertFalse(microphone.capturing)
    XCTAssertTrue(system.capturing)
    XCTAssertEqual(system.startCount, 1)
  }

  func testOptionalSystemAudioFailurePreservesMicrophoneListening() async {
    let (state, microphone, system) = makeCapture(system: TestSystemAudio(fails: true))

    await state.reconcileCapture()

    XCTAssertTrue(state.isTranscribing)
    XCTAssertTrue(microphone.capturing)
    XCTAssertFalse(system.capturing)
  }

  func testStopDuringSystemAudioStartupLeavesBothSourcesInactive() async {
    let entered = expectation(description: "system audio startup suspended")
    let gate = CaptureStartGate(entered: entered)
    let (state, microphone, system) = makeCapture(system: TestSystemAudio(gate: gate))
    let startup = Task { await state.reconcileCapture() }
    await fulfillment(of: [entered], timeout: 2)

    await state.stopTranscriptionAndWait()
    await gate.release()
    await startup.value

    XCTAssertFalse(state.isTranscribing)
    XCTAssertFalse(microphone.capturing)
    XCTAssertFalse(system.capturing)
  }

  func testCancelledSystemAudioStartupCannotUnlockReplacementStartup() async {
    let oldEntered = expectation(description: "old system audio startup suspended")
    let oldGate = CaptureStartGate(entered: oldEntered)
    let (state, _, oldSystem) = makeCapture(system: TestSystemAudio(gate: oldGate))
    let oldStartup = Task { await state.reconcileCapture() }
    await fulfillment(of: [oldEntered], timeout: 2)
    await state.stopTranscriptionAndWait()

    let newEntered = expectation(description: "new microphone startup suspended")
    let newGate = CaptureStartGate(entered: newEntered)
    let microphone = TestMicrophone(gate: newGate)
    let system = TestSystemAudio()
    state.audioCaptureService = microphone
    state.systemAudioCaptureService = system
    state.isTranscribing = true
    let newStartup = Task { await state.reconcileCapture() }
    await fulfillment(of: [newEntered], timeout: 2)
    await oldGate.release()
    await oldStartup.value

    await state.reconcileCapture()
    await newGate.release()
    await newStartup.value

    XCTAssertTrue(state.isTranscribing)
    XCTAssertTrue(microphone.capturing)
    XCTAssertTrue(system.capturing)
    XCTAssertFalse(oldSystem.capturing)
    XCTAssertEqual(microphone.startCount, 1)
  }

  private func makeCapture(
    mode: AssistantSettings.SystemAudioCaptureMode = .always,
    microphone: TestMicrophone = TestMicrophone(),
    system: TestSystemAudio = TestSystemAudio()
  ) -> (AppState, TestMicrophone, TestSystemAudio) {
    let keys = [
      "systemAudioCaptureMode", "disableSystemAudioCapture", "transcriptionEnabled", "ambientMicrophoneEnabled",
    ]
    let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
    UserDefaults.standard.set(mode.rawValue, forKey: .systemAudioCaptureMode)
    UserDefaults.standard.set(false, forKey: .disableSystemAudioCapture)
    UserDefaults.standard.set(true, forKey: .ambientMicrophoneEnabled)
    UserDefaults.standard.set(true, forKey: .transcriptionEnabled)
    let state = AppState()
    state.hasMicrophonePermission = true
    state.audioCaptureService = microphone
    state.systemAudioCaptureService = system
    state.isTranscribing = true
    addTeardownBlock { @MainActor in
      await state.stopTranscriptionAndWait()
      state.servicesCoordinator.removeLifecycleObservers()
      for (key, value) in saved {
        if let value {
          UserDefaults.standard.set(value, forKey: key)
        } else {
          UserDefaults.standard.removeObject(forKey: key)
        }
      }
    }
    return (state, microphone, system)
  }
}

private enum CaptureTestError: Error { case unavailable }

private final class CaptureHardwareState: @unchecked Sendable {
  private let lock = NSLock()
  private var active = false
  private var starts = 0
  var startCount: Int { lock.withLock { starts } }
  var capturing: Bool { lock.withLock { active } }
  func start() {
    lock.withLock {
      active = true
      starts += 1
    }
  }
  func stop() { lock.withLock { active = false } }
}

private actor CaptureStartGate {
  private let entered: XCTestExpectation
  private var continuation: CheckedContinuation<Void, Never>?
  init(entered: XCTestExpectation) { self.entered = entered }
  func wait() async {
    // A duplicate hardware start returns immediately so tests can observe it
    // without deadlocking the deliberately suspended first request.
    guard continuation == nil else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      entered.fulfill()
    }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class TestMicrophone: AudioCaptureService, @unchecked Sendable {
  private let hardware = CaptureHardwareState()
  private let gate: CaptureStartGate?
  private let fails: Bool
  init(gate: CaptureStartGate? = nil, fails: Bool = false) {
    self.gate = gate
    self.fails = fails
    super.init()
  }
  var startCount: Int { hardware.startCount }
  override var capturing: Bool { hardware.capturing }
  override func startCapture(
    onAudioChunk: @escaping AudioChunkHandler, onAudioLevel: AudioLevelHandler? = nil
  ) async throws {
    await gate?.wait()
    if fails { throw CaptureTestError.unavailable }
    hardware.start()
  }
  override func stopCapture() { hardware.stop() }
}

@available(macOS 14.4, *)
private final class TestSystemAudio: SystemAudioCaptureService, @unchecked Sendable {
  private let hardware = CaptureHardwareState()
  private let gate: CaptureStartGate?
  private let fails: Bool
  init(gate: CaptureStartGate? = nil, fails: Bool = false) {
    self.gate = gate
    self.fails = fails
    super.init()
  }
  var startCount: Int { hardware.startCount }
  override var capturing: Bool { hardware.capturing }
  override func startCapture(
    onAudioChunk: @escaping AudioChunkHandler, onAudioLevel: AudioLevelHandler? = nil
  ) async throws {
    await gate?.wait()
    if fails { throw CaptureTestError.unavailable }
    hardware.start()
  }
  override func stopCapture() { hardware.stop() }
}
