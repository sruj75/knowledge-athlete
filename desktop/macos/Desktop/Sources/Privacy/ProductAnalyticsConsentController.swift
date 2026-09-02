import Combine
import Foundation

@MainActor
protocol ProductAnalyticsPreferenceStore: AnyObject {
  func readShareProductAnalytics() -> Bool?
  func writeShareProductAnalytics(_ enabled: Bool)
}

@MainActor
protocol ProductAnalyticsConsentAdapter: AnyObject {
  func start() -> Bool
  func resume()
  func identify()
  func resetIdentity()
  func stopSharing()
}

@MainActor
final class UserDefaultsProductAnalyticsPreferenceStore: ProductAnalyticsPreferenceStore {
  private static let key = "shareProductAnalytics"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func readShareProductAnalytics() -> Bool? {
    guard defaults.object(forKey: Self.key) != nil else { return nil }
    return defaults.bool(forKey: Self.key)
  }

  func writeShareProductAnalytics(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.key)
  }
}

@MainActor
final class ProductAnalyticsConsentController: ObservableObject {
  enum Status: String, Equatable {
    case notStarted = "not_started"
    case enabled
    case disabledByUser = "disabled_by_user"
    case configurationUnavailable = "configuration_unavailable"

    var detail: String {
      switch self {
      case .notStarted:
        return "Analytics sharing starts only after the owned configuration is validated."
      case .enabled:
        return "Product analytics sharing is on."
      case .disabledByUser:
        return "Product analytics sharing is off."
      case .configurationUnavailable:
        return "No owned PostHog configuration is available, so no product analytics are being sent."
      }
    }
  }

  static let shared = ProductAnalyticsConsentController(
    store: UserDefaultsProductAnalyticsPreferenceStore(),
    adapter: PostHogManager.shared)

  private let store: ProductAnalyticsPreferenceStore
  private let adapter: ProductAnalyticsConsentAdapter
  @Published private(set) var isSharingEnabled: Bool
  @Published private(set) var status: Status
  private var isActive = false

  init(store: ProductAnalyticsPreferenceStore, adapter: ProductAnalyticsConsentAdapter) {
    let enabled = store.readShareProductAnalytics() ?? true
    self.store = store
    self.adapter = adapter
    self.isSharingEnabled = enabled
    self.status = enabled ? .notStarted : .disabledByUser
  }

  func start() {
    guard isSharingEnabled else {
      status = .disabledByUser
      return
    }
    isActive = adapter.start()
    status = isActive ? .enabled : .configurationUnavailable
  }

  func setSharingEnabled(_ enabled: Bool) {
    isSharingEnabled = enabled
    store.writeShareProductAnalytics(enabled)

    guard enabled else {
      if isActive {
        adapter.resetIdentity()
        adapter.stopSharing()
      }
      isActive = false
      status = .disabledByUser
      return
    }

    isActive = adapter.start()
    guard isActive else {
      status = .configurationUnavailable
      return
    }
    adapter.resume()
    status = .enabled
  }

  func identify() {
    guard isSharingEnabled, isActive else { return }
    adapter.identify()
  }

  func resetIdentity() {
    guard isActive else { return }
    adapter.resetIdentity()
  }
}
