import Foundation

enum TranscriptionFinalizationReason: String, Codable, CaseIterable, Sendable {
  case userStop = "user_stop"
  case finishAndContinue = "finish_and_continue"
  case meetingEnded = "meeting_ended"
  case maxDurationRotation = "max_duration_rotation"
  case crashRecovery = "crash_recovery"
  case retry = "retry"
}

enum TranscriptionStorageError: LocalizedError {
  case databaseNotInitialized
  case sessionNotFound
  case invalidState(String)

  var errorDescription: String? {
    switch self {
    case .databaseNotInitialized:
      return "Conversation storage database is not initialized"
    case .sessionNotFound:
      return "Conversation not found"
    case .invalidState(let message):
      return "Invalid conversation state: \(message)"
    }
  }
}
