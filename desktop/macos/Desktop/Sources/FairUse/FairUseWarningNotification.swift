import CryptoKit
import Foundation

struct FairUseWarningPresentation: Equatable, Sendable {
  let title: String
  let message: String

  static func from(_ receipt: FairUseClassificationReceipt) -> Self? {
    let reference = receipt.caseRef.isEmpty ? "" : " Reference: \(receipt.caseRef)"
    switch receipt.action {
    case "warning":
      return Self(
        title: "Fair Use Notice",
        message:
          "Your speech usage is unusually high. This service is designed for personal conversations. "
          + "If this continues, you may receive a final fair-use warning. "
          + "Contact support@heyintentive.com if you believe this is an error. "
          + "Quote your case reference when contacting support.\(reference)")
    case "throttle":
      return Self(
        title: "Final Fair Use Warning",
        message:
          "Due to high non-conversational usage, this is your final fair-use warning. "
          + "Transcription quality and access have not changed. "
          + "This warning resets after seven days without another qualifying violation. "
          + "Contact support@heyintentive.com if you believe this is an error. "
          + "Quote your case reference when contacting support.\(reference)")
    case "restrict":
      return Self(
        title: "Transcription Limit Reached",
        message:
          "Your managed cloud transcription is temporarily limited for 30 days due to repeated fair-use violations. "
          + "Up to 30 minutes of managed cloud transcription remains available each UTC day. "
          + "On-device transcription continues only when it is available on this Mac. "
          + "Contact support@heyintentive.com to discuss your usage.\(reference)")
    default:
      return nil
    }
  }
}

@MainActor
final class FairUseWarningNotificationPresenter {
  static let shared = FairUseWarningNotificationPresenter()

  private let defaults: UserDefaults
  private let isAuthorizationCurrent: (RuntimeOwnerAuthorizationSnapshot) -> Bool
  private let deliver: (String, FairUseWarningPresentation, RuntimeOwnerAuthorizationSnapshot) async -> Bool

  init(
    defaults: UserDefaults = .standard,
    isAuthorizationCurrent: @escaping (RuntimeOwnerAuthorizationSnapshot) -> Bool = {
      RuntimeOwnerIdentity.isAuthorizationCurrent($0)
    },
    deliver:
      @escaping (
        String, FairUseWarningPresentation, RuntimeOwnerAuthorizationSnapshot
      ) async -> Bool = {
        ownerID, presentation, authorization in
        await withCheckedContinuation { continuation in
          NotificationService.shared.sendNotification(
            ownerID: ownerID,
            title: presentation.title,
            message: presentation.message,
            assistantId: "fair_use",
            deliverSystemBanner: true,
            respectFrequency: false,
            authorizationSnapshot: authorization,
            completion: { delivered in continuation.resume(returning: delivered) })
        }
      }
  ) {
    self.defaults = defaults
    self.isAuthorizationCurrent = isAuthorizationCurrent
    self.deliver = deliver
  }

  @discardableResult
  func present(
    _ receipt: FairUseClassificationReceipt,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async -> Bool {
    guard authorization.ownerID.isEmpty == false,
      isAuthorizationCurrent(authorization),
      let presentation = FairUseWarningPresentation.from(receipt)
    else { return false }

    let key = deduplicationKey(ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    guard defaults.bool(forKey: key) == false else { return false }
    guard isAuthorizationCurrent(authorization) else { return false }

    let delivered = await deliver(authorization.ownerID, presentation, authorization)
    guard delivered, isAuthorizationCurrent(authorization) else { return false }
    defaults.set(true, forKey: key)
    return true
  }

  private func deduplicationKey(ownerID: String, reviewID: String) -> String {
    let identity = Data("\(ownerID):\(reviewID.lowercased())".utf8)
    let digest = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    return "fair_use_warning_presented.\(digest)"
  }
}
