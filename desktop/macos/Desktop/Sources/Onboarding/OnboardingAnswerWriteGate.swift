import Foundation

/// Preserves a user's answer order when they revisit an onboarding question.
///
/// The UI advances optimistically while the name is projected to Firebase.
/// A revision must wait for its predecessor to finish before it begins,
/// otherwise an older request may finish last and overwrite the newer answer.
@MainActor
final class OnboardingAnswerWriteGate {
  private var tail: Task<Void, Never>?

  func enqueue(operation: @escaping @MainActor () async -> Void) {
    let predecessor = tail
    let task = Task { @MainActor in
      _ = await predecessor?.result
      await operation()
    }
    tail = task
  }

  func waitForIdle() async {
    _ = await tail?.result
  }
}
