import XCTest

@testable import Omi_Computer

@MainActor
private final class CameraHardwareFixture: SupervisorCameraHardware {
  var permission: SupervisorCameraPermission = .authorized
  var devicesChanged: (@MainActor () -> Void)?
  var onStart: ((String) -> Void)?
  var sample: (@Sendable (SupervisorCameraSample) -> Void)?
  var unavailable: (@Sendable () -> Void)?
  var availableDevices = [
    SupervisorCameraDevice(id: "external", name: "External", builtIn: false),
    SupervisorCameraDevice(id: "builtin", name: "Built-in", builtIn: true),
  ]
  var permissionRequests = 0
  func devices() async -> [SupervisorCameraDevice] { availableDevices }
  func requestPermission() async -> Bool {
    permissionRequests += 1
    return permission == .authorized
  }
  func start(
    deviceID: String, sample: @escaping @Sendable (SupervisorCameraSample) -> Void,
    unavailable: @escaping @Sendable () -> Void
  ) {
    self.sample = sample
    self.unavailable = unavailable
    onStart?(deviceID)
  }
  func stop() {}
}

@MainActor
final class SupervisorWebcamTests: XCTestCase {
  func testCameraIsOptInAndDefaultsToBuiltInRatherThanAnExternalDevice() async throws {
    let hardware = CameraHardwareFixture()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let authority = RuntimeOwnerAuthorizationAuthority()
    let owner = try XCTUnwrap(authority.capture(ownerID: "camera-owner", expectedOwnerID: nil))
    let started = expectation(description: "explicit opt-in starts the built-in camera")
    hardware.onStart = { id in
      XCTAssertEqual(id, "builtin")
      started.fulfill()
    }
    let camera = SupervisorWebcamService(
      hardware: hardware, defaults: defaults, currentOwner: { owner },
      ownerIsCurrent: { authority.isCurrent($0, ownerID: "camera-owner") },
      monitoringSession: { "observation" }, deliver: { _, _, _ in }, statusChanged: { _ in })
    camera.setMonitoringAllowed(true)
    XCTAssertFalse(camera.enabled)
    XCTAssertNil(hardware.sample)
    XCTAssertEqual(hardware.permissionRequests, 0)
    camera.enabled = true
    await fulfillment(of: [started], timeout: 2)
    camera.enabled = false
  }

  func testDeniedCameraDoesNotPreventTranscriptObservation() async throws {
    let hardware = CameraHardwareFixture()
    hardware.permission = .denied
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let authority = RuntimeOwnerAuthorizationAuthority()
    let owner = try XCTUnwrap(authority.capture(ownerID: "camera-owner", expectedOwnerID: nil))
    let denied = expectation(description: "permission denial is exposed")
    var clock: TimeInterval = 100
    var requests: [SupervisorEvaluationRequest] = []
    let supervisor = SupervisorService(
      defaults: defaults, now: { Date(timeIntervalSince1970: clock) }, monotonicNow: { clock },
      currentOwner: { owner }, ownerIsCurrent: { authority.isCurrent($0, ownerID: "camera-owner") },
      evaluate: { request, _ in
        requests.append(request)
        return .init(
          decisionID: "decision", observationID: request.observationID, sessionID: request.sessionID,
          contextEpoch: request.contextEpoch, action: .wait, note: nil,
          prompt: .init(text: "", name: "test", version: "1", source: "fallback"), outcome: "completed")
      }, loadMemory: { _ in .empty }, deliver: { _ in }, decisionStarted: { _ in }, recordDecision: { _, _, _ in },
      automaticallySchedule: false)
    let camera = SupervisorWebcamService(
      hardware: hardware, defaults: defaults, currentOwner: { owner },
      ownerIsCurrent: { authority.isCurrent($0, ownerID: "camera-owner") },
      monitoringSession: { supervisor.sessionID }, deliver: { _, _, _ in },
      statusChanged: { status in
        supervisor.webcamUnavailable(status)
        if status == .denied { denied.fulfill() }
      })
    camera.setMonitoringAllowed(true)
    camera.enabled = true
    await fulfillment(of: [denied], timeout: 2)
    supervisor.observeVoice(userText: "Please help with this", turnID: "turn", outcome: "completed")
    clock += 1
    await supervisor.evaluatePendingObservation()
    XCTAssertEqual(requests.first?.conversation.first?.text, "Please help with this")
    XCTAssertEqual(requests.first?.inputStatus.webcam.status, .denied)
    XCTAssertNil(requests.first?.webcam)
    XCTAssertNil(hardware.sample)
    camera.enabled = false
  }

  func testDisablingAndAccountChangeRejectLateCameraFrames() async throws {
    let hardware = CameraHardwareFixture()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let authority = RuntimeOwnerAuthorizationAuthority()
    let owner = try XCTUnwrap(authority.capture(ownerID: "camera-owner", expectedOwnerID: nil))
    let started = expectation(description: "camera configured")
    hardware.onStart = { _ in started.fulfill() }
    var delivered = 0
    let camera = SupervisorWebcamService(
      hardware: hardware, defaults: defaults, currentOwner: { owner },
      ownerIsCurrent: { authority.isCurrent($0, ownerID: "camera-owner") }, monitoringSession: { "session" },
      deliver: { _, _, _ in delivered += 1 }, statusChanged: { _ in })
    camera.setMonitoringAllowed(true)
    camera.enabled = true
    await fulfillment(of: [started], timeout: 2)
    let oldSample = try XCTUnwrap(hardware.sample)
    camera.enabled = false
    authority.beginTransition()
    authority.endTransition(ownerID: "other-owner")
    oldSample(.init(jpegData: Data([0xFF, 0xD8, 0xFF]), capturedAt: Date(), capturedUptime: 100, visualHash: 0))
    // Yield through the public delivery boundary, then verify no old account image was published.
    await Task.yield()
    await Task.yield()
    XCTAssertEqual(delivered, 0)
    XCTAssertEqual(camera.availability, .disabled)
  }
}
