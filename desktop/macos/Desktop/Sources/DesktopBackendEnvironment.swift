import Foundation
import OmiSupport

enum DesktopBackendEnvironment {
  static let productionBackendInfoKey = "IntentiveProductionAPIURL"
  static let developmentBackendURL =
    "https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app/"

  static var productionBackendURL: String? {
    validatedProductionURL(
      Bundle.main.object(forInfoDictionaryKey: productionBackendInfoKey) as? String)
  }

  static var shouldUseDevelopmentBackends: Bool {
    shouldUseDevelopmentBackends(
      bundleIdentifier: AppBuild.bundleIdentifier,
      updateChannel: AppBuild.currentUpdateChannel,
      externalPreviewBackend: AppBuild.externalPreviewBackend
    )
  }

  static func shouldUseDevelopmentBackends(
    bundleIdentifier: String,
    updateChannel: String,
    externalPreviewBackend: AppBuild.ExternalPreviewBackend? = nil
  ) -> Bool {
    // External previews opt into their backend through signed bundle metadata. They must
    // never inherit local-development routing or an environment force override. Missing or
    // malformed preview metadata therefore fails closed to the production backend.
    if AppBuild.isExternalPreviewBundleIdentifier(bundleIdentifier) {
      return externalPreviewBackend == .development
    }

    guard let identity = DesktopProductIdentity(bundleIdentifier: bundleIdentifier) else {
      return false
    }

    // Named/dev bundles route to the dev backend by default. Explicit launch
    // URLs still win below so local harnesses and intentionally-targeted tests
    // remain possible. The Intentive Beta app is a production-family artifact, not a
    // dev bundle: it falls through to channel-based routing like stable.
    return !identity.isProductionFamily
  }

  static func backendBaseURL(
    environmentValue: String? = currentEnvironmentValue("OMI_PYTHON_API_URL")
  ) -> String {
    backendBaseURL(
      useDevelopmentBackends: shouldUseDevelopmentBackends,
      environmentValue: environmentValue
    )
  }

  static func backendBaseURL(
    useDevelopmentBackends: Bool,
    environmentValue: String?
  ) -> String {
    guard
      let resolved = resolvedBackendBaseURL(
        useDevelopmentBackends: useDevelopmentBackends,
        environmentValue: environmentValue,
        productionMetadataValue: Bundle.main.object(
          forInfoDictionaryKey: productionBackendInfoKey) as? String)
    else {
      preconditionFailure(
        "Production Intentive bundle is missing a valid signed \(productionBackendInfoKey)")
    }
    return resolved
  }

  static func resolvedBackendBaseURL(
    useDevelopmentBackends: Bool,
    environmentValue: String?,
    productionMetadataValue: String?
  ) -> String? {
    // A production-family app must not allow a launch environment or bundled
    // config to switch its customer data plane. Development identities retain
    // their explicit override seam for local and signed-preview testing.
    if !useDevelopmentBackends {
      return validatedProductionURL(productionMetadataValue)
    }
    if let url = normalizedURL(environmentValue) {
      return url
    }

    return developmentBackendURL
  }

  static func authBaseURL(
    useDevelopmentBackends: Bool = shouldUseDevelopmentBackends,
    environmentValue: String? = currentEnvironmentValue("OMI_AUTH_API_URL")
  ) -> String {
    guard
      let resolved = resolvedAuthBaseURL(
        useDevelopmentBackends: useDevelopmentBackends,
        environmentValue: environmentValue,
        productionMetadataValue: Bundle.main.object(
          forInfoDictionaryKey: productionBackendInfoKey) as? String)
    else {
      preconditionFailure(
        "Production Intentive bundle is missing a valid signed \(productionBackendInfoKey)")
    }
    return resolved
  }

  static func resolvedAuthBaseURL(
    useDevelopmentBackends: Bool,
    environmentValue: String?,
    productionMetadataValue: String?
  ) -> String? {
    if !useDevelopmentBackends {
      return validatedProductionURL(productionMetadataValue)
    }
    if let url = normalizedURL(environmentValue) {
      return url
    }

    return developmentBackendURL
  }

  static func applyReleaseChannelDefaults() {
    if shouldUseDevelopmentBackends {
      if normalizedURL(currentEnvironmentValue("OMI_PYTHON_API_URL")) == nil {
        setenv("OMI_PYTHON_API_URL", developmentBackendURL, 1)
      }
    }
    log("BackendEnvironment: release-channel defaults applied only for missing backend URLs")
  }

  private static func normalizedURL(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let normalized = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    guard
      let components = URLComponents(string: normalized),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      components.user == nil,
      components.password == nil,
      components.fragment == nil,
      let host = components.host?.lowercased(),
      !host.isEmpty,
      host != "omi.me",
      !host.hasSuffix(".omi.me"),
      host != "basedhardware.com",
      !host.hasSuffix(".basedhardware.com")
    else { return nil }
    return normalized
  }

  private static func validatedProductionURL(_ raw: String?) -> String? {
    guard
      let normalized = normalizedURL(raw),
      let components = URLComponents(string: normalized),
      components.scheme?.lowercased() == "https",
      components.user == nil,
      components.password == nil,
      components.fragment == nil,
      let host = components.host?.lowercased(),
      !host.isEmpty,
      host != "omi.me",
      !host.hasSuffix(".omi.me"),
      host != "basedhardware.com",
      !host.hasSuffix(".basedhardware.com")
    else { return nil }
    return normalized
  }

  private static func currentEnvironmentValue(_ key: String) -> String? {
    guard let value = getenv(key), let string = String(validatingCString: value) else {
      return nil
    }
    return string
  }
}
