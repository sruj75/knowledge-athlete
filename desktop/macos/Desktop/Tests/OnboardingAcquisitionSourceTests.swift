import XCTest

@testable import Omi_Computer

private final class UnexpectedAcquisitionNetworkRequest: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var _requestCount = 0

  static var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _requestCount
  }

  static func reset() {
    lock.lock()
    _requestCount = 0
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self._requestCount += 1
    Self.lock.unlock()
    client?.urlProtocol(self, didFailWithError: URLError(.dataNotAllowed))
  }

  override func stopLoading() {}
}

@MainActor
final class OnboardingAcquisitionSourceTests: XCTestCase {
  func testSelectionPersistsLocallyTracksOnceAndAdvancesWithoutRemoteState() throws {
    let suiteName = "OnboardingAcquisitionSourceTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var analyticsSources: [String] = []
    let recorder = OnboardingAcquisitionSourceRecorder(
      defaults: defaults,
      track: { analyticsSources.append($0) })
    let model = SBOnboardingModel(
      appState: AppState(),
      chatProvider: ChatProvider(),
      acquisitionSourceRecorder: recorder,
      onComplete: nil)
    model.step = .howHeard

    UnexpectedAcquisitionNetworkRequest.reset()
    XCTAssertTrue(URLProtocol.registerClass(UnexpectedAcquisitionNetworkRequest.self))
    defer { URLProtocol.unregisterClass(UnexpectedAcquisitionNetworkRequest.self) }

    model.pickHowHeard("YouTube")

    XCTAssertEqual(
      defaults.string(forKey: DefaultsKey.onboardingHowDidYouHearSource),
      "YouTube")
    XCTAssertEqual(analyticsSources, ["YouTube"])
    XCTAssertEqual(model.howHeard, "YouTube")
    XCTAssertEqual(model.step, .language)
    XCTAssertEqual(UnexpectedAcquisitionNetworkRequest.requestCount, 0)
  }
}
