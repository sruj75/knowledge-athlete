struct ModelQoS {
  struct Gemini {
    /// Normal Chat and floating-bar responses
    static let chat = "gemini-3.7-flash"

    /// Proactive assistants (screenshot analysis, context detection)
    static let proactive = "gemini-3.7-flash"

    /// Task extraction
    static let taskExtraction = "gemini-3.7-flash"

    /// Insight generation
    static let insight = "gemini-3.7-flash"

    /// Use the account-available managed model; retained 2.5 routes return 404
    /// for the owned provider account (#102). Existing frequency gates remain.
    static let suggestions = "gemini-3.7-flash"

    /// Embeddings
    static let embedding = "gemini-embedding-001"
  }
}
