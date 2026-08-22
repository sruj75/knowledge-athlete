struct ModelQoS {
  struct Claude {
    /// Main chat session model (user-facing conversations)
    static let chat = "claude-sonnet-4-6"

    /// Floating bar responses
    static let floatingBar = "claude-sonnet-4-6"
  }

  struct Gemini {
    /// Proactive assistants (screenshot analysis, context detection)
    static let proactive = "gemini-2.5-flash"

    /// Task extraction
    static let taskExtraction = "gemini-2.5-flash"

    /// Insight generation
    static let insight = "gemini-2.5-flash"

    /// Live notch suggestions use Flash-Lite because ordinary context changes
    /// trigger them much more often than the slower proactive assistants.
    static let suggestions = "gemini-2.5-flash-lite"

    /// Embeddings
    static let embedding = "gemini-embedding-001"
  }
}
