import Foundation

/// One bounded language/retry policy shared by every completed-turn PTT batch
/// recovery route. Ambient meeting-transcription settings are intentionally not
/// an input.
enum PTTBatchTranscriptionPolicy {
  @MainActor
  static func transcribe(
    audioData: Data,
    voiceLanguages: [String],
    verdictCode: String?,
    contextKeywords: [String],
    isAuthorized: () -> Bool,
    recordLanguageFallback: (String, String, DesktopFallbackOutcome) -> Void = { from, to, outcome in
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "ptt_cascade",
        from: from,
        to: to,
        reason: "other",
        outcome: outcome,
        extra: [
          "fallback_detail": "empty_transcript",
          "user_visible": true,
        ])
    },
    transcribe: (Data, String, [String]) async throws -> TranscriptionService.BatchTranscriptionResult
  ) async throws -> TranscriptionService.BatchTranscriptionResult {
    guard isAuthorized() else { throw CancellationError() }
    let firstLanguage = selectedLanguage(
      voiceLanguages: voiceLanguages,
      verdictCode: verdictCode)
    var result = try await transcribe(audioData, firstLanguage, contextKeywords)
    guard isAuthorized() else { throw CancellationError() }

    if isEmpty(result.transcript), firstLanguage != "multi" {
      do {
        result = try await transcribe(audioData, "multi", contextKeywords)
      } catch {
        recordLanguageFallback(firstLanguage, "multi", .exhausted)
        throw error
      }
      guard isAuthorized() else { throw CancellationError() }
      recordLanguageFallback(firstLanguage, "multi", isEmpty(result.transcript) ? .exhausted : .recovered)
    }
    return result
  }

  static func selectedLanguage(voiceLanguages: [String], verdictCode: String?) -> String {
    let normalized = AssistantSettings.dedupedNormalizedLanguageCodes(voiceLanguages)
    if let verdictCode {
      let verdictBase = AssistantSettings.baseLanguageCode(verdictCode)
      if let matching = normalized.first(where: {
        AssistantSettings.baseLanguageCode($0) == verdictBase
      }) {
        return matching
      }
    }
    if normalized.count == 1, let only = normalized.first { return only }
    return "multi"
  }

  private static func isEmpty(_ transcript: String?) -> Bool {
    transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
  }
}
