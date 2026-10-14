import Foundation

extension ConversationDeliveryOutcome {
  /// The observability schema uses suppressed for a generated answer that was
  /// never spoken. Storage retains its distinct not_spoken delivery value.
  var observedOutcome: AIVoiceTurnOutcome {
    switch self {
    case .completed: return .completed
    case .interrupted: return .interrupted
    case .failed: return .failed
    case .notSpoken: return .suppressed
    }
  }
}
