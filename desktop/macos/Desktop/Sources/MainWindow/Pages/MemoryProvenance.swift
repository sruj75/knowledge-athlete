import Foundation

/// One glanceable fact about where a memory came from.
struct MemoryProvenanceFact: Equatable, Identifiable {
  let icon: String
  let label: String

  var id: String { "\(icon)|\(label)" }
}

/// Resolves retained local provenance without external-device mappings.
enum MemoryProvenance {
  static let appTagPrefix = "app:"

  static func facts(for memory: MemoryItem) -> [MemoryProvenanceFact] {
    var facts: [MemoryProvenanceFact] = []

    if let sourceName = memory.sourceName {
      facts.append(MemoryProvenanceFact(icon: memory.sourceIcon, label: sourceName))
    }

    if let app = appName(for: memory) {
      facts.append(MemoryProvenanceFact(icon: "app.dashed", label: app))
    }

    if memory.manuallyAdded {
      facts.append(MemoryProvenanceFact(icon: "hand.point.up.left", label: "Added by you"))
    }

    if let micName = memory.inputDeviceName, !micName.isEmpty {
      facts.append(MemoryProvenanceFact(icon: "mic", label: micName))
    }

    if let confidence = memory.confidenceString {
      facts.append(MemoryProvenanceFact(icon: "gauge.medium", label: "\(confidence) confidence"))
    }

    return facts
  }

  /// The capturing app, carried as an `app:<name>` tag rather than a field.
  ///
  /// "Unknown" and "Unknown Application/Browser" are values the extractor emits
  /// when it could not tell; naming them tells the user nothing and reads as a
  /// worse answer than the honest absence of one.
  static func appName(for memory: MemoryItem) -> String? {
    if let sourceApp = memory.sourceApp, !sourceApp.isEmpty { return sourceApp }
    for tag in memory.tags where tag.hasPrefix(appTagPrefix) {
      let name = String(tag.dropFirst(appTagPrefix.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, !name.lowercased().hasPrefix("unknown") else { continue }
      return name
    }
    return nil
  }
}
