import Foundation

/// Fetches API keys from the backend at runtime instead of bundling them in the app.
///
/// NOTE: Deepgram, Gemini, Anthropic keys are NO LONGER fetched from the backend —
/// they are proxied server-side (issues #5861, #6594).
/// Firebase and Calendar keys are still served via /v1/config/api-keys.

@MainActor
final class APIKeyService: ObservableObject {
  static let shared = APIKeyService()

  // Backend-provided keys (in-memory only, never persisted to disk)
  @Published private(set) var geminiApiKey: String?
  @Published private(set) var firebaseApiKey: String?
  @Published private(set) var googleCalendarApiKey: String?
  @Published private(set) var isLoaded: Bool = false
  @Published private(set) var loadError: String?

  /// The in-flight fetch task, so callers can await it instead of polling.
  private var fetchTask: Task<Void, Never>?

  /// Start fetching keys in the background. Callers can await via waitForKeys().
  func startFetchingKeys() {
    guard !isLoaded else { return }
    guard fetchTask == nil else { return }
    fetchTask = Task { await self.fetchKeys() }
  }

  /// Wait for keys to be loaded. Returns immediately if already loaded.
  /// If no fetch is in-flight, starts one (handles app-restart-while-signed-in case).
  /// A previously failed fetch clears fetchTask, so Calendar/Chat callers can retry without restarting.
  func waitForKeys() async {
    if isLoaded { return }
    if fetchTask == nil {
      log("APIKeyService: waitForKeys called but no fetch in-flight, starting one")
      fetchTask = Task { await fetchKeys() }
    }
    await fetchTask?.value
    if isLoaded { return }
    if fetchTask == nil {
      log("APIKeyService: key fetch completed without loaded keys, retrying once")
      fetchTask = Task { await fetchKeys() }
      await fetchTask?.value
    }
  }

  var effectiveGeminiKey: String? {
    geminiApiKey
  }

  var effectiveFirebaseApiKey: String? {
    firebaseApiKey
  }

  var effectiveGoogleCalendarApiKey: String? {
    googleCalendarApiKey
  }

  /// Fetch keys from the backend. Call after Firebase auth is ready.
  func fetchKeys() async {
    loadError = nil

    // Retry up to 3 times with backoff
    for attempt in 1...3 {
      do {
        let keys = try await APIClient.shared.fetchApiKeys()
        self.geminiApiKey = keys.geminiApiKey
        self.firebaseApiKey = keys.firebaseApiKey
        self.googleCalendarApiKey = keys.googleCalendarApiKey
        self.isLoaded = true

        // Set env vars so existing getenv() consumers keep working during transition
        applyToEnvironment()

        // Clear the completed task on the success path too (not just on the
        // all-attempts-failed path below). Otherwise a stale finished task
        // lingers; after sign-out (clear() sets isLoaded=false) the fetchTask
        // == nil guards in startFetchingKeys()/waitForKeys() never fire, so a
        // re-login can never refetch keys until the app is relaunched.
        fetchTask = nil

        log(
          "APIKeyService: Fetched keys from backend (gemini=\(keys.geminiApiKey != nil), firebase=\(keys.firebaseApiKey != nil), calendar=\(keys.googleCalendarApiKey != nil))"
        )
        return
      } catch {
        let delay = pow(2.0, Double(attempt - 1))
        log("APIKeyService: Fetch attempt \(attempt)/3 failed: \(error.localizedDescription), retrying in \(delay)s")
        if attempt < 3 {
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }
    }

    loadError = "Failed to fetch API keys from backend"
    log("APIKeyService: All fetch attempts failed — features requiring API keys will be unavailable")
    fetchTask = nil

    // Preserve any managed values already fetched before a transient failure.
    applyToEnvironment()
  }

  /// Clear all keys (e.g. on sign-out)
  func clear() {
    geminiApiKey = nil
    firebaseApiKey = nil
    googleCalendarApiKey = nil
    isLoaded = false
    loadError = nil
    // Drop any completed/in-flight fetch task so the next sign-in can start a
    // fresh fetch — the fetchTask == nil guards would otherwise block it.
    fetchTask?.cancel()
    fetchTask = nil

    unsetenv("GEMINI_API_KEY")
    // NOTE: Do NOT unset FIREBASE_API_KEY — it's needed for the next sign-in
    // (auth bootstrap requires Firebase key before backend is reachable)
    unsetenv("GOOGLE_CALENDAR_API_KEY")
  }

  /// Push effective keys into the process environment for backward compatibility.
  private func applyToEnvironment() {
    if let key = effectiveGeminiKey {
      setenv("GEMINI_API_KEY", key, 1)
    }
    if let key = effectiveFirebaseApiKey {
      setenv("FIREBASE_API_KEY", key, 1)
    }
    if let key = effectiveGoogleCalendarApiKey {
      setenv("GOOGLE_CALENDAR_API_KEY", key, 1)
    }
  }

  // MARK: - Thread-safe key access (for non-MainActor contexts)
  // These read from UserDefaults (thread-safe) and getenv() (set by applyToEnvironment).
  // Use these from actors, nonisolated inits, and background threads.

  nonisolated static var currentGeminiKey: String? {
    getenv("GEMINI_API_KEY").flatMap { String(validatingCString: $0) }
  }

  /// True when the app has enough configuration to start transcription and screen analysis.
  /// In managed mode, a canonical backend URL removes any need for client-side provider keys.
  nonisolated static var keysAvailable: Bool {
    getenv("GEMINI_API_KEY") != nil || getenv("OMI_PYTHON_API_URL") != nil
  }

}
