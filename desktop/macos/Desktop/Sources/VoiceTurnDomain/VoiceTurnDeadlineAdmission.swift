enum VoiceTurnDeadlineAdmission {
  /// Deadline cancellation is best effort because a scheduled callback may have
  /// already crossed its scheduler boundary. The reducer is the final admission
  /// fence: a callback is valid only for the state that originally scheduled it.
  static func matchesCurrentState(_ deadline: VoiceTurnDeadline, turn: VoiceTurn) -> Bool {
    switch deadline {
    case .lockDecision:
      return turn.phase == .pendingLockDecision
    case .captureStart:
      return turn.phase.isRecording
    case .hubWarm:
      return turn.route == .hubWarmWait
    case .transcription:
      return turn.phase == .finalizing
    case .providerResponse:
      return turn.phase == .awaitingResponse
    case .pendingTools, .screenEvidenceProtocol:
      return turn.phase == .awaitingTools
    case .bargeInReplacement:
      if case .replacing = turn.providerConnection,
        turn.phase.isRecording || turn.phase == .finalizing
      {
        return true
      }
      return turn.phase == .awaitingResponse && turn.hubCommitPending
    case .deferredCommit:
      return turn.phase == .awaitingResponse && turn.hubCommitPending
    case .playbackDrain:
      if case .playing = turn.phase { return true }
      return false
    case .providerReconnect:
      if case .reconnecting = turn.providerConnection { return true }
      return false
    case .journalFinalization:
      return turn.phase == .awaitingJournal
    case .transcriptionFinalization:
      return turn.transcriptionFinalizationMode != nil
    case .hintVisibility:
      return true
    }
  }
}
