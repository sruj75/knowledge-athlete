import Foundation

/// Prompt fragments for the "Execute" button on a proactive task notification.
///
/// The floating-bar agent normally lives under a concise presentation prompt.
/// An explicit **Execute** click supplies durable task intent while the kernel
/// still owns routing, clarification, and capability authorization.
enum ProactiveTaskExecute {

  /// Imperative restatement of the task. Tells the agent the user already
  /// chose to act — so finish the work end-to-end (which may legitimately
  /// include summarizing, drafting, or describing if that *is* the task).
  static func buildQuery(title: String, message: String) -> String {
    """
    Execute this task end-to-end now.

    Task: \(title)
    Details: \(message)
    """
  }

}
