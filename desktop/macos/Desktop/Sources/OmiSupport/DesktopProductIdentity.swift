import Foundation

/// The single display-independent identity authority for every Intentive desktop bundle.
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
  package static let productSlug = "heyintentive"

  package static let stableBundleIdentifier = "com.heyintentive.intentive"
  package static let betaBundleIdentifier = "com.heyintentive.intentive.beta"
  package static let canonicalDevelopmentBundleIdentifier = "com.heyintentive.intentive.dev"
  package static let namedDevelopmentBundlePrefix = "com.heyintentive.intentive.dev."
  package static let previewBundlePrefix = "com.heyintentive.intentive.preview."

  package static let applicationFilename = "Intentive.app"
  package static let databaseFilename = "heyintentive.db"
  package static let runningFlagFilename = ".heyintentive_running"
  package static let agentRuntimeDatabaseFilename = "heyintentive-agent.sqlite3"
  package static let logPrefix = "heyintentive"
  package static let lockPrefix = "heyintentive"
  package static let automationTokenPrefix = "heyintentive-automation"
  package static let archiveCacheRootName = "heyintentive-desktop"
  package static let runtimeManifestFilename = ".heyintentive-dev-runtime.json"
  package static let agentStateEnvironmentVariable = "HEYINTENTIVE_AGENT_STATE_DIR"
  package static let agentArtifactsEnvironmentVariable = "HEYINTENTIVE_AGENT_ARTIFACTS_DIR"
  package static let installerSkipEnvironmentVariable = "HEYINTENTIVE_SKIP_INSTALL_GATE"
  package static let authKeychainServiceBase =
    "com.heyintentive.intentive.firebase-rest-session"
  package static let clientDeviceKeychainServiceBase =
    "com.heyintentive.intentive.client-device-id"

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
      return ["Intentive"]
    case .beta:
      return ["Intentive Beta"]
    case .canonicalDevelopment:
      return ["Intentive Dev"]
    case .namedDevelopment:
      return ["Intentive Dev Bundles", bundleIdentifier]
    case .preview:
      return ["Intentive Preview Builds", bundleIdentifier]
    }
  }

  package var cachePathComponents: [String] {
    applicationSupportPathComponents
  }

  package func applicationSupportURL(homeDirectory: URL) -> URL {
    applicationSupportPathComponents.reduce(
      homeDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
    ) { partialResult, component in
      partialResult.appendingPathComponent(component, isDirectory: true)
    }
  }

  package var urlScheme: String {
    switch family {
    case .stable:
      return "heyintentive"
    case .beta:
      return "heyintentive-beta"
    case .canonicalDevelopment:
      return "heyintentive-dev"
    case .namedDevelopment(let slug):
      return "heyintentive-\(slug)"
    case .preview(let identifier):
      return "heyintentive-preview-\(identifier)"
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
