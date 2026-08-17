@preconcurrency import CoreLocation
import Foundation

@MainActor
protocol ConversationLocationProviding: AnyObject, Sendable {
  func requestOneShotLocation() async throws -> ConversationLocationSnapshot?
}

enum ConversationLocationSnapshotter {
  @MainActor
  static func capture(
    using provider: ConversationLocationProviding,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    timeoutSleeper: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
      try await Task.sleep(nanoseconds: nanoseconds)
    }
  ) async -> ConversationLocationSnapshot? {
    await withTaskGroup(of: ConversationLocationSnapshot?.self) { group in
      group.addTask {
        try? await provider.requestOneShotLocation()
      }
      group.addTask {
        try? await timeoutSleeper(timeoutNanoseconds)
        return nil
      }
      let result = await group.next() ?? nil
      group.cancelAll()
      return result
    }
  }
}

@MainActor
final class CoreLocationConversationLocationProvider: NSObject, ConversationLocationProviding,
  @preconcurrency CLLocationManagerDelegate
{
  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<ConversationLocationSnapshot?, Never>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func requestOneShotLocation() async throws -> ConversationLocationSnapshot? {
    guard continuation == nil else { return nil }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        guard !Task.isCancelled else {
          finish(nil)
          return
        }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
          manager.requestLocation()
        case .notDetermined:
          manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
          finish(nil)
        @unknown default:
          finish(nil)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finish(nil)
      }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard continuation != nil else { return }
    switch manager.authorizationStatus {
    case .authorized, .authorizedAlways: manager.requestLocation()
    case .denied, .restricted: finish(nil)
    case .notDetermined: break
    @unknown default: finish(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let coordinate = locations.last?.coordinate else {
      finish(nil)
      return
    }
    finish(ConversationLocationSnapshot(latitude: coordinate.latitude, longitude: coordinate.longitude, label: nil))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finish(nil)
  }

  private func finish(_ value: ConversationLocationSnapshot?) {
    let pending = continuation
    continuation = nil
    pending?.resume(returning: value)
  }
}
