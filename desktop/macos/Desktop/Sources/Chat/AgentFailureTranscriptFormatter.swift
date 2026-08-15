import Foundation

enum AgentFailureTranscriptFormatter {
  static let genericSpawnFailure = "Agent couldn't start — try again"

  static func errorText(for projection: AgentRunProjection) -> String? {
    switch projection.status {
    case .failed, .timedOut, .orphaned:
      let raw =
        projection.failure?.displayMessage
        ?? projection.errorMessage
        ?? projection.statusText
        ?? "Agent failed"
      return userFacingFailure(raw)
    case .idle, .queued, .starting, .running, .waitingInput, .waitingApproval, .cancelling, .succeeded, .cancelled:
      return nil
    }
  }

  static func transcriptText(for errorText: String) -> String? {
    let trimmed = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let sanitized = userFacingFailure(trimmed)
    if sanitized.lowercased().hasPrefix("failed:") {
      return sanitized
    }
    return "Failed: \(sanitized)"
  }

  /// Strip HTTP/URLSession guts while preserving managed-authentication guidance.
  static func userFacingFailure(_ errorText: String) -> String {
    let trimmed = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return genericSpawnFailure }

    if looksLikeSetupNeeded(trimmed) {
      return genericSpawnFailure
    }

    if looksLikeRawTransportGuts(trimmed) {
      return genericSpawnFailure
    }

    // Prefer short, non-technical copy already authored for the UI.
    if trimmed.count <= 120,
      !trimmed.contains("http"),
      !trimmed.contains("URLSession"),
      !trimmed.contains("NSURLError")
    {
      return trimmed
    }
    return genericSpawnFailure
  }

  static func userFacingFailure(for error: Error) -> String {
    if let runtime = error as? BridgeError, case .agentRuntimeFailure(let failure) = runtime {
      return userFacingFailure(failure.displayMessage)
    }
    let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return userFacingFailure(raw)
  }

  private static func looksLikeSetupNeeded(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains("needs setup") { return true }
    if lower.contains("adapter")
      && (lower.contains("missing") || lower.contains("unavailable") || lower.contains("not found")
        || lower.contains("not configured") || lower.contains("no such file"))
    {
      return true
    }
    return false
  }

  private static func looksLikeRawTransportGuts(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower.contains("urlsession")
      || lower.contains("nsurlerror")
      || lower.contains("http://")
      || lower.contains("https://")
      || lower.contains("(-1001)")
      || lower.contains("(-1009)")
      || lower.contains("status code")
      || lower.contains("task failed")
  }
}
