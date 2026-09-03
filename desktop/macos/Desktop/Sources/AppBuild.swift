import Foundation
import OmiSupport

enum AppBuild {
  static let productionBundleIdentifier = DesktopProductIdentity.stableBundleIdentifier
  /// The separately-installable beta app. A distinct bundle id gives it
  /// its own UserDefaults domain, TCC grants, Keychain ACL, and single-instance lock, so
  /// it runs side-by-side with stable.
  static let betaProductionBundleIdentifier = DesktopProductIdentity.betaBundleIdentifier
  static let productionFamilyBundleIdentifiers: Set<String> = [
    productionBundleIdentifier, betaProductionBundleIdentifier,
  ]
  static let desktopDevBundleIdentifier =
    DesktopProductIdentity.canonicalDevelopmentBundleIdentifier
  static let externalPreviewBundleIdentifierPrefix = DesktopProductIdentity.previewBundlePrefix
  static let externalPreviewMarkerInfoKey = "OMIExternalPreview"
  static let externalPreviewBackendInfoKey = "OMIExternalPreviewBackend"
  static let manualDownloadInfoKey = "IntentiveManualDownloadURL"
  static let releasesInfoKey = "IntentiveReleasesURL"
  static let productWebsiteInfoKey = "IntentiveProductURL"
  static let termsInfoKey = "IntentiveTermsURL"
  static let privacyInfoKey = "IntentivePrivacyURL"
  static let supportInfoKey = "IntentiveSupportURL"
  static let sparkleFeedInfoKey = "SUFeedURL"
  static let sparklePublicKeyInfoKey = "SUPublicEDKey"
  static let sourceGitSHAInfoKey = "IntentiveSourceGitSHA"
  static let sourceTreeDirtyInfoKey = "IntentiveSourceTreeDirty"
  private static let updateChannelDefaultsKey = "update_channel"
  private static let betaOverwriteMigrationKey = "didMigrateBetaOverwrite_v1"
  /// How long the launch-time channel probe may hold the main thread. It runs before the
  /// first frame, so it has to stay clear of the 3s watchdog that reports "App Hanging".
  private static let channelProbeMainThreadBudget: TimeInterval = 1.5
  private static let channelProbeRequestTimeout: TimeInterval = 3

  enum ExternalPreviewBackend: String, Equatable {
    case production
    case development

    init?(infoValue: Any?) {
      guard let rawValue = infoValue as? String else { return nil }
      self.init(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
  }

  struct SourceProvenance: Equatable {
    let gitSHA: String
    let sourceTreeDirty: Bool
  }

  static func sourceProvenance(infoDictionary: [String: Any]) -> SourceProvenance? {
    guard
      let gitSHA = infoDictionary[sourceGitSHAInfoKey] as? String,
      gitSHA.utf8.count == 40,
      gitSHA.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      let sourceTreeDirty = infoDictionary[sourceTreeDirtyInfoKey] as? Bool
    else {
      return nil
    }
    return SourceProvenance(gitSHA: gitSHA, sourceTreeDirty: sourceTreeDirty)
  }

  /// Release-only destinations and Sparkle trust material stamped into the signed app.
  ///
  /// The repository intentionally has no fallback values for these fields. Until the
  /// product-owned release provider supplies every value, production-family bundles keep
  /// Sparkle disabled instead of polling or trusting the inherited Omi release system.
  struct ReleaseConfiguration: Equatable {
    let appcastURL: URL
    let sparklePublicKey: String
    let manualDownloadBaseURL: URL
    let releasesURL: URL

    init?(infoDictionary: [String: Any]) {
      guard
        let appcastURL = Self.httpsURL(
          infoDictionary[sparkleFeedInfoKey], disallowInheritedOmiHost: true),
        let manualDownloadBaseURL = Self.httpsURL(
          infoDictionary[manualDownloadInfoKey], disallowInheritedOmiHost: true),
        let releasesURL = Self.httpsURL(
          infoDictionary[releasesInfoKey], disallowInheritedOmiHost: true),
        Self.isOwnedRepositoryReleaseURL(releasesURL),
        let publicKey = Self.trimmedString(infoDictionary[sparklePublicKeyInfoKey]),
        let publicKeyData = Data(base64Encoded: publicKey),
        publicKeyData.count == 32
      else {
        return nil
      }

      self.appcastURL = appcastURL
      self.sparklePublicKey = publicKey
      self.manualDownloadBaseURL = manualDownloadBaseURL
      self.releasesURL = releasesURL
    }

    func manualDownloadURL(channel: String, isBetaIdentity: Bool) -> URL? {
      guard var components = URLComponents(url: manualDownloadBaseURL, resolvingAgainstBaseURL: false)
      else { return nil }

      var queryItems = components.queryItems ?? []
      queryItems.removeAll { $0.name == "channel" || $0.name == "identity" }
      queryItems.append(URLQueryItem(name: "channel", value: channel))
      if isBetaIdentity {
        queryItems.append(URLQueryItem(name: "identity", value: "beta"))
      }
      components.queryItems = queryItems
      return components.url
    }

    private static func trimmedString(_ value: Any?) -> String? {
      guard let value = value as? String else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate static func httpsURL(_ value: Any?, disallowInheritedOmiHost: Bool) -> URL? {
      guard
        let rawValue = trimmedString(value),
        let components = URLComponents(string: rawValue),
        components.scheme?.lowercased() == "https",
        components.user == nil,
        components.password == nil,
        components.fragment == nil,
        let host = components.host?.lowercased(),
        !host.isEmpty,
        let url = components.url
      else { return nil }

      if disallowInheritedOmiHost,
        host == "omi.me" || host.hasSuffix(".omi.me") || host == "basedhardware.com"
          || host.hasSuffix(".basedhardware.com")
      {
        return nil
      }
      return url
    }

    private static func isOwnedRepositoryReleaseURL(_ url: URL) -> Bool {
      guard
        url.host?.lowercased() == "github.com",
        url.query == nil
      else { return false }
      return url.path == "/sruj75/knowledge-athlete/releases"
        || url.path == "/sruj75/knowledge-athlete/releases/"
    }
  }

  /// Preview bundle identity, the explicit Info.plist marker, and the selected backend are
  /// all evaluated together. The reserved identity is the safety boundary: an artifact with
  /// a preview identity is always restricted, even if a packaging error omits its marker.
  struct Configuration: Equatable {
    let bundleIdentifier: String
    let identity: DesktopProductIdentity?
    let isExternalPreview: Bool
    let hasExternalPreviewMarker: Bool
    let externalPreviewBackend: ExternalPreviewBackend?
    let releaseConfiguration: ReleaseConfiguration?

    var isNonProduction: Bool {
      guard let identity else { return false }
      return !identity.isProductionFamily
    }

    var allowsLocalAutomation: Bool {
      identity?.allowsLocalAutomation == true && !isExternalPreview
    }

    var isNamedDevelopmentBundle: Bool {
      identity?.isNamedDevelopment == true
    }

    var allowsSparkleUpdates: Bool {
      identity?.allowsSparkleUpdates == true && releaseConfiguration != nil
    }

    var hasValidExternalPreviewConfiguration: Bool {
      !isExternalPreview
        || (identity?.isPreview == true && hasExternalPreviewMarker && externalPreviewBackend != nil)
    }
  }

  static func configuration(
    bundleIdentifier: String,
    infoDictionary: [String: Any]
  ) -> Configuration {
    let identity = DesktopProductIdentity(bundleIdentifier: bundleIdentifier)
    // Any bundle in the reserved preview namespace remains restricted even when
    // malformed. Only a valid typed preview can pass the packaging-metadata gate.
    let isExternalPreview = bundleIdentifier.hasPrefix(externalPreviewBundleIdentifierPrefix)
    let hasExternalPreviewMarker = infoDictionary[externalPreviewMarkerInfoKey] as? Bool == true
    let externalPreviewBackend = ExternalPreviewBackend(
      infoValue: infoDictionary[externalPreviewBackendInfoKey])
    let releaseConfiguration = ReleaseConfiguration(infoDictionary: infoDictionary)

    return Configuration(
      bundleIdentifier: bundleIdentifier,
      identity: identity,
      isExternalPreview: isExternalPreview,
      hasExternalPreviewMarker: hasExternalPreviewMarker,
      externalPreviewBackend: externalPreviewBackend,
      releaseConfiguration: releaseConfiguration
    )
  }

  static func isExternalPreviewBundleIdentifier(_ bundleIdentifier: String) -> Bool {
    DesktopProductIdentity(bundleIdentifier: bundleIdentifier)?.isPreview == true
  }

  private static var buildConfiguration: Configuration {
    configuration(
      bundleIdentifier: bundleIdentifier,
      infoDictionary: Bundle.main.infoDictionary ?? [:]
    )
  }

  static var bundleIdentifier: String {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
      fatalError("The desktop app bundle has no identifier")
    }
    return bundleIdentifier
  }

  static var sourceProvenance: SourceProvenance? {
    sourceProvenance(infoDictionary: Bundle.main.infoDictionary ?? [:])
  }

  static var isNonProduction: Bool {
    buildConfiguration.isNonProduction
  }

  /// True for every shipped production-family artifact (stable *and* the beta app).
  /// Use `isBetaProductionBundle` when behavior differs between the two.
  static var isProductionBundle: Bool {
    buildConfiguration.identity?.isProductionFamily == true
  }

  /// The separately-installable "Intentive Beta" app. Its update channel is pinned to beta
  /// and it keeps its own isolated on-disk state, so it can run beside stable.
  static var isBetaProductionBundle: Bool {
    buildConfiguration.identity?.family == .beta
  }

  static var isExternalPreview: Bool {
    buildConfiguration.isExternalPreview
  }

  /// Only local development bundles expose the loopback automation/debug bridge. Published
  /// preview apps share the non-production namespace but must never expose that bridge.
  static var allowsLocalAutomation: Bool {
    buildConfiguration.allowsLocalAutomation
  }

  /// Preview/named bundles never consume the shared Sparkle feed. Production-family and
  /// canonical-development bundles additionally require a complete, valid, signed release
  /// configuration; a missing provider value disables Sparkle rather than falling back.
  static var allowsSparkleUpdates: Bool {
    buildConfiguration.allowsSparkleUpdates
  }

  static var hasValidExternalPreviewConfiguration: Bool {
    buildConfiguration.hasValidExternalPreviewConfiguration
  }

  /// Nil is intentional for a malformed preview configuration. Backend routing then fails
  /// closed to production rather than inheriting the local-development default.
  static var externalPreviewBackend: ExternalPreviewBackend? {
    guard buildConfiguration.isExternalPreview, buildConfiguration.hasExternalPreviewMarker else {
      return nil
    }
    return buildConfiguration.externalPreviewBackend
  }

  static var isNamedDevelopmentBundle: Bool {
    buildConfiguration.isNamedDevelopmentBundle
  }

  static var usesLazyDevPermissions: Bool {
    isNamedDevelopmentBundle && UserDefaults.standard.bool(forKey: "devLazyPermissionsEnabled")
  }

  static var displayName: String {
    if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
      !displayName.isEmpty
    {
      return displayName
    }

    if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
      !bundleName.isEmpty
    {
      return bundleName
    }

    return "Intentive"
  }

  private static var releaseConfiguration: ReleaseConfiguration? {
    buildConfiguration.releaseConfiguration
  }

  /// Release tag for the running build, e.g. "v0.11.475+11475-macos".
  /// Matches the tag Codemagic publishes (`v{shortVersion}+{build}-{platform}`).
  static var releaseTag: String? {
    guard
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      !version.isEmpty,
      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      !build.isEmpty
    else {
      return nil
    }
    return "v\(version)+\(build)-macos"
  }

  /// "What's New" target: the GitHub release page for the running build.
  /// Real shipped Stable and Beta builds carry a production-family identity and a
  /// version that maps to a published tag, so deep-link to this version's notes (the
  /// `+` in the tag must be `%2B` in the URL path). Dev/named test bundles carry a
  /// placeholder version with no matching tag, so fall back to the releases list.
  static var changelogURL: URL? {
    changelogURL(
      infoDictionary: Bundle.main.infoDictionary ?? [:],
      isProductionBundle: isProductionBundle,
      releaseTag: releaseTag)
  }

  static func changelogURL(
    infoDictionary: [String: Any],
    isProductionBundle: Bool,
    releaseTag: String?
  ) -> URL? {
    guard let releasesURL = ReleaseConfiguration(infoDictionary: infoDictionary)?.releasesURL else {
      return nil
    }
    guard isProductionBundle, let releaseTag else { return releasesURL }

    var allowedTagCharacters = CharacterSet.alphanumerics
    allowedTagCharacters.insert(charactersIn: "-._~")
    guard let encodedTag = releaseTag.addingPercentEncoding(withAllowedCharacters: allowedTagCharacters)
    else { return nil }
    let tagDirectory = releasesURL.appendingPathComponent("tag", isDirectory: true)
    return URL(string: tagDirectory.absoluteString + encodedTag)
  }

  static var productWebsiteURL: URL? {
    publicDestinationURL(infoKey: productWebsiteInfoKey)
  }

  static var termsURL: URL? {
    publicDestinationURL(infoKey: termsInfoKey)
  }

  static var privacyURL: URL? {
    publicDestinationURL(infoKey: privacyInfoKey)
  }

  static var supportURL: URL? {
    publicDestinationURL(infoKey: supportInfoKey)
  }

  struct SettingsExternalDestination: Equatable {
    let title: String
    let url: URL
  }

  static var currentSettingsExternalDestinations: [SettingsExternalDestination] {
    settingsExternalDestinations(infoDictionary: Bundle.main.infoDictionary ?? [:])
  }

  static func settingsExternalDestinations(
    infoDictionary: [String: Any]
  ) -> [SettingsExternalDestination] {
    [
      ("Visit Website", productWebsiteInfoKey),
      ("Terms of Service", termsInfoKey),
    ].compactMap { title, infoKey in
      guard let url = publicDestinationURL(infoDictionary: infoDictionary, infoKey: infoKey)
      else { return nil }
      return SettingsExternalDestination(title: title, url: url)
    }
  }

  static func publicDestinationURL(
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    infoKey: String
  ) -> URL? {
    guard
      let url = ReleaseConfiguration.httpsURL(
        infoDictionary[infoKey], disallowInheritedOmiHost: true),
      let host = url.host?.lowercased(),
      host == "heyintentive.com" || host.hasSuffix(".heyintentive.com")
    else { return nil }
    return url
  }

  static var ownedBundleIdentifier: String? {
    DesktopProductIdentity(bundleIdentifier: Bundle.main.bundleIdentifier)?.bundleIdentifier
  }

  static let agentDatabaseFilename = DesktopProductIdentity.agentRuntimeDatabaseFilename

  static var currentUpdateChannel: String {
    // The Intentive Beta app is permanently a beta-channel client; a stray defaults value
    // (imported settings, sync) must never flip it to stable-identity updates.
    if isBetaProductionBundle { return "beta" }
    let raw = UserDefaults.standard.string(forKey: updateChannelDefaultsKey) ?? "stable"
    return raw == "staging" ? "beta" : raw
  }

  static var manualDownloadURL: URL? {
    releaseConfiguration?.manualDownloadURL(
      channel: currentUpdateChannel,
      isBetaIdentity: isBetaProductionBundle)
  }

  static func manualDownloadURL(
    infoDictionary: [String: Any],
    channel: String,
    isBetaIdentity: Bool
  ) -> URL? {
    ReleaseConfiguration(infoDictionary: infoDictionary)?.manualDownloadURL(
      channel: channel,
      isBetaIdentity: isBetaIdentity)
  }

  static var inferredUpdateChannel: String {
    let bundlePath = Bundle.main.bundleURL.path.lowercased()
    let display = displayName.lowercased()
    let bundle = bundleIdentifier.lowercased()

    if bundle.contains("beta")
      || display.contains("beta")
      || bundlePath.contains("/beta")
      || bundlePath.contains("intentive beta")
    {
      return "beta"
    }

    return "stable"
  }

  /// Only set the channel on first launch when no preference exists yet.
  /// Never overwrite a user-chosen channel (e.g. beta selected in settings).
  @discardableResult
  static func syncUpdateChannelOnFirstLaunch() -> String? {
    guard UserDefaults.standard.string(forKey: updateChannelDefaultsKey) == nil else { return nil }
    let resolved = probeFreshInstallUpdateChannel()
    UserDefaults.standard.set(resolved, forKey: updateChannelDefaultsKey)
    return resolved
  }

  /// One-time migration for users whose beta channel was overwritten to stable
  /// by the syncUpdateChannelWithInstalledApp() bug (commit 8c60fafe8, March 27 2026).
  /// Re-checks the appcast: if the current build is ahead of latest stable, restore beta.
  static func migrateBetaChannelOverwrite() {
    migrateBetaChannelOverwrite(probeAppcast: probeFreshInstallUpdateChannel)
  }

  static func migrateBetaChannelOverwrite(probeAppcast: () -> String) {
    guard !UserDefaults.standard.bool(forKey: betaOverwriteMigrationKey) else { return }
    UserDefaults.standard.set(true, forKey: betaOverwriteMigrationKey)

    // A fresh install has no stored channel, so there is nothing to restore — and
    // syncUpdateChannelOnFirstLaunch() probes the same appcast moments later. Probing
    // here as well made every new install pay for two serial launch-blocking round
    // trips to answer one question.
    guard UserDefaults.standard.string(forKey: updateChannelDefaultsKey) != nil else { return }
    guard currentUpdateChannel == "stable" else { return }

    if probeAppcast() == "beta" {
      UserDefaults.standard.set("beta", forKey: updateChannelDefaultsKey)
    }
  }

  static func prepareUpdateChannelForBackendRouting() {
    guard isProductionBundle else { return }
    guard allowsSparkleUpdates else { return }
    // Beta identity: channel is pinned, so the launch-blocking appcast probes and the
    // stable-overwrite migration have nothing to decide.
    guard !isBetaProductionBundle else { return }

    migrateBetaChannelOverwrite()
    if UserDefaults.standard.string(forKey: updateChannelDefaultsKey) == nil {
      syncUpdateChannelOnFirstLaunch()
    }
  }

  static func resolveFreshInstallUpdateChannel(
    currentBuild: Int,
    fallback: String,
    appcastXML: String
  ) -> String {
    if fallback == "beta" {
      return "beta"
    }

    guard let latestStableBuild = latestStableBuildNumber(in: appcastXML) else {
      return fallback
    }

    return currentBuild > latestStableBuild ? "beta" : "stable"
  }

  static func latestStableBuildNumber(in appcastXML: String) -> Int? {
    let itemPattern = #"<item>(.*?)</item>"#
    let versionPattern = #"<sparkle:version>(\d+)</sparkle:version>"#

    guard
      let itemRegex = try? NSRegularExpression(
        pattern: itemPattern,
        options: [.dotMatchesLineSeparators]
      ),
      let versionRegex = try? NSRegularExpression(pattern: versionPattern)
    else {
      return nil
    }

    let xmlRange = NSRange(appcastXML.startIndex..<appcastXML.endIndex, in: appcastXML)
    var latestStableBuild: Int?

    for match in itemRegex.matches(in: appcastXML, options: [], range: xmlRange) {
      guard
        let itemRange = Range(match.range(at: 1), in: appcastXML)
      else {
        continue
      }

      let itemXML = String(appcastXML[itemRange])
      if itemXML.contains("<sparkle:channel>beta</sparkle:channel>")
        || itemXML.contains("<sparkle:channel>staging</sparkle:channel>")
      {
        continue
      }

      let itemNSRange = NSRange(itemXML.startIndex..<itemXML.endIndex, in: itemXML)
      guard
        let versionMatch = versionRegex.firstMatch(in: itemXML, options: [], range: itemNSRange),
        let versionRange = Range(versionMatch.range(at: 1), in: itemXML),
        let build = Int(itemXML[versionRange])
      else {
        continue
      }

      latestStableBuild = max(latestStableBuild ?? build, build)
    }

    return latestStableBuild
  }

  private static var currentBuildNumber: Int? {
    guard
      let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    else {
      return nil
    }

    return Int(raw)
  }

  private static func probeFreshInstallUpdateChannel() -> String {
    probeFreshInstallUpdateChannel(
      fallback: inferredUpdateChannel,
      currentBuild: currentBuildNumber,
      mainThreadBudget: channelProbeMainThreadBudget,
      fetchAppcast: fetchDesktopAppcast,
      persistLateCorrection: { storeLateChannelCorrection($0) }
    )
  }

  /// Resolve the channel for an install with no stored preference.
  ///
  /// This runs on the main thread during launch (`AppState.init` needs the channel before
  /// it loads backend URLs), so it waits at most `mainThreadBudget` for the appcast. Past
  /// that it returns the bundle-inferred channel and lets the request finish in the
  /// background: a late answer that disagrees is written through `persistLateCorrection`,
  /// so the next launch starts on the right channel.
  ///
  /// It used to block for up to 3.5s inline, and pinned the timed-out guess permanently.
  static func probeFreshInstallUpdateChannel(
    fallback: String,
    currentBuild: Int?,
    mainThreadBudget: TimeInterval,
    fetchAppcast: @escaping (@escaping @Sendable (String?) -> Void) -> Void,
    persistLateCorrection: @escaping @Sendable (String) -> Void
  ) -> String {
    if fallback == "beta" {
      return "beta"
    }

    guard let currentBuild else {
      return fallback
    }

    let appcast = AppcastProbeResult()
    let semaphore = DispatchSemaphore(value: 0)

    fetchAppcast { xml in
      appcast.set(xml)
      semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + mainThreadBudget) == .success {
      guard let appcastXML = appcast.value else { return fallback }
      return resolveFreshInstallUpdateChannel(
        currentBuild: currentBuild,
        fallback: fallback,
        appcastXML: appcastXML
      )
    }

    DispatchQueue.global(qos: .utility).async {
      guard
        semaphore.wait(timeout: .now() + channelProbeRequestTimeout + 0.5) == .success,
        let appcastXML = appcast.value
      else { return }

      let resolved = resolveFreshInstallUpdateChannel(
        currentBuild: currentBuild,
        fallback: fallback,
        appcastXML: appcastXML
      )
      guard resolved != fallback else { return }
      persistLateCorrection(resolved)
    }

    return fallback
  }

  private static func fetchDesktopAppcast(completion: @escaping @Sendable (String?) -> Void) {
    guard let desktopAppcastURL = releaseConfiguration?.appcastURL else {
      completion(nil)
      return
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = channelProbeRequestTimeout
    configuration.timeoutIntervalForResource = channelProbeRequestTimeout

    let session = URLSession(configuration: configuration)
    session.dataTask(with: desktopAppcastURL) { data, _, _ in
      defer { session.finishTasksAndInvalidate() }
      guard let data, let xml = String(data: data, encoding: .utf8) else {
        completion(nil)
        return
      }
      completion(xml)
    }.resume()
  }

  private static func storeLateChannelCorrection(_ resolved: String) {
    DispatchQueue.main.async {
      // Only upgrade the guess this probe stored — never clobber a channel the user
      // picked in Settings while the appcast was still in flight.
      guard currentUpdateChannel == "stable" else { return }
      UserDefaults.standard.set(resolved, forKey: updateChannelDefaultsKey)
      log("AppBuild: appcast answered after the launch budget; update channel set to \(resolved)")
    }
  }
}

private final class AppcastProbeResult: @unchecked Sendable {
  private let lock = NSLock()
  private var xml: String?

  func set(_ value: String?) {
    lock.lock()
    defer { lock.unlock() }
    xml = value
  }

  var value: String? {
    lock.lock()
    defer { lock.unlock() }
    return xml
  }
}
