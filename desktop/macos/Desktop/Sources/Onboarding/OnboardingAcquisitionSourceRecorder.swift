import Foundation

/// Owns the complete acquisition-answer side effect: local persistence plus
/// analytics. There is deliberately no backend or network collaborator.
@MainActor
struct OnboardingAcquisitionSourceRecorder {
  private let defaults: UserDefaults
  private let track: (String) -> Void

  init(
    defaults: UserDefaults = .standard,
    track: @escaping (String) -> Void = {
      AnalyticsManager.shared.onboardingHowDidYouHear(source: $0)
    }
  ) {
    self.defaults = defaults
    self.track = track
  }

  func record(_ source: String) {
    defaults.set(source, forKey: DefaultsKey.onboardingHowDidYouHearSource)
    track(source)
  }
}
