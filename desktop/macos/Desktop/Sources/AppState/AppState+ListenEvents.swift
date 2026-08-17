@preconcurrency import AVFoundation
import Combine
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
extension AppState {
  func handleBackendSegments(_ segments: [TranscriptionService.BackendSegment]) async {
    for segment in segments {
      guard !segment.text.isEmpty else { continue }

      // Extract speaker_id from backend (e.g. "SPEAKER_00" → 0)
      let speakerId = segment.speaker_id ?? 0

      // Convert backend segment to local SpeakerSegment
      let translations = (segment.translations ?? []).map {
        SegmentTranslation(lang: $0.lang, text: $0.text)
      }
      let newSeg = SpeakerSegment(
        segmentId: segment.id,
        speaker: speakerId,
        text: segment.text,
        start: segment.start,
        end: segment.end,
        isUser: segment.is_user,
        translations: translations
      )

      // Upsert: if we already have a segment with this ID, update it; otherwise append
      if let segId = segment.id,
        let existingIdx = speakerSegments.firstIndex(where: { $0.segmentId == segId })
      {
        // Adjust word count: subtract old words, add new words
        let oldWords = speakerSegments[existingIdx].text.split(separator: " ").count
        totalWordCount += newSeg.text.split(separator: " ").count - oldWords
        // Preserve existing translations if the backend didn't send new ones
        var updatedSeg = newSeg
        if translations.isEmpty && !speakerSegments[existingIdx].translations.isEmpty {
          updatedSeg.translations = speakerSegments[existingIdx].translations
        }
        speakerSegments[existingIdx] = updatedSeg
        log(
          "Transcript [UPDATE] Speaker \(speakerId) [\(String(format: "%.1f", segment.start))s-\(String(format: "%.1f", segment.end))s]: \(segment.text.prefix(80))"
        )
      } else {
        totalWordCount += newSeg.text.split(separator: " ").count
        speakerSegments.append(newSeg)
        totalSegmentCount += 1
        log(
          "Transcript [ADD] Speaker \(speakerId) [\(String(format: "%.1f", segment.start))s-\(String(format: "%.1f", segment.end))s]: \(segment.text.prefix(80))"
        )
      }
    }

    // Sliding window: trim old segments from memory (they're already persisted in SQLite)
    if speakerSegments.count > maxInMemorySegments {
      let excess = speakerSegments.count - maxInMemorySegments
      speakerSegments.removeFirst(excess)
    }

    log(
      "Transcript [SEGMENTS] Total: \(totalSegmentCount) segments (in-memory: \(speakerSegments.count))"
    )

    // Update published segments for UI (via isolated monitor)
    LiveTranscriptMonitor.shared.updateSegments(speakerSegments)

    // Persist segments to DB for crash safety (upsert by backend segment ID)
    if let sessionId = currentSessionId, let authorization = currentSessionAuthorization {
      await persistBackendSegmentsToStorage(
        segments, sessionId: sessionId, authorization: authorization)
    }
  }

  func persistBackendSegmentsToStorage(
    _ segments: [TranscriptionService.BackendSegment],
    sessionId: Int64,
    authorization: LocalMutationAuthorization
  ) async {
    let inputs = segments.compactMap { segment -> ConversationSegmentInput? in
      guard !segment.text.isEmpty else { return nil }
      return ConversationSegmentInput(
        segmentId: segment.id,
        speakerId: segment.speaker_id ?? 0,
        text: segment.text,
        startTime: segment.start,
        endTime: segment.end,
        isUser: segment.is_user,
        translations: (segment.translations ?? []).map {
          ConversationSegmentTranslation(language: $0.lang, text: $0.text)
        })
    }
    do {
      try await TranscriptionStorage.shared.upsertSegments(
        sessionId: sessionId, segments: inputs, authorization: authorization)
    } catch {
      logError("Transcription: Failed to persist segments to DB", error: error)
      await RewindDatabase.shared.reportQueryError(error)
    }
  }

  /// Handle message events from Python backend `/v4/listen`
  func handleListenEvent(_ event: TranscriptionService.ListenEvent) {
    switch event.type {
    case "service_status":
      let status = event.raw["status"] as? String ?? "unknown"
      if status == "stt_failed" {
        // The socket is closed immediately after this status. Keep a
        // user-visible truth state through reconnects; only a subsequent
        // ready status proves that live transcription recovered.
        transcriptionServiceError = "Transcription unavailable"
      } else if status == "ready" {
        transcriptionServiceError = nil
      }
      log("Transcription: Backend service status: \(status)")

    case "freemium_threshold_reached":
      let remaining = event.raw["remaining_seconds"] as? Int ?? 0
      log("Transcription: Freemium threshold reached, \(remaining)s remaining")
      triggerUsageLimitPopup(reason: "transcription")
      // Hard-stop client-side capture so the mic LED and screen-recording
      // indicator actually turn off. Without this, popup shows but the user
      // still sees the mic indicator green and assumes recording continues —
      // confusing and a battery/trust hit. Sticky until next app launch or
      // successful plan reactivation.
      isPaywalled = true
      if isTranscribing {
        log("Paywall: stopping transcription (freemium threshold)")
        stopTranscription()
      }
      Task { @MainActor in
        ProactiveAssistantsPlugin.shared.stopMonitoring()
      }

    case "translating":
      if let segmentsArray = event.raw["segments"] as? [[String: Any]] {
        do {
          let data = try JSONSerialization.data(withJSONObject: segmentsArray)
          let translatedSegments = try JSONDecoder().decode(
            [TranscriptionService.BackendSegment].self, from: data)
          log("Transcription: Translation event with \(translatedSegments.count) segments")
          for translated in translatedSegments {
            guard let segId = translated.id else { continue }
            let newTranslations = (translated.translations ?? []).map {
              SegmentTranslation(lang: $0.lang, text: $0.text)
            }
            guard !newTranslations.isEmpty else { continue }

            // Update in-memory if the segment is still loaded
            if let idx = speakerSegments.firstIndex(where: { $0.segmentId == segId }) {
              speakerSegments[idx].translations = newTranslations
            }

            // Always persist to SQLite — even if the segment was trimmed from
            // the in-memory window, the event payload has all fields needed
            if let sessionId = currentSessionId {
              let mapped = newTranslations.map {
                ConversationSegmentTranslation(language: $0.lang, text: $0.text)
              }
              Task {
                try? await TranscriptionStorage.shared.upsertSegments(
                  sessionId: sessionId,
                  segments: [
                    ConversationSegmentInput(
                      segmentId: segId,
                      speakerId: translated.speaker_id ?? 0,
                      text: translated.text,
                      startTime: translated.start,
                      endTime: translated.end,
                      isUser: translated.is_user,
                      translations: mapped)
                  ])
              }
            }
          }
          LiveTranscriptMonitor.shared.updateSegments(speakerSegments)
        } catch {
          logError("Transcription: Failed to parse translation event", error: error)
        }
      } else {
        log("Transcription: Translation event received (no segments)")
      }

    default:
      // `/v4/listen` remains a transient STT transport until S-16. Unknown
      // hosted lifecycle/identity events have no authority on the Mac.
      break
    }
  }

  /// Update the display transcript — no-op since word count is tracked incrementally
  /// and views use LiveTranscriptMonitor.segments directly
  func updateTranscriptDisplay() {
    // Previously rebuilt currentTranscript from all speakerSegments on every incoming segment,
    // causing O(N^2) string allocations. Word count is now tracked via totalWordCount.
  }

  /// Append text to transcript (fallback when no word-level data)
  func appendToTranscript(_ text: String) {
    if !currentTranscript.isEmpty {
      currentTranscript += "\n"
    }
    currentTranscript += text
  }

  /// Request microphone permission
}
