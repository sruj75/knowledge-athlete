import Foundation

/// The single display-independent identity authority for every Intuitive desktop bundle.
///
/// A bundle identifier that is not one of the approved families is rejected. Callers must
/// never turn an unknown identity into the stable product's privileges or writable paths.
package struct DesktopProductIdentity: Equatable {
  package enum Family: Equatable {
    case stable
    case beta
    case canonicalDevelopment
    case namedDevelopment(String)
    case preview(String)
  }

  package static let reverseDNSOwner = "com.heyintentive"
  package static let productSlug = "intuitive"

  package static let stableBundleIdentifier = "com.heyintentive.intuitive"
  package static let betaBundleIdentifier = "com.heyintentive.intuitive.beta"
  package static let canonicalDevelopmentBundleIdentifier = "com.heyintentive.intuitive.dev"
  package static let namedDevelopmentBundlePrefix = "com.heyintentive.intuitive.dev."
  package static let previewBundlePrefix = "com.heyintentive.intuitive.preview."

  package static let applicationFilename = "Intuitive.app"
  package static let databaseFilename = "intuitive.db"
  package static let agentRuntimeDatabaseFilename = "intuitive-agent.sqlite3"
  package static let logPrefix = "intuitive"
  package static let lockPrefix = "intuitive"
  package static let automationTokenPrefix = "intuitive-automation"
  package static let archiveCacheRootName = "IntuitiveDesktop"
  package static let runtimeManifestFilename = ".intuitive-dev-runtime.json"
  package static let agentStateEnvironmentVariable = "INTUITIVE_AGENT_STATE_DIR"
  package static let installerSkipEnvironmentVariable = "INTUITIVE_SKIP_INSTALL_GATE"
  package static let authKeychainServiceBase =
    "com.heyintentive.intuitive.firebase-rest-session"
  package static let clientDeviceKeychainServiceBase =
    "com.heyintentive.intuitive.client-device-id"

  package let bundleIdentifier: String
  package let family: Family

  package init?(bundleIdentifier: String?) {
    guard let bundleIdentifier else { return nil }

    let family: Family
    switch bundleIdentifier {
    case Self.stableBundleIdentifier:
      family = .stable
    case Self.betaBundleIdentifier:
      family = .beta
    case Self.canonicalDevelopmentBundleIdentifier:
      family = .canonicalDevelopment
    default:
      if bundleIdentifier.hasPrefix(Self.namedDevelopmentBundlePrefix) {
        let slug = String(bundleIdentifier.dropFirst(Self.namedDevelopmentBundlePrefix.count))
        guard Self.isValidIdentifierComponent(slug) else { return nil }
        family = .namedDevelopment(slug)
      } else if bundleIdentifier.hasPrefix(Self.previewBundlePrefix) {
        let identifier = String(bundleIdentifier.dropFirst(Self.previewBundlePrefix.count))
        guard Self.isValidIdentifierComponent(identifier) else { return nil }
        family = .preview(identifier)
      } else {
        return nil
      }
    }

    self.bundleIdentifier = bundleIdentifier
    self.family = family
  }

  package var isProductionFamily: Bool {
    family == .stable || family == .beta
  }

  package var isNamedDevelopment: Bool {
    if case .namedDevelopment = family { return true }
    return false
  }

  package var isPreview: Bool {
    if case .preview = family { return true }
    return false
  }

  package var applicationSupportPathComponents: [String] {
    switch family {
    case .stable:
      return ["Intuitive"]
    case .beta:
      return ["Intuitive Beta"]
    case .canonicalDevelopment:
      return ["Intuitive Dev"]
    case .namedDevelopment:
      return ["Intuitive Dev Bundles", bundleIdentifier]
    case .preview:
      return ["Intuitive Preview Builds", bundleIdentifier]
    }
  }

  package var cachePathComponents: [String] {
    applicationSupportPathComponents
  }

  package var urlScheme: String {
    switch family {
    case .stable:
      return "intuitive"
    case .beta:
      return "intuitive-beta"
    case .canonicalDevelopment:
      return "intuitive-dev"
    case .namedDevelopment(let slug):
      return "intuitive-\(slug)"
    case .preview(let identifier):
      return "intuitive-preview-\(identifier)"
    }
  }

  package var allowsLocalAutomation: Bool {
    switch family {
    case .canonicalDevelopment, .namedDevelopment:
      return true
    case .stable, .beta, .preview:
      return false
    }
  }

  package var allowsSparkleUpdates: Bool {
    switch family {
    case .stable, .beta, .canonicalDevelopment:
      return true
    case .namedDevelopment, .preview:
      return false
    }
  }

  package var allowsLoginItem: Bool {
    isProductionFamily
  }

  /// The retained architecture has no app-group consumer or entitlement.
  package var appGroupIdentifier: String? { nil }

  private static func isValidIdentifierComponent(_ value: String) -> Bool {
    guard !value.isEmpty, value.first != "-", value.last != "-" else { return false }
    return value.unicodeScalars.allSatisfy { scalar in
      switch scalar.value {
      case 48...57, 97...122, 45:
        return true
      default:
        return false
      }
    }
  }
}
