import CryptoKit
import Foundation
import LocalAuthentication
import OmiSupport
import Security

enum ClientDeviceKeychainReadResult {
  case found(String)
  case missing
  case unavailable(OSStatus)
}

/// Stable per-installation device identity for capture provenance (mirrors Flutter `deviceIdHash`).
final class ClientDeviceService {
  nonisolated(unsafe) static let shared = ClientDeviceService()

  private let keychainAccount = "install-uuid"
  private let devInstallIdDefaultsKey: DefaultsKey = .clientDeviceDevInstallId
  private let installIdMirrorDefaultsKey: DefaultsKey = .clientDeviceInstallIdMirror
  private let bundleIdentifier: String?
  private let userDefaults: UserDefaults
  private let keychainReader: (() -> ClientDeviceKeychainReadResult)?
  private let keychainWriter: ((String) -> Void)?
  private let cacheLock = NSLock()
  private var cachedInstallId: String?

  /// Team+bundle scoped service for this process. It never queries a foreign or
  /// unscoped service whose ACL could trigger a Keychain password prompt.
  private var keychainService: String {
    DesktopKeychainStore.scopedService(
      DesktopKeychainStore.clientDeviceServiceBase,
      bundleID: bundleIdentifier ?? Bundle.main.bundleIdentifier ?? "unknown.bundle"
    )
  }

  init(
    bundleIdentifier: String? = Bundle.main.bundleIdentifier,
    userDefaults: UserDefaults = .standard,
    keychainReader: (() -> ClientDeviceKeychainReadResult)? = nil,
    keychainWriter: ((String) -> Void)? = nil
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.userDefaults = userDefaults
    self.keychainReader = keychainReader
    self.keychainWriter = keychainWriter
  }

  var deviceIdHash: String {
    let installId = resolveInstallId()
    let digest = SHA256.hash(data: Data(installId.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
  }

  /// Contract: `{platform}_{hash}` for retained auth, abuse, update, and metrics identity.
  var clientDeviceId: String {
    "macos_\(deviceIdHash)"
  }

  private func resolveInstallId() -> String {
    cacheLock.lock()
    defer { cacheLock.unlock() }
    if let cached = cachedInstallId {
      return cached
    }
    let resolved = loadOrCreateInstallId()
    cachedInstallId = resolved
    return resolved
  }

  private func loadOrCreateInstallId() -> String {
    guard let identity = DesktopProductIdentity(bundleIdentifier: bundleIdentifier) else {
      // An unrecognized or foreign bundle may run in a test host, but it must not
      // create product defaults or Keychain state. Keep one process-local value.
      log("ClientDeviceService: refusing persistent installation identity for unknown bundle")
      return UUID().uuidString
    }
    // All owned non-production bundles stay out of Keychain entirely —
    // UserDefaults is enough for disposable local identity and never prompts.
    // Owned production Beta/Stable use the team+bundle scoped Keychain item.
    if !identity.isProductionFamily {
      return loadOrCreateDevInstallId()
    }
    switch keychainReader?() ?? readKeychainInstallId() {
    case .found(let existing):
      userDefaults.set(existing, forKey: installIdMirrorDefaultsKey)
      return existing
    case .missing:
      // v0.12.64 moved production builds to a team+bundle scoped Keychain
      // service. Existing installs have their prior stable value in this
      // mirror, so migrate it instead of changing the provenance identity.
      if let mirror = userDefaults.string(forKey: installIdMirrorDefaultsKey), !mirror.isEmpty {
        saveKeychainInstallId(mirror)
        return mirror
      }
      let fresh = UUID().uuidString
      saveKeychainInstallId(fresh)
      userDefaults.set(fresh, forKey: installIdMirrorDefaultsKey)
      return fresh
    case .unavailable(let status):
      // Denied prompt or transient keychain failure. Never rotate the item here —
      // and never fall through to the legacy unscoped service (that prompts).
      log("ClientDeviceService: keychain read unavailable (status \(status)); using mirror fallback")
      if let mirror = userDefaults.string(forKey: installIdMirrorDefaultsKey), !mirror.isEmpty {
        return mirror
      }
      let fallback = UUID().uuidString
      userDefaults.set(fallback, forKey: installIdMirrorDefaultsKey)
      return fallback
    }
  }

  private func loadOrCreateDevInstallId() -> String {
    if let existing = userDefaults.string(forKey: devInstallIdDefaultsKey), !existing.isEmpty {
      return existing
    }
    let fresh = UUID().uuidString
    userDefaults.set(fresh, forKey: devInstallIdDefaultsKey)
    return fresh
  }

  private func readKeychainInstallId() -> ClientDeviceKeychainReadResult {
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationContext as String: context,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
        return .missing
      }
      return .found(value)
    case errSecItemNotFound:
      return .missing
    default:
      // errSecAuthFailed / errSecUserCanceled / errSecInteractionNotAllowed etc.
      return .unavailable(status)
    }
  }

  private func saveKeychainInstallId(_ value: String) {
    if let keychainWriter {
      keychainWriter(value)
      return
    }
    let data = Data(value.utf8)
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecUseAuthenticationContext as String: context,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    }
    if updateStatus != errSecItemNotFound {
      // Do not SecItemDelete+Add on auth failure — that can prompt. Fail closed;
      // the mirror fallback in loadOrCreateInstallId covers continuity.
      log("ClientDeviceService: keychain update unavailable (status \(updateStatus))")
      return
    }
    var addQuery = query
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus != errSecSuccess {
      log("ClientDeviceService: keychain add unavailable (status \(addStatus))")
    }
  }
}
