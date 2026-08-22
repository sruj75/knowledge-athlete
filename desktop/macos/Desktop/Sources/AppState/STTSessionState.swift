import Foundation

/// Pure policy + transition state for cloud ↔ on-device STT fallback.
/// All resolution rules live here so AppState only orchestrates I/O.
struct STTSessionState: Equatable {
  enum ResolvedMode: Equatable {
    case local
    case cloud

    var usesLocalSTT: Bool { self == .local }
  }

  enum FallbackDirection: Equatable {
    case localToCloud
    case cloudToLocal
  }

  /// Sticky for the app run after Parakeet model-load failure (never reset on new recordings).
  private(set) var appRunForceCloud = false
  /// Session sticky: prefer on-device after cloud reconnect exhaustion.
  private(set) var sessionForceLocal = false
  /// One-shot guard: cloud→local fallback already attempted this session.
  private(set) var cloudToLocalFallbackTried = false
  /// Mutex during stop→async-restart fallback choreography.
  private(set) var fallbackInProgress = false
  /// In-place fair-use handoffs are generation-bound; unlike restart fallbacks,
  /// they must be cancelled when their recording ends.
  private(set) var managedRestrictionHandoffInProgress = false
  /// Active transport mode while capture is running (`nil` when stopped).
  var activeMode: ResolvedMode?

  var useLocalSTT: Bool { activeMode?.usesLocalSTT ?? false }

  /// Reset session-scoped flags when starting a new recording (skipped mid-fallback).
  mutating func prepareForStart() {
    guard !fallbackInProgress else { return }
    cloudToLocalFallbackTried = false
    sessionForceLocal = false
  }

  /// Resolve which STT path to use for a new recording.
  func resolveMode(
    isAppleSilicon: Bool,
    debugForceCloud: Bool
  ) -> ResolvedMode {
    let forceCloud = !sessionForceLocal && (debugForceCloud || appRunForceCloud)
    if !isAppleSilicon || forceCloud {
      return .cloud
    }
    return .local
  }

  mutating func beginRecording(
    isAppleSilicon: Bool,
    debugForceCloud: Bool
  ) {
    activeMode = resolveMode(
      isAppleSilicon: isAppleSilicon,
      debugForceCloud: debugForceCloud
    )
  }

  mutating func endRecording() {
    activeMode = nil
    if managedRestrictionHandoffInProgress {
      // An in-place producer handoff belongs to one recording generation.
      // Restart-based fallbacks intentionally retain their flags across stop;
      // this path alone must not leak into the next recording.
      fallbackInProgress = false
      sessionForceLocal = false
      managedRestrictionHandoffInProgress = false
    }
  }

  func canBeginLocalToCloudFallback(isTranscribing: Bool) -> Bool {
    isTranscribing && useLocalSTT && !fallbackInProgress
  }

  mutating func beginLocalToCloudFallback() {
    fallbackInProgress = true
    appRunForceCloud = true
    // Clear a stale session-local preference so resolveMode honors the cloud
    // fallback instead of resolving back to .local.
    sessionForceLocal = false
  }

  func canBeginCloudToLocalFallback(
    isTranscribing: Bool,
    isAppleSilicon: Bool
  ) -> Bool {
    isTranscribing
      && !useLocalSTT
      && isAppleSilicon
      && !appRunForceCloud
      && !cloudToLocalFallbackTried
      && !fallbackInProgress
  }

  mutating func beginCloudToLocalFallback() {
    cloudToLocalFallbackTried = true
    fallbackInProgress = true
    sessionForceLocal = true
  }

  func canBeginManagedRestrictionHandoff(
    isTranscribing: Bool,
    isAppleSilicon: Bool
  ) -> Bool {
    canBeginCloudToLocalFallback(
      isTranscribing: isTranscribing,
      isAppleSilicon: isAppleSilicon)
  }

  /// Switches only the active producer. The caller deliberately keeps the current conversation,
  /// owner authorization, and live websocket rather than entering the stop/restart choreography.
  mutating func beginManagedRestrictionHandoff() {
    beginCloudToLocalFallback()
    managedRestrictionHandoffInProgress = true
    // Route newly armed capture into the local sinks while readiness is still
    // represented by ``fallbackInProgress``. Recovery is not complete until
    // both Parakeet services report usable.
    activeMode = .local
  }

  mutating func completeManagedRestrictionHandoff() {
    managedRestrictionHandoffInProgress = false
    completeFallback()
  }

  mutating func abortManagedRestrictionHandoff(localModelUnavailable: Bool) {
    managedRestrictionHandoffInProgress = false
    fallbackInProgress = false
    sessionForceLocal = false
    if localModelUnavailable { appRunForceCloud = true }
    if activeMode != nil { activeMode = .cloud }
  }

  /// Preserve local mode just long enough for stopTranscription() to finish the
  /// unaffected producer's buffered tail before the session is finalized.
  mutating func prepareManagedRestrictionFailureForLocalTeardown() {
    managedRestrictionHandoffInProgress = false
    fallbackInProgress = false
    sessionForceLocal = false
    appRunForceCloud = true
  }

  mutating func completeFallback() {
    fallbackInProgress = false
  }

  static func debugForceCloudSTT(
    environmentForceCloud: Bool,
    userDefaultsForceCloud: Bool
  ) -> Bool {
    environmentForceCloud || userDefaultsForceCloud
  }
}
