import Foundation
import OmiSupport

/// Stable identity for unsent text in one conversational composer.
///
/// Drafts are deliberately separate from chat/session persistence: they are local UI
/// intent and never become conversation history until a send is accepted.
struct ChatDraftKey: Hashable, Sendable {
  let scope: String
  let contextID: String

  static func mainChat(contextID: String = "default") -> Self {
    Self(scope: "main_chat", contextID: contextID)
  }

  static let floatingMain = Self(scope: "floating_chat", contextID: "main")
  static let onboardingMain = Self(scope: "onboarding_chat", contextID: "main")
  static let onboardingFloating = Self(scope: "onboarding_chat", contextID: "floating")

  static func floatingAgent(_ id: UUID) -> Self {
    Self(scope: "floating_agent", contextID: id.uuidString.lowercased())
  }

}

private struct ChatDraftRecord: Codable, Sendable {
  let version: Int
  let ownerID: String
  let scope: String
  let contextID: String
  let text: String
  let attachments: [ChatDraftAttachmentRecord]?
  let updatedAt: Date
}

private struct ChatDraftAttachmentRecord: Codable, Sendable {
  let id: String
  let fileName: String
  let mimeType: String
  let localFileURL: URL

  init?(_ attachment: ChatAttachment) {
    guard attachment.state == .localOnly,
      let localFileURL = attachment.localFileURL,
      localFileURL.isFileURL
    else { return nil }
    id = attachment.id
    fileName = attachment.fileName
    mimeType = attachment.mimeType
    self.localFileURL = localFileURL
  }

  func attachment(fileManager: FileManager) -> ChatAttachment? {
    guard fileManager.fileExists(atPath: localFileURL.path) else { return nil }
    let data: Data?
    if mimeType.hasPrefix("image/"),
      let attributes = try? fileManager.attributesOfItem(atPath: localFileURL.path),
      let size = attributes[.size] as? NSNumber,
      size.intValue <= 25 * 1_024 * 1_024
    {
      data = try? Data(contentsOf: localFileURL)
    } else {
      data = nil
    }
    return ChatAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      data: data,
      localFileURL: localFileURL,
      state: .localOnly
    )
  }
}

private struct ChatDraftSnapshot: Sendable {
  var text: String
  var attachments: [ChatAttachment]
}

/// Lightweight local persistence for conversational drafts.
///
/// Each draft is an independent, atomically replaced record under Application
/// Support. Writes are coalesced on a serial background queue, so the typing path
/// only updates in-memory UI state. A corrupt record cannot affect another draft.
@MainActor
final class ChatDraftStore {
  static let shared = ChatDraftStore()

  private struct StorageID: Hashable, Sendable {
    let ownerID: String
    let key: ChatDraftKey
  }

  private let rootURL: URL
  private let fileManager: FileManager
  private let writeDelay: TimeInterval
  private let ownerIDProvider: () -> String?
  private let persistenceQueue = DispatchQueue(label: "com.heyintentive.intentive.desktop.chat-drafts", qos: .utility)

  private var cache: [StorageID: ChatDraftSnapshot] = [:]
  private var loaded: Set<StorageID> = []
  private var pendingWrites: [StorageID: DispatchWorkItem] = [:]
  private var writeGenerations: [StorageID: Int] = [:]

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    writeDelay: TimeInterval = 0.2,
    ownerIDProvider: @escaping () -> String? = {
      UserDefaults.standard.string(forKey: .authUserId)
    }
  ) {
    self.fileManager = fileManager
    self.writeDelay = writeDelay
    self.ownerIDProvider = ownerIDProvider

    if let rootURL {
      self.rootURL = rootURL
    } else {
      self.rootURL =
        DesktopLocalProfile.applicationSupportURL()
        .appendingPathComponent("Drafts/v1", isDirectory: true)
    }
  }

  func text(for key: ChatDraftKey, ownerID: String? = nil) -> String {
    let id = storageID(for: key, ownerID: ownerID)
    return snapshot(for: id).text
  }

  func attachments(for key: ChatDraftKey, ownerID: String? = nil) -> [ChatAttachment] {
    let id = storageID(for: key, ownerID: ownerID)
    return snapshot(for: id).attachments
  }

  func setText(_ text: String, for key: ChatDraftKey, ownerID: String? = nil) {
    let id = storageID(for: key, ownerID: ownerID)
    var value = snapshot(for: id)
    value.text = text
    cache[id] = value
    scheduleWrite(for: id, snapshot: value)
  }

  func setAttachments(
    _ attachments: [ChatAttachment],
    for key: ChatDraftKey,
    ownerID: String? = nil
  ) {
    let id = storageID(for: key, ownerID: ownerID)
    var value = snapshot(for: id)
    value.attachments = attachments.filter { ChatDraftAttachmentRecord($0) != nil }
    cache[id] = value
    scheduleWrite(for: id, snapshot: value)
  }

  func clear(_ key: ChatDraftKey, ownerID: String? = nil) {
    let id = storageID(for: key, ownerID: ownerID)
    let value = ChatDraftSnapshot(text: "", attachments: [])
    loaded.insert(id)
    cache[id] = value
    scheduleWrite(for: id, snapshot: value)
  }

  func managedAttachmentURIs(ownerID: String? = nil) -> Set<String> {
    let normalizedOwnerID = Self.normalizedOwnerID(ownerID ?? ownerIDProvider())
    var values = Set(
      cache
        .filter { $0.key.ownerID == normalizedOwnerID }
        .flatMap { $0.value.attachments }
        .compactMap { $0.localFileURL?.absoluteString }
    )
    let ownerURL = rootURL.appendingPathComponent(Self.fileNameComponent(normalizedOwnerID), isDirectory: true)
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: ownerURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else { return values }
    for file in files where file.pathExtension == "json" {
      guard let data = try? Data(contentsOf: file),
        let record = try? JSONDecoder().decode(ChatDraftRecord.self, from: data),
        record.ownerID == normalizedOwnerID
      else { continue }
      let recordID = StorageID(
        ownerID: normalizedOwnerID,
        key: ChatDraftKey(scope: record.scope, contextID: record.contextID)
      )
      if loaded.contains(recordID) { continue }
      for attachment in record.attachments ?? [] {
        values.insert(attachment.localFileURL.absoluteString)
      }
    }
    return values
  }

  /// Drops persisted main-chat drafts whose catalog identity no longer exists.
  /// This runs before managed attachment GC so a crash between catalog deletion
  /// and draft cleanup cannot retain orphaned bytes forever.
  func reconcileMainChatCatalog(ownerID: String, retainingChatIDs: Set<String>) {
    let normalizedOwnerID = Self.normalizedOwnerID(ownerID)
    var ids = Set(
      cache.keys.filter {
        $0.ownerID == normalizedOwnerID && $0.key.scope == "main_chat"
      })
    let ownerURL = rootURL.appendingPathComponent(
      Self.fileNameComponent(normalizedOwnerID),
      isDirectory: true
    )
    if let files = try? fileManager.contentsOfDirectory(
      at: ownerURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) {
      for file in files where file.pathExtension == "json" {
        guard let data = try? Data(contentsOf: file),
          let record = try? JSONDecoder().decode(ChatDraftRecord.self, from: data),
          record.ownerID == normalizedOwnerID,
          record.scope == "main_chat"
        else { continue }
        ids.insert(
          StorageID(
            ownerID: normalizedOwnerID,
            key: .mainChat(contextID: record.contextID)
          ))
      }
    }

    for id in ids where !retainingChatIDs.contains(id.key.contextID) {
      clear(id.key, ownerID: normalizedOwnerID)
    }
    flush()
  }

  /// Synchronously persists the latest in-memory values. Used for orderly app
  /// termination and tests; normal edits remain off the main thread.
  func flush() {
    let snapshots = pendingWrites.keys.map { id in
      (id, cache[id] ?? ChatDraftSnapshot(text: "", attachments: []))
    }
    pendingWrites.values.forEach { $0.cancel() }
    pendingWrites.removeAll()
    let rootURL = rootURL
    let flushWork: @Sendable () -> Void = {
      for (id, snapshot) in snapshots {
        Self.persist(snapshot: snapshot, id: id, rootURL: rootURL)
      }
    }
    persistenceQueue.sync(execute: flushWork)
  }

  /// Explicit sign-out is destructive for that account's drafts. Light auth
  /// invalidation intentionally does not call this, so reauthentication retains text.
  func clearAll(ownerID: String?) {
    let normalizedOwnerID = Self.normalizedOwnerID(ownerID)
    let matchingIDs = Set(cache.keys.filter { $0.ownerID == normalizedOwnerID })
    for id in matchingIDs {
      pendingWrites[id]?.cancel()
      pendingWrites[id] = nil
      cache[id] = nil
      loaded.remove(id)
    }

    let ownerURL = rootURL.appendingPathComponent(Self.fileNameComponent(normalizedOwnerID), isDirectory: true)
    let removeWork: @Sendable () -> Void = {
      try? FileManager.default.removeItem(at: ownerURL)
    }
    persistenceQueue.sync(execute: removeWork)
  }

  private func storageID(for key: ChatDraftKey, ownerID: String?) -> StorageID {
    StorageID(
      ownerID: Self.normalizedOwnerID(ownerID ?? ownerIDProvider()),
      key: key
    )
  }

  private func fileURL(for id: StorageID) -> URL {
    let ownerURL = rootURL.appendingPathComponent(Self.fileNameComponent(id.ownerID), isDirectory: true)
    let key = "\(id.key.scope)\u{0}\(id.key.contextID)"
    return ownerURL.appendingPathComponent(Self.fileNameComponent(key)).appendingPathExtension("json")
  }

  private func snapshot(for id: StorageID) -> ChatDraftSnapshot {
    if loaded.contains(id) {
      return cache[id] ?? ChatDraftSnapshot(text: "", attachments: [])
    }

    loaded.insert(id)
    guard let data = try? Data(contentsOf: fileURL(for: id)),
      let record = try? JSONDecoder().decode(ChatDraftRecord.self, from: data),
      record.version == 1 || record.version == 2,
      record.ownerID == id.ownerID,
      record.scope == id.key.scope,
      record.contextID == id.key.contextID
    else {
      let empty = ChatDraftSnapshot(text: "", attachments: [])
      cache[id] = empty
      return empty
    }

    let value = ChatDraftSnapshot(
      text: record.text,
      attachments: (record.attachments ?? []).compactMap { $0.attachment(fileManager: fileManager) }
    )
    cache[id] = value
    return value
  }

  private func scheduleWrite(for id: StorageID, snapshot: ChatDraftSnapshot) {
    pendingWrites[id]?.cancel()
    let generation = (writeGenerations[id] ?? 0) + 1
    writeGenerations[id] = generation
    let rootURL = rootURL
    // The work item runs on `persistenceQueue` (not the main actor). Under Swift 6
    // the runtime asserts executor assumptions, so the block must be a non-isolated
    // `@Sendable` closure — an inferred `@MainActor` block dispatched off the main
    // queue would trap (`dispatch_assert_queue_fail`). `persist` is a static call;
    // the in-memory bookkeeping hops back to the main actor via a `Task`.
    let block: @Sendable () -> Void = { [weak self] in
      Self.persist(snapshot: snapshot, id: id, rootURL: rootURL)
      Task { @MainActor [weak self] in
        guard let self, self.writeGenerations[id] == generation else { return }
        self.pendingWrites[id] = nil
      }
    }
    let workItem = DispatchWorkItem(block: block)
    pendingWrites[id] = workItem
    persistenceQueue.asyncAfter(deadline: .now() + writeDelay, execute: workItem)
  }

  private nonisolated static func persist(
    snapshot: ChatDraftSnapshot,
    id: StorageID,
    rootURL: URL
  ) {
    let fileManager = FileManager.default
    let ownerURL = rootURL.appendingPathComponent(fileNameComponent(id.ownerID), isDirectory: true)
    let key = "\(id.key.scope)\u{0}\(id.key.contextID)"
    let url = ownerURL.appendingPathComponent(fileNameComponent(key)).appendingPathExtension("json")

    let attachments = snapshot.attachments.compactMap(ChatDraftAttachmentRecord.init)
    if snapshot.text.isEmpty && attachments.isEmpty {
      try? fileManager.removeItem(at: url)
      return
    }

    do {
      try fileManager.createDirectory(at: ownerURL, withIntermediateDirectories: true)
      let record = ChatDraftRecord(
        version: 2,
        ownerID: id.ownerID,
        scope: id.key.scope,
        contextID: id.key.contextID,
        text: snapshot.text,
        attachments: attachments,
        updatedAt: Date()
      )
      let data = try JSONEncoder().encode(record)
      try data.write(to: url, options: .atomic)
    } catch {
      // Draft contents are private user text, so never include them in logs.
      logError("ChatDraftStore: failed to persist \(id.key.scope) draft", error: error)
    }
  }

  private static func normalizedOwnerID(_ ownerID: String?) -> String {
    let trimmed = ownerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "local" : trimmed
  }

  private nonisolated static func fileNameComponent(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
  }
}
