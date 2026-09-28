import Foundation

extension FloatingControlBarManager {
  nonisolated private static let screenshotCues = [
    // explicit screen references
    "screen", "on my display", "what's on", "whats on", "on display",
    "look at", "looking at", "do you see", "can you see", "what do you see",
    "what am i looking at", "screenshot", "visible", "in front of me",
    "this page", "this window", "this app", "this tab", "this site",
    // visual verb + deictic (this/that/it)
    "read this", "read that", "read it", "summarize this", "summarize that",
    "explain this", "explain that", "what is this", "what's this", "whats this",
    "what does this", "what is that", "what's that", "translate this", "translate that",
    "fix this", "fix that", "what's this error", "this error", "this code",
    "this image", "this picture", "this photo", "this diagram", "this chart",
    "highlighted", "selected", "this selection",
  ]

  /// Heuristic: does this query plausibly need a screenshot of the user's screen?
  /// Defaults to NO — captures only when the text references the screen, something
  /// visual, or a visual verb paired with a deictic ("read this", "what's that").
  /// Keeps screenshots off the ~70% of queries that never look at the screen.
  nonisolated static func queryNeedsScreenshot(_ message: String) -> Bool {
    let m = message.lowercased()
    return screenshotCues.contains(where: { m.contains($0) })
  }
}
