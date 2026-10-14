import Foundation

struct AgentArtifactProjection: Codable, Equatable, Identifiable {
  var id: String { artifactId }

  let artifactId: String
  let sessionId: String
  let runId: String?
  let attemptId: String?
  let kind: String
  let role: String
  let uri: String
  let displayName: String?
  let mimeType: String?
  let contentHash: String?
  let sizeBytes: Int?
  let lifecycleState: String
  let lifecycleUpdatedAtMs: Int?
  let metadataRows: [String]
  let createdAtMs: Int?

  var title: String {
    if let displayName, !displayName.isEmpty {
      return displayName
    }
    return uri
  }

  /// True for artifacts worth surfacing to the user as a result card (a produced
  /// file/output), excluding inputs, intermediate context, and dismissed items.
  var isUserFacingResult: Bool {
    if lifecycleState == "dismissed" { return false }
    switch role {
    case "input", "context", "reference":
      return false
    default:
      return true
    }
  }

  static func parseList(fromToolResult result: String) throws -> [AgentArtifactProjection] {
    guard let data = result.data(using: .utf8),
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw AgentArtifactProjectionError.invalidResponse
    }
    if let ok = root["ok"] as? Bool, !ok {
      let error = root["error"] as? [String: Any]
      let message = error?["message"] as? String ?? "Artifact inspection failed"
      throw AgentArtifactProjectionError.toolFailed(message)
    }
    guard let artifacts = root["artifacts"] as? [[String: Any]] else {
      throw AgentArtifactProjectionError.invalidResponse
    }
    return parseList(fromJSONArray: artifacts)
  }

  static func parseList(fromJSONArray artifacts: [[String: Any]]) -> [AgentArtifactProjection] {
    artifacts.compactMap(parseArtifact(_:))
  }

  private static func parseArtifact(_ dict: [String: Any]) -> AgentArtifactProjection? {
    guard let artifactId = dict["artifactId"] as? String,
      let sessionId = dict["sessionId"] as? String,
      let kind = dict["kind"] as? String,
      let role = dict["role"] as? String,
      let uri = dict["uri"] as? String
    else {
      return nil
    }
    return AgentArtifactProjection(
      artifactId: artifactId,
      sessionId: sessionId,
      runId: dict["runId"] as? String,
      attemptId: dict["attemptId"] as? String,
      kind: kind,
      role: role,
      uri: uri,
      displayName: dict["displayName"] as? String,
      mimeType: dict["mimeType"] as? String,
      contentHash: dict["contentHash"] as? String,
      sizeBytes: intValue(dict["sizeBytes"]),
      lifecycleState: dict["lifecycleState"] as? String ?? "retained",
      lifecycleUpdatedAtMs: intValue(dict["lifecycleUpdatedAtMs"]),
      metadataRows: metadataRows(from: dict["metadata"]),
      createdAtMs: intValue(dict["createdAtMs"])
    )
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private static func metadataRows(from value: Any?) -> [String] {
    guard let metadata = value as? [String: Any], !metadata.isEmpty else {
      return []
    }
    return metadata.keys.sorted().compactMap { key in
      guard let rendered = renderMetadataValue(metadata[key]) else {
        return nil
      }
      return "\(key): \(rendered)"
    }
  }

  private static func renderMetadataValue(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else {
      return nil
    }
    if let string = value as? String {
      return string
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    if JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      return text
    }
    return String(describing: value)
  }
}

enum AgentArtifactProjectionError: LocalizedError, Equatable {
  case invalidResponse
  case toolFailed(String)
  var errorDescription: String? {
    switch self {
    case .invalidResponse: return "Invalid historical artifact data."
    case .toolFailed(let text): return text
    }
  }
}
