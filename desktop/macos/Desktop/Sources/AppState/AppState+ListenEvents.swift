@preconcurrency import AVFoundation
import Combine
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
extension AppState {
  func handleBackendSegments(
    _ segments: [TranscriptionService.BackendSegment], expectedSessionId: Int64? = nil
  ) async {
    if let expectedSessionId, currentSessionId != expectedSessionId { return }
    for segment in segments {
      guard !segment.text.isEmpty else { continue }

      let speakerId = segment.speakerId

      // Convert backend segment to local SpeakerSegment
      let translations = segment.translations.map {
        SegmentTranslation(lang: $0.lang, text: $0.text)
      }
      let newSeg = SpeakerSegment(
        segmentId: segment.segmentId,
        speaker: speakerId,
        text: segment.text,
        start: segment.start,
        end: segment.end,
        isUser: segment.isUser,
        translations: translations
      )

      // Upsert: if we already have a segment with this ID, update it; otherwise append
      if let existingIdx = speakerSegments.firstIndex(where: { $0.segmentId == segment.segmentId }) {
        // Adjust word count: subtract old words, add new words
        let oldWords = speakerSegments[existingIdx].text.split(separator: " ").count
        totalWordCount += newSeg.text.split(separator: " ").count - oldWords
        // Preserve existing translations if the backend didn't send new ones
        var updatedSeg = newSeg
        if translations.isEmpty && !speakerSegments[existingIdx].translations.isEmpty {
          updatedSeg.translations = speakerSegments[existingIdx].translations
        }
        speakerSegments[existingIdx] = updatedSeg
        log("Transcript [UPDATE] Speaker \(speakerId)")
      } else {
        totalWordCount += newSeg.text.split(separator: " ").count
        speakerSegments.append(newSeg)
        totalSegmentCount += 1
        log("Transcript [ADD] Speaker \(speakerId)")
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
        segmentId: segment.segmentId,
        speakerId: segment.speakerId,
        text: segment.text,
        startTime: segment.start,
        endTime: segment.end,
        isUser: segment.isUser,
        translations: segment.translations.map {
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
  func handleListenEvent(
    _ event: TranscriptionService.ListenEvent, expectedSessionId: Int64? = nil
  ) async {
    if let expectedSessionId, currentSessionId != expectedSessionId { return }
    switch event {
    case .serviceStatus(let status):
      if status == .sttFailed {
        // The socket is closed immediately after this status. Keep a
        // user-visible truth state through reconnects; only a subsequent
        // ready status proves that live transcription recovered.
        transcriptionServiceError = "Transcription unavailable"
      } else if status == .ready {
        transcriptionServiceError = nil
      }
      log("Transcription: Backend service status: \(status.rawValue)")

    case .freemiumThresholdReached(let remaining, _):
      log("Transcription: Freemium threshold reached, \(remaining)s remaining")
      triggerUsageLimitPopup(reason: "transcription")
      // Hard-stop client-side capture so the mic LED and screen-recording
      // indicator actually turn off. Without this, popup shows but the user
      // still sees the mic indicator green and assumes recording continues —
      // confusing and a battery/trust hit. Sticky until next app launch or
      // verified paid projection.
      isPaywalled = true
      if isTranscribing {
        log("Paywall: stopping transcription (freemium threshold)")
        stopTranscription()
      }
      Task { @MainActor in
        ProactiveAssistantsPlugin.shared.stopMonitoring()
      }

    case .translation(let segmentId, let language, let text):
      let translation = SegmentTranslation(lang: language, text: text)
      if let index = speakerSegments.firstIndex(where: { $0.segmentId == segmentId }) {
        var translations = speakerSegments[index].translations
        translations.removeAll { $0.lang == language }
        translations.append(translation)
        speakerSegments[index].translations = translations
        LiveTranscriptMonitor.shared.updateSegments(speakerSegments)
      }
      guard let sessionId = currentSessionId,
        let authorization = currentSessionAuthorization
      else { return }
      do {
        try await TranscriptionStorage.shared.attachTranslation(
          sessionId: sessionId,
          segmentId: segmentId,
          translation: ConversationSegmentTranslation(language: language, text: text),
          authorization: authorization)
      } catch {
        logError("Transcription: Failed to persist local translation", error: error)
      }
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
