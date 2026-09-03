import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct LocalUserDataExportAction {
  enum Outcome: Equatable {
    case cancelled
    case saved(URL)
  }

  private let chooseDestination: () -> URL?
  private let performExport: (String, URL) async throws -> Void

  init(
    chooseDestination: @escaping () -> URL?,
    performExport: @escaping (String, URL) async throws -> Void
  ) {
    self.chooseDestination = chooseDestination
    self.performExport = performExport
  }

  func perform(ownerID: String) async throws -> Outcome {
    guard let destination = chooseDestination() else { return .cancelled }
    try await performExport(ownerID, destination)
    return .saved(destination)
  }

  static let live = LocalUserDataExportAction(
    chooseDestination: {
      let panel = NSSavePanel()
      panel.title = "Export My Data"
      panel.prompt = "Export"
      panel.allowedContentTypes = [.json]
      panel.canCreateDirectories = true
      panel.isExtensionHidden = false
      panel.nameFieldStringValue = defaultFilename()
      return panel.runModal() == .OK ? panel.url : nil
    },
    performExport: { ownerID, destination in
      try await LocalUserDataExport().export(ownerID: ownerID, to: destination)
    })

  static func defaultFilename(now: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return "intentive-data-export-\(formatter.string(from: now)).json"
  }
}
