import Foundation

/// Persists the retained conversational-onboarding completion gates across a
/// permission-driven app restart.
enum OnboardingChatPersistence {
  private static let toolCompletedKey = "onboardingToolCompleted"
  private static let goalCompletedKey = "onboardingGoalCompleted"

  static func markToolCompleted() {
    UserDefaults.standard.set(true, forKey: toolCompletedKey)
  }

  static func markGoalCompleted() {
    UserDefaults.standard.set(true, forKey: goalCompletedKey)
  }

  static var isGoalCompleted: Bool {
    UserDefaults.standard.bool(forKey: goalCompletedKey)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: toolCompletedKey)
    UserDefaults.standard.removeObject(forKey: goalCompletedKey)
  }
}
