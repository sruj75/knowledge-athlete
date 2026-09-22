import XCTest

@testable import Omi_Computer

@MainActor
final class SystemAudioCaptureModeSettingsTests: XCTestCase {
  private let key = "systemAudioCaptureMode"
  private var previousValue: Any?

  override func setUp() async throws {
    previousValue = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
  }

  override func tearDown() async throws {
    if let previousValue {
      UserDefaults.standard.set(previousValue, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
    previousValue = nil
  }

  func testDefaultsToContinuousSystemAudioCapture() {
    XCTAssertEqual(AssistantSettings.shared.systemAudioCaptureMode, .always)
  }

  func testPersistsContinuousAndMicrophoneOnlyModes() {
    AssistantSettings.shared.systemAudioCaptureMode = .never
    XCTAssertEqual(AssistantSettings.shared.systemAudioCaptureMode, .never)

    AssistantSettings.shared.systemAudioCaptureMode = .always
    XCTAssertEqual(AssistantSettings.shared.systemAudioCaptureMode, .always)
  }

  func testUnknownRawValueFallsBackToContinuousCapture() {
    UserDefaults.standard.set("garbage", forKey: key)
    XCTAssertEqual(AssistantSettings.shared.systemAudioCaptureMode, .always)
  }

  func testMeetingsOnlyIsNotAnAvailableCaptureMode() {
    XCTAssertNil(AssistantSettings.SystemAudioCaptureMode(rawValue: "onlyDuringMeetings"))
  }
}
