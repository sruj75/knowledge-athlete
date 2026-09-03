import Foundation

struct FairUseConversationEvidence: Codable, Equatable, Sendable {
  let conversationId: String
  let title: String
  let overview: String
  let category: String
  let durationMinutes: Double
  let source: String
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case conversationId = "conversation_id"
    case title, overview, category, source
    case durationMinutes = "duration_minutes"
    case createdAt = "created_at"
  }
}

struct FairUseReviewRequest: Equatable, Sendable {
  let reviewId: String
  let trigger: String
  let windowSpeechMs: [String: Int]
  let thresholdsMs: [String: Int]
  let classifierContract: String
  let requestedAt: Date
  let expiresAt: Date
}

struct FairUseManagedCloudExhaustion: Equatable, Sendable {
  let resetsAt: String
  let caseRef: String
}

struct FairUseManagedCloudPresentation: Equatable, Sendable {
  let title: String
  let message: String

  static func blocked(resetsAt: String, caseRef: String) -> Self {
    let refSuffix = caseRef.isEmpty ? "" : " Reference: \(caseRef)"
    return Self(
      title: "Managed Transcription Paused",
      message:
        "Today's 30-minute managed cloud transcription allowance has been used. "
        + "On-device transcription is unavailable on this Mac, so transcription is paused until \(resetsAt). "
        + "Save your case reference for the support channel when it is published."
        + refSuffix)
  }
}

enum FairUseManagedCloudHandoffOutcome: String, Equatable, Sendable {
  case ignored
  case continuedLocally = "continued_locally"
  case stoppedUnavailable = "stopped_unavailable"
}

enum FairUseAutomationProbe {
  static func rejectedExpiredAdmission(
    coordinator: FairUseReviewCoordinator = .shared
  ) async -> [String: String] {
    let expired = FairUseReviewRequest(
      reviewId: UUID().uuidString.lowercased(),
      trigger: "automation_probe",
      windowSpeechMs: [:],
      thresholdsMs: [:],
      classifierContract: "gemini/gemini-3.7-flash:prompt-v2",
      requestedAt: Date.distantPast,
      expiresAt: Date.distantPast.addingTimeInterval(1))
    await coordinator.handle(expired)
    return [
      "status": "expired_rejected",
      "backend_submission_attempted": "false",
      "content_fields_exposed": "false",
    ]
  }

}
