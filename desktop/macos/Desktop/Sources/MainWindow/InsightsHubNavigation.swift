import Combine
import Foundation

enum InsightsHubSegment: Int, CaseIterable, Sendable {
  case insights
  case focus
}

struct InsightsHubRequest: Equatable, Sendable {
  let segment: InsightsHubSegment
  let authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  let insightID: String?
}

@MainActor
final class InsightsHubNavigationStore: ObservableObject {
  static let shared = InsightsHubNavigationStore()

  @Published private(set) var pendingRequest: InsightsHubRequest?
  @Published private(set) var unavailableMessage: String?

  private let notificationCenter: NotificationCenter
  private nonisolated(unsafe) var ownerObserver: NSObjectProtocol?

  init(notificationCenter: NotificationCenter = .default) {
    self.notificationCenter = notificationCenter
    ownerObserver = notificationCenter.addObserver(
      forName: .runtimeOwnerDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if self.pendingRequest?.insightID != nil {
          self.unavailableMessage = "Insight unavailable"
        }
        self.pendingRequest = nil
      }
    }
  }

  deinit {
    if let ownerObserver { notificationCenter.removeObserver(ownerObserver) }
  }

  @discardableResult
  func request(segment: InsightsHubSegment, insightID: String? = nil) -> Bool {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      unavailableMessage = insightID == nil ? nil : "Insight unavailable"
      pendingRequest = nil
      return false
    }
    unavailableMessage = nil
    pendingRequest = InsightsHubRequest(
      segment: segment,
      authorizationSnapshot: snapshot,
      insightID: insightID
    )
    return true
  }

  func consume() -> InsightsHubRequest? {
    guard let request = pendingRequest else { return nil }
    pendingRequest = nil
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(request.authorizationSnapshot) else {
      unavailableMessage = request.insightID == nil ? nil : "Insight unavailable"
      return nil
    }
    return request
  }

  func reportInsightUnavailable() {
    unavailableMessage = "Insight unavailable"
  }

  func dismissUnavailableMessage() {
    unavailableMessage = nil
  }
}
