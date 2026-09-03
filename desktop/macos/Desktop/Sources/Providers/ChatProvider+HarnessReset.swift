import Foundation

extension ChatProvider {
  var automationMainChatIsIdle: Bool {
    !isLoading && !isLoadingSessions && !isSending
      && !messages.contains(where: { $0.isStreaming })
  }

  /// Harness-only chat reset that awaits backend deletion before returning and
  /// leaves any replacement session empty. Returns an error message when
  /// backend deletion fails so E2E flows don't proceed against stale state.
  func automationResetChatForHarness() async -> String? {
    guard AppBuild.isNonProduction else { return nil }
    return await resetChatForAuthorizedHarness()
  }

  /// Completes a harness reset after its non-production automation entrypoint
  /// has established eligibility. The main-chat transaction sets
  /// `journalAlreadyCleared` only after its authoritative owner-scoped control
  /// clear has succeeded for the active surface.
  func resetChatForAuthorizedHarness(
    journalAlreadyCleared: Bool = false,
    authorizedClearTransaction: AuthorizedHarnessClearTransaction? = nil,
    createReplacementSession: (@MainActor () async -> ChatSession?)? = nil
  ) async -> String? {
    let surface = mainChatSurfaceReference()
    var ownedClearTransaction: AuthorizedHarnessClearTransaction?
    let effectiveClearTransaction: AuthorizedHarnessClearTransaction
    if let authorizedClearTransaction {
      guard isAuthorizedHarnessClearTransactionCurrent(authorizedClearTransaction) else {
        return "owner changed during chat reset"
      }
      effectiveClearTransaction = authorizedClearTransaction
    } else {
      let admission = beginAuthorizedHarnessClearTransaction(surface: surface)
      guard let transaction = admission.transaction else {
        return admission.error ?? "chat clear unavailable"
      }
      ownedClearTransaction = transaction
      effectiveClearTransaction = transaction
    }
    defer {
      if let ownedClearTransaction {
        endAuthorizedHarnessClearTransaction(ownedClearTransaction)
      }
    }

    if isInDefaultChat {
      let runtimeChatId = mainChatRuntimeChatId(sessionId: nil)
      let defaultSurface = AgentSurfaceReference.mainChat(chatId: runtimeChatId)
      AgentRuntimeStatusStore.shared.clear(surface: defaultSurface)
      if !journalAlreadyCleared {
        let cleared: Bool
        #if DEBUG
          if let clearChatJournalForTests {
            cleared = await clearChatJournalForTests(runtimeChatId)
          } else {
            cleared = await kernelTurnProjection.clear(surface: defaultSurface)
          }
        #else
          cleared = await kernelTurnProjection.clear(surface: defaultSurface)
        #endif
        guard cleared else {
          return "failed to clear default kernel journal"
        }
        guard isAuthorizedHarnessClearTransactionCurrent(effectiveClearTransaction) else {
          return "owner changed during chat reset"
        }
      }
    } else {
      let sessionToDelete = currentSession
      if let session = sessionToDelete {
        let surface = AgentSurfaceReference.mainChat(chatId: session.id)
        AgentRuntimeStatusStore.shared.clear(surface: surface)
        if !journalAlreadyCleared {
          let cleared: Bool
          #if DEBUG
            if let clearChatJournalForTests {
              cleared = await clearChatJournalForTests(session.id)
            } else {
              cleared = await kernelTurnProjection.clear(surface: surface)
            }
          #else
            cleared = await kernelTurnProjection.clear(surface: surface)
          #endif
          guard cleared else {
            return "failed to clear session kernel journal"
          }
          guard isAuthorizedHarnessClearTransactionCurrent(effectiveClearTransaction) else {
            return "owner changed during chat reset"
          }
        }
      }
      if let session = sessionToDelete,
        let error = await deleteNamedChatCatalogForAuthorizedHarness(session)
      {
        return error
      }
      if let createReplacementSession {
        _ = await createReplacementSession()
      } else {
        guard await createNewSession(skipGreeting: true, allowWhileClearing: true) != nil else {
          return "failed to create replacement chat session"
        }
      }
    }
    return nil
  }

  /// Reset isolation must clear the same kernel-owned surface the flow will
  /// exercise. Fault bundles intentionally have no authenticated owner, so
  /// establish a temporary non-production owner for this transaction rather
  /// than bypassing the owner boundary or carrying a synthetic session forward.
  func automationResetMainChatForHarness() async -> String? {
    guard AppBuild.isNonProduction else { return nil }
    return await performMainChatHarnessResetTransaction()
  }

  /// Performs the owner-scoped reset transaction after the automation entrypoint
  /// has established that the bundle is non-production.
  func performMainChatHarnessResetTransaction(
    createReplacementSession: (@MainActor () async -> ChatSession?)? = nil
  ) async -> String? {
    let bundleScope = (Bundle.main.bundleIdentifier ?? "desktop")
      .replacingOccurrences(of: ".", with: "-")
    let resetOwnerID = "desktop-harness-reset-\(bundleScope)"
    return await RuntimeOwnerIdentity.withAutomationOwnerIfMissing(resetOwnerID) { [self] in
      // Clear the active main-chat surface, not a hard-coded "default". When
      // the provider is on an app-scoped default chat (default|<app>) or a
      // non-default session, a hard-coded "default" would clear the wrong
      // surface and leave the visible/persisted rows for the next ask intact.
      let activeChatId = mainChatSurfaceReference().externalRefId
      let surface = AgentSurfaceReference.mainChat(chatId: activeChatId)
      let admission = beginAuthorizedHarnessClearTransaction(surface: surface)
      guard let transaction = admission.transaction else {
        return admission.error ?? "chat clear unavailable"
      }
      defer { endAuthorizedHarnessClearTransaction(transaction) }
      let clear = await clearOwnerSurfaceStateForAuthorizedHarness(chatId: activeChatId)
      if let error = clear["error"] {
        return error
      }
      guard isAuthorizedHarnessClearTransactionCurrent(transaction) else {
        return "owner changed during chat reset"
      }
      return await resetChatForAuthorizedHarness(
        journalAlreadyCleared: true,
        authorizedClearTransaction: transaction,
        createReplacementSession: createReplacementSession
      )
    }
  }
}
