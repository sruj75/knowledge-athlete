import Foundation

/// Firebase credentials are mandatory for every production and model runtime
/// start. The sole exception is a non-production journal-control start, whose
/// owner-bound RPCs deliberately operate without a model credential. The
/// fault suite supplies a separate, inert model token so its named test bundle
/// can reach the local 5xx endpoint without contacting Firebase.
enum AgentRuntimeCredentialPolicy {
  static let hermeticFaultModelTokenEnvironmentKey = "OMI_FAULT_MODEL_AUTH_TOKEN"
  static let hermeticFaultBundleIdentifierPrefix = "com.heyintentive.intentive.dev.omi-fault-"

  static func hermeticFaultModelToken(
    isNonProduction: Bool,
    bundleIdentifier: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    let suffix = String(bundleIdentifier.dropFirst(hermeticFaultBundleIdentifierPrefix.count))
    let isOwnedFaultBundle =
      bundleIdentifier.hasPrefix(hermeticFaultBundleIdentifierPrefix)
      && (16...48).contains(suffix.count)
      && suffix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    guard isNonProduction, isOwnedFaultBundle else { return nil }
    let token =
      environment[hermeticFaultModelTokenEnvironmentKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return token.isEmpty ? nil : token
  }

  static func requiresManagedCredentials(
    requestedCredentials: Bool,
    isNonProduction: Bool,
    hermeticFaultModelToken: String? = nil
  ) -> Bool {
    (requestedCredentials || !isNonProduction) && hermeticFaultModelToken == nil
  }

  /// Named QA bundles have a valid owner-bound token seeded from another app,
  /// but intentionally lack that app's Firebase SDK session. Let AuthService
  /// reuse the token until its normal expiry path refreshes it.
  static func shouldForceRefreshAtStartup(
    isNonProduction: Bool,
    isDesktopLocalProfile: Bool
  ) -> Bool {
    !isNonProduction && !isDesktopLocalProfile
  }
}
