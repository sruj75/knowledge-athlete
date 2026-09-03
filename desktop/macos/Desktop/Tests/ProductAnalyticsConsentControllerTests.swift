import XCTest

@testable import Omi_Computer

@MainActor
final class ProductAnalyticsConsentControllerTests: XCTestCase {
  private final class Store: ProductAnalyticsPreferenceStore {
    var value: Bool?

    init(_ value: Bool?) {
      self.value = value
    }

    func readShareProductAnalytics() -> Bool? { value }
    func writeShareProductAnalytics(_ enabled: Bool) { value = enabled }
  }

  private final class Adapter: ProductAnalyticsConsentAdapter {
    var isEnvironmentEligible = true
    var startSucceeds = true
    var events: [String] = []

    func start() -> Bool {
      events.append("start")
      return startSucceeds
    }

    func resume() { events.append("resume") }
    func identify() { events.append("identify") }
    func resetIdentity() { events.append("reset") }
    func stopSharing() { events.append("stop") }
  }

  func testDefaultOnStartsBeforeLaterIdentityAttachment() {
    let store = Store(nil)
    let adapter = Adapter()
    let controller = ProductAnalyticsConsentController(store: store, adapter: adapter)

    XCTAssertTrue(controller.isSharingEnabled)
    controller.start()
    controller.identify()

    XCTAssertEqual(adapter.events, ["start", "identify"])
    XCTAssertEqual(controller.status, .enabled)
  }

  func testSavedOffLaunchNeverStartsOrIdentifiesTheSDK() {
    let store = Store(false)
    let adapter = Adapter()
    let controller = ProductAnalyticsConsentController(store: store, adapter: adapter)

    controller.start()
    controller.identify()

    XCTAssertEqual(adapter.events, [])
    XCTAssertEqual(controller.status, .disabledByUser)
  }

  func testUnavailableOwnedConfigurationDoesNotReportSharingAsActive() {
    let store = Store(true)
    let adapter = Adapter()
    adapter.startSucceeds = false
    let controller = ProductAnalyticsConsentController(store: store, adapter: adapter)

    controller.start()

    XCTAssertTrue(controller.isSharingEnabled)
    XCTAssertEqual(adapter.events, ["start"])
    XCTAssertEqual(controller.status, .configurationUnavailable)
  }

  func testRuntimeOffDetachesIdentityBeforeStoppingAndBlocksLaterIdentity() {
    let store = Store(true)
    let adapter = Adapter()
    let controller = ProductAnalyticsConsentController(store: store, adapter: adapter)
    controller.start()

    controller.setSharingEnabled(false)
    controller.identify()

    XCTAssertEqual(adapter.events, ["start", "reset", "stop"])
    XCTAssertFalse(store.value ?? true)
    XCTAssertEqual(controller.status, .disabledByUser)
  }

  func testRuntimeOnStartsAndResumesSharing() {
    let store = Store(false)
    let adapter = Adapter()
    let controller = ProductAnalyticsConsentController(store: store, adapter: adapter)

    controller.setSharingEnabled(true)

    XCTAssertEqual(adapter.events, ["start", "resume"])
    XCTAssertTrue(store.value ?? false)
    XCTAssertEqual(controller.status, .enabled)
  }

  func testNonProductionEnvironmentNeverStartsWhenRuntimeConsentIsReenabled() {
    let store = Store(true)
    let adapter = Adapter()
    adapter.isEnvironmentEligible = false
    let controller = ProductAnalyticsConsentController(store: store, adapter: adapter)

    controller.start()
    controller.setSharingEnabled(false)
    controller.setSharingEnabled(true)
    controller.identify()

    XCTAssertEqual(adapter.events, [])
    XCTAssertTrue(store.value ?? false)
    XCTAssertEqual(controller.status, .disabledForEnvironment)
  }
}
