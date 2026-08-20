import CryptoKit
import Foundation
import OmiSupport

actor LocalChatAttachmentStore {
  static let shared = LocalChatAttachmentStore()

  private let rootURL: URL
  private let fileManager: FileManager
  private var protectedMaterializationPaths: Set<String> = []

  init(
    rootURL: URL = DesktopLocalProfile.applicationSupportURL()
      .appendingPathComponent("ChatAttachments", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true),
    fileManager: FileManager = .default
  ) {
    self.rootURL = rootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  func materialize(
    _ attachment: ChatAttachment,
    ownerID: String,
    chatID: String
  ) throws -> ChatAttachment {
    let directory = directoryURL(ownerID: ownerID, chatID: chatID)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let fileName = Self.safeFileName(attachment.fileName)
    let destination = directory.appendingPathComponent(
      "\(UUID().uuidString.lowercased())-\(fileName)",
      isDirectory: false
    )
    let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
    defer { try? fileManager.removeItem(at: temporary) }

    if let data = attachment.data {
      try data.write(to: temporary, options: .atomic)
    } else if let source = attachment.localFileURL, source.isFileURL {
      try copyRegularFileBytes(from: source, to: temporary)
    } else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    try fileManager.moveItem(at: temporary, to: destination)
    protectedMaterializationPaths.insert(destination.standardizedFileURL.path)

    var managed = attachment
    managed.localFileURL = destination
    managed.state = .localOnly
    return managed
  }

  func garbageCollect(
    ownerID: String,
    retaining retainedURIs: Set<String>
  ) throws {
    let ownerDirectory = ownerDirectoryURL(ownerID: ownerID)
    guard fileManager.fileExists(atPath: ownerDirectory.path) else { return }
    var retainedPaths = Set(
      retainedURIs.compactMap { uri -> String? in
        guard let url = URL(string: uri), url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        return Self.isDescendant(path: path, of: rootURL.path) ? path : nil
      })
    retainedPaths.formUnion(protectedMaterializationPaths)
    for chatDirectory in try fileManager.contentsOfDirectory(
      at: ownerDirectory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      for file in try fileManager.contentsOfDirectory(
        at: chatDirectory,
        includingPropertiesForKeys: nil,
        options: []
      ) where !retainedPaths.contains(file.standardizedFileURL.path) {
        try fileManager.removeItem(at: file)
      }
      if (try fileManager.contentsOfDirectory(atPath: chatDirectory.path)).isEmpty {
        try fileManager.removeItem(at: chatDirectory)
      }
    }
    if (try fileManager.contentsOfDirectory(atPath: ownerDirectory.path)).isEmpty {
      try fileManager.removeItem(at: ownerDirectory)
    }
  }

  /// Remove abandoned staged copies only when they are inside the exact
  /// owner/chat directory managed by this store. Source files are never
  /// eligible for removal.
  func discardManagedFiles(
    _ fileURLs: [URL],
    ownerID: String,
    chatID: String
  ) throws {
    let directory = directoryURL(ownerID: ownerID, chatID: chatID)
    for fileURL in fileURLs where fileURL.isFileURL {
      let path = fileURL.standardizedFileURL.path
      guard Self.isDescendant(path: path, of: directory.path) else { continue }
      protectedMaterializationPaths.remove(path)
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(at: fileURL)
      }
    }
    if fileManager.fileExists(atPath: directory.path),
      (try fileManager.contentsOfDirectory(atPath: directory.path)).isEmpty
    {
      try fileManager.removeItem(at: directory)
    }
  }

  /// Explicit sign-out removes only draft-owned copies for the selected owner.
  /// The URL allow-list comes from that owner's persisted drafts, and the
  /// owner-directory fence prevents another account or a source file from
  /// becoming eligible even if a malformed record supplies it.
  func discardManagedDraftFiles(
    _ fileURLs: [URL],
    ownerID: String
  ) throws {
    let ownerDirectory = ownerDirectoryURL(ownerID: ownerID)
    for fileURL in fileURLs where fileURL.isFileURL {
      let path = fileURL.standardizedFileURL.path
      guard Self.isDescendant(path: path, of: ownerDirectory.path) else { continue }
      protectedMaterializationPaths.remove(path)
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(at: fileURL)
      }
      let chatDirectory = fileURL.deletingLastPathComponent().standardizedFileURL
      if Self.isDescendant(path: chatDirectory.path, of: ownerDirectory.path),
        fileManager.fileExists(atPath: chatDirectory.path),
        (try fileManager.contentsOfDirectory(atPath: chatDirectory.path)).isEmpty
      {
        try fileManager.removeItem(at: chatDirectory)
      }
    }
    if fileManager.fileExists(atPath: ownerDirectory.path),
      (try fileManager.contentsOfDirectory(atPath: ownerDirectory.path)).isEmpty
    {
      try fileManager.removeItem(at: ownerDirectory)
    }
  }

  func releaseMaterializationProtection(_ fileURLs: [URL]) {
    for fileURL in fileURLs where fileURL.isFileURL {
      protectedMaterializationPaths.remove(fileURL.standardizedFileURL.path)
    }
  }

  /// Stream an opened regular file into a new app-owned inode. Resolving the
  /// selected path before opening dereferences symbolic links, so the managed
  /// copy cannot keep depending on a target that may later move or disappear.
  private func copyRegularFileBytes(from source: URL, to destination: URL) throws {
    let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
    let values = try resolvedSource.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
    guard fileManager.createFile(atPath: destination.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }

    let input = try FileHandle(forReadingFrom: resolvedSource)
    let output = try FileHandle(forWritingTo: destination)
    defer {
      try? input.close()
      try? output.close()
    }
    while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
      try output.write(contentsOf: chunk)
    }
    try output.synchronize()
  }

  private func directoryURL(ownerID: String, chatID: String) -> URL {
    ownerDirectoryURL(ownerID: ownerID)
      .appendingPathComponent(Self.pathComponent(for: chatID), isDirectory: true)
  }

  private func ownerDirectoryURL(ownerID: String) -> URL {
    rootURL.appendingPathComponent(Self.pathComponent(for: ownerID), isDirectory: true)
  }

  private static func pathComponent(for identity: String) -> String {
    SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func safeFileName(_ candidate: String) -> String {
    let name = URL(fileURLWithPath: candidate).lastPathComponent
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ "))
    let sanitized = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
    let result = String(sanitized).trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? "attachment" : String(result.prefix(180))
  }

  private static func isDescendant(path: String, of root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
  }
}
