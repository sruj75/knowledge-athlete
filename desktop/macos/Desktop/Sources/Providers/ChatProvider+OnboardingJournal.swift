extension ChatProvider {
  func beginOnboardingJournal() {
    guard !isOnboarding else { return }
    preOnboardingMainMessages = messages
    isOnboarding = true
  }

  /// Delete only setup-owned conversation state. Onboarding is a local-only
  /// journal surface, so this can never enqueue a backend chat deletion or
  /// mutate the user's normal main-chat history.
  func clearOnboardingJournal() async -> Bool {
    let surface = AgentSurfaceReference.onboarding()
    AgentRuntimeStatusStore.shared.clear(surface: surface)
    return await kernelTurnProjection.clear(surface: surface, deleteBackend: false)
  }

  /// Clear every in-memory setup projection before replay or owner handoff.
  /// The setup journal is local-only, and none of its transcript, fallback, or
  /// personalized opener may survive into another authenticated owner.
  func resetOnboardingProjectionForReplay() {
    if isOnboarding, let fallbackMessages = preOnboardingMainMessages {
      messages = fallbackMessages
      resetMessagesPagination()
    }
    isOnboarding = false
    preOnboardingMainMessages = nil
    onboardingOpener = nil
    ChatDraftStore.shared.clear(.onboardingMain)
    ChatDraftStore.shared.clear(.onboardingFloating)
  }

  /// Leave the setup-only chat surface, purge its local transcript, and restore
  /// the authoritative main-chat projection before the product UI is revealed.
  func finishOnboardingJournal() async {
    let fallbackMessages = preOnboardingMainMessages ?? []
    _ = await clearOnboardingJournal()
    isOnboarding = false
    let reloaded = await kernelTurnProjection.reload(surface: mainChatSurfaceReference())
    if !reloaded {
      messages = fallbackMessages
      resetMessagesPagination()
    }
    preOnboardingMainMessages = nil
  }
}
