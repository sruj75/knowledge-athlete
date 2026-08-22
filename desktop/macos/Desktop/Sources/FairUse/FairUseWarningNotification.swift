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

struct FairUseWarningDeliveryStatus: Equatable, Sendable {
  let inAppPresented: Bool
  let systemBannerDelivered: Bool
  let pendingReplay: Bool
}

@MainActor
final class FairUseWarningNotificationPresenter {
  static let shared = FairUseWarningNotificationPresenter()

  private static let maximumPendingReceipts = 16

  private let defaults: UserDefaults
  private var inFlightReceiptAuthorizations: [String: RuntimeOwnerAuthorizationSnapshot] = [:]
  private var queuedInAppAuthorizations: [String: RuntimeOwnerAuthorizationSnapshot] = [:]
  private let isAuthorizationCurrent: @Sendable (RuntimeOwnerAuthorizationSnapshot) -> Bool
  private let deliver:
    @MainActor (
      String, FairUseWarningPresentation, RuntimeOwnerAuthorizationSnapshot,
      Bool, Bool,
      @escaping @MainActor @Sendable () -> Void,
      @escaping @MainActor @Sendable () -> Void,
      @escaping @MainActor @Sendable () -> Void,
      @escaping @MainActor @Sendable () -> Void
    ) async -> Bool

  init(
    defaults: UserDefaults = .standard,
    isAuthorizationCurrent: @escaping @Sendable (RuntimeOwnerAuthorizationSnapshot) -> Bool = {
      RuntimeOwnerIdentity.isAuthorizationCurrent($0)
    },
    deliver:
      @escaping @MainActor (
        String, FairUseWarningPresentation, RuntimeOwnerAuthorizationSnapshot,
        Bool, Bool,
        @escaping @MainActor @Sendable () -> Void,
        @escaping @MainActor @Sendable () -> Void,
        @escaping @MainActor @Sendable () -> Void,
        @escaping @MainActor @Sendable () -> Void
      ) async -> Bool = {
        ownerID, presentation, authorization, deliverInApp, deliverSystemBanner, queueInApp,
        cancelQueuedInApp, commitInApp, commitSystemBanner in
        await withCheckedContinuation { continuation in
          NotificationService.shared.sendNotification(
            ownerID: ownerID,
            title: presentation.title,
            message: presentation.message,
            assistantId: "fair_use",
            deliverInAppPresentation: deliverInApp,
            deliverSystemBanner: deliverSystemBanner,
            respectFrequency: false,
            authorizationSnapshot: authorization,
            onInAppQueued: queueInApp,
            onInAppQueueCancelled: cancelQueuedInApp,
            onInAppPresented: commitInApp,
            onSystemBannerDeliveredWithinCommit: commitSystemBanner,
            completion: { delivered in continuation.resume(returning: delivered) })
        }
      }
  ) {
    self.defaults = defaults
    self.isAuthorizationCurrent = isAuthorizationCurrent
    self.deliver = deliver
  }

  /// Accept durable ownership of a classified warning before attempting either
  /// presentation surface. The coordinator may then retire the transient socket
  /// event: denied/snoozed delivery remains replayable by this owner on reconnect
  /// or process restart without re-running classification.
  func accept(
    _ receipt: FairUseClassificationReceipt,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async -> Bool {
    guard authorization.ownerID.isEmpty == false,
      isAuthorizationCurrent(authorization),
      FairUseWarningPresentation.from(receipt) != nil
    else { return false }

    let inAppKey = inAppDeduplicationKey(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    let systemKey = systemDeduplicationKey(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    if defaults.bool(forKey: inAppKey), defaults.bool(forKey: systemKey) {
      removePending(receipt, ownerID: authorization.ownerID)
      return true
    }
    stagePending(receipt, ownerID: authorization.ownerID)
    _ = await attemptPresentation(receipt, authorization: authorization)
    return true
  }

  @discardableResult
  func present(
    _ receipt: FairUseClassificationReceipt,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async -> Bool {
    guard authorization.ownerID.isEmpty == false,
      isAuthorizationCurrent(authorization),
      FairUseWarningPresentation.from(receipt) != nil
    else { return false }

    let inAppKey = inAppDeduplicationKey(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    let systemKey = systemDeduplicationKey(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    guard !defaults.bool(forKey: inAppKey) || !defaults.bool(forKey: systemKey) else {
      return false
    }
    stagePending(receipt, ownerID: authorization.ownerID)
    return await attemptPresentation(receipt, authorization: authorization)
  }

  @discardableResult
  func replayPending(authorization: RuntimeOwnerAuthorizationSnapshot) async -> Int {
    guard isAuthorizationCurrent(authorization) else { return 0 }
    var delivered = 0
    for receipt in pendingReceipts(ownerID: authorization.ownerID) {
      guard isAuthorizationCurrent(authorization) else { break }
      if await attemptPresentation(receipt, authorization: authorization) {
        delivered += 1
      }
    }
    return delivered
  }

  func deliveryStatus(
    for receipt: FairUseClassificationReceipt,
    ownerID: String
  ) -> FairUseWarningDeliveryStatus {
    let pending = pendingReceipts(ownerID: ownerID).contains {
      $0.reviewId.caseInsensitiveCompare(receipt.reviewId) == .orderedSame
    }
    return FairUseWarningDeliveryStatus(
      inAppPresented: defaults.bool(
        forKey: inAppDeduplicationKey(ownerID: ownerID, reviewID: receipt.reviewId)),
      systemBannerDelivered: defaults.bool(
        forKey: systemDeduplicationKey(ownerID: ownerID, reviewID: receipt.reviewId)),
      pendingReplay: pending)
  }

  private func attemptPresentation(
    _ receipt: FairUseClassificationReceipt,
    authorization: RuntimeOwnerAuthorizationSnapshot
  ) async -> Bool {
    guard isAuthorizationCurrent(authorization),
      let presentation = FairUseWarningPresentation.from(receipt)
    else { return false }

    let inAppKey = inAppDeduplicationKey(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    let systemKey = systemDeduplicationKey(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    let receiptKey = deduplicationDigest(
      ownerID: authorization.ownerID, reviewID: receipt.reviewId)
    guard inFlightReceiptAuthorizations[receiptKey] != authorization else { return false }
    inFlightReceiptAuthorizations[receiptKey] = authorization
    defer {
      if inFlightReceiptAuthorizations[receiptKey] == authorization {
        inFlightReceiptAuthorizations.removeValue(forKey: receiptKey)
      }
    }
    let inAppPresented = defaults.bool(forKey: inAppKey)
    let inAppQueued = queuedInAppAuthorizations[receiptKey] == authorization
    let systemBannerDelivered = defaults.bool(forKey: systemKey)
    guard !inAppPresented || !systemBannerDelivered else {
      removePending(receipt, ownerID: authorization.ownerID)
      return false
    }
    if inAppQueued && systemBannerDelivered {
      return false
    }

    _ = await deliver(
      authorization.ownerID,
      presentation,
      authorization,
      !inAppPresented && !inAppQueued,
      !systemBannerDelivered,
      { [self] in queuedInAppAuthorizations[receiptKey] = authorization },
      { [self] in
        if queuedInAppAuthorizations[receiptKey] == authorization {
          queuedInAppAuthorizations.removeValue(forKey: receiptKey)
        }
      },
      { [self, defaults] in
        queuedInAppAuthorizations.removeValue(forKey: receiptKey)
        defaults.set(true, forKey: inAppKey)
        if defaults.bool(forKey: systemKey) {
          removePending(receipt, ownerID: authorization.ownerID)
        }
      },
      { [self, defaults] in
        defaults.set(true, forKey: systemKey)
        if defaults.bool(forKey: inAppKey) {
          removePending(receipt, ownerID: authorization.ownerID)
        }
      })
    let complete = defaults.bool(forKey: inAppKey) && defaults.bool(forKey: systemKey)
    if complete {
      removePending(receipt, ownerID: authorization.ownerID)
    }
    return complete
  }

  private func inAppDeduplicationKey(ownerID: String, reviewID: String) -> String {
    "fair_use_warning_in_app_presented.\(deduplicationDigest(ownerID: ownerID, reviewID: reviewID))"
  }

  private func systemDeduplicationKey(ownerID: String, reviewID: String) -> String {
    "fair_use_warning_system_presented.\(deduplicationDigest(ownerID: ownerID, reviewID: reviewID))"
  }

  private func deduplicationDigest(ownerID: String, reviewID: String) -> String {
    let identity = Data("\(ownerID):\(reviewID.lowercased())".utf8)
    return SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
  }

  private func pendingKey(ownerID: String) -> String {
    let digest = SHA256.hash(data: Data(ownerID.utf8)).map { String(format: "%02x", $0) }.joined()
    return "fair_use_warning_pending.\(digest)"
  }

  private func pendingReceipts(ownerID: String) -> [FairUseClassificationReceipt] {
    guard let data = defaults.data(forKey: pendingKey(ownerID: ownerID)) else { return [] }
    do {
      return try JSONDecoder().decode([FairUseClassificationReceipt].self, from: data)
    } catch {
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "fair_use_review",
        from: "durable_pending_receipts",
        to: "empty_projection",
        reason: "state_divergence",
        outcome: .exhausted,
        extra: ["failure_class": "pending_receipt_decode_failed"])
      return []
    }
  }

  private func stagePending(_ receipt: FairUseClassificationReceipt, ownerID: String) {
    var receipts = pendingReceipts(ownerID: ownerID)
    receipts.removeAll { $0.reviewId.caseInsensitiveCompare(receipt.reviewId) == .orderedSame }
    receipts.append(receipt)
    if receipts.count > Self.maximumPendingReceipts {
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "fair_use_review",
        from: "pending_replay_queue",
        to: "bounded_oldest_eviction",
        reason: "policy",
        outcome: .degraded,
        extra: ["failure_class": "pending_receipt_capacity"])
      receipts.removeFirst(receipts.count - Self.maximumPendingReceipts)
    }
    persistPending(receipts, ownerID: ownerID)
  }

  private func removePending(_ receipt: FairUseClassificationReceipt, ownerID: String) {
    var receipts = pendingReceipts(ownerID: ownerID)
    receipts.removeAll { $0.reviewId.caseInsensitiveCompare(receipt.reviewId) == .orderedSame }
    persistPending(receipts, ownerID: ownerID)
  }

  private func persistPending(_ receipts: [FairUseClassificationReceipt], ownerID: String) {
    let key = pendingKey(ownerID: ownerID)
    guard !receipts.isEmpty else {
      defaults.removeObject(forKey: key)
      return
    }
    do {
      let data = try JSONEncoder().encode(receipts)
      defaults.set(data, forKey: key)
    } catch {
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "fair_use_review",
        from: "pending_receipt",
        to: "prior_durable_projection",
        reason: "state_divergence",
        outcome: .exhausted,
        extra: ["failure_class": "pending_receipt_encode_failed"])
    }
  }
}
