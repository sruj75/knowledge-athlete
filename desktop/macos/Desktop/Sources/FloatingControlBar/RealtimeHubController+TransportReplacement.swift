import Foundation
import VoiceTurnDomain

@MainActor
extension RealtimeHubController {
  var isTransportReady: Bool {
    guard !physicalPTTTransportFault.blocksTransport else { return false }
    guard
      RealtimeHubOwnerFence.canReuseWarmSession(
        sessionOwner: sessionOwnerScope,
        currentOwnerID: RuntimeOwnerIdentity.currentOwnerId())
    else {
      if session != nil {
        log("RealtimeHub: refusing warm socket owned by a previous authenticated user")
        discardSessionAfterOwnerChange()
      }
      return false
    }
    let physicalProviderMatchesSelection = sessionProvider == .gemini
    #if DEBUG
      return RealtimeTransportReadinessPolicy.isReady(
        hubConnected: hubConnected,
        physicalProviderMatchesSelection: physicalProviderMatchesSelection,
        localProfileTransportAuthorized: isAuthorizedLocalProfileTransport())
    #else
      return hubConnected && physicalProviderMatchesSelection
    #endif
  }

  /// Arms or clears the next-physical-turn transport fault. Identity validation
  /// lives in the gate as defense in depth: the production bridge is absent from
  /// release bundles, but Stable, Beta, preview, and canonical Dev are rejected
  /// even if this method is invoked directly.
  func configurePhysicalPTTTransportFault(
    operation: String,
    bundleIdentifier: String
  ) -> [String: String] {
    let result: RealtimePhysicalPTTTransportFaultGate.CommandResult
    switch operation {
    case "arm":
      result = physicalPTTTransportFault.arm(bundleIdentifier: bundleIdentifier)
    case "clear":
      result = physicalPTTTransportFault.clear(bundleIdentifier: bundleIdentifier)
    default:
      return [
        "error": "unsupported operation; expected arm or clear",
        "fault_state": physicalPTTTransportFault.diagnosticsState,
      ]
    }

    switch result {
    case .armed:
      return [
        "armed": "true",
        "auto_restore": "terminal",
        "fault_state": physicalPTTTransportFault.diagnosticsState,
        "scope": "next_physical_ptt_turn",
      ]
    case .cleared:
      return [
        "cleared": "true",
        "fault_state": physicalPTTTransportFault.diagnosticsState,
      ]
    case .rejectedIdentity:
      return [
        "error": "physical PTT transport fault requires a named development bundle",
        "fault_state": physicalPTTTransportFault.diagnosticsState,
      ]
    case .rejectedActive:
      return [
        "error": "physical PTT transport fault is active until its turn terminates",
        "fault_state": physicalPTTTransportFault.diagnosticsState,
      ]
    }
  }

  /// Consumes the armed fault only for the real microphone path, detaching the
  /// active Gemini socket before admission is selected. The manager continues
  /// capturing while the existing warm-wait deadline chooses batch recovery.
  @discardableResult
  func activatePhysicalPTTTransportFaultIfArmed(
    turnID: VoiceTurnID,
    isPhysicalMicrophone: Bool
  ) -> Bool {
    guard
      physicalPTTTransportFault.activateIfArmed(
        turnID: turnID,
        isPhysicalMicrophone: isPhysicalMicrophone)
    else { return false }

    invalidatePendingMint()
    // Use the sole physical replacement owner. Its start closure retries warm-up
    // only after `stopAndWait` acknowledges the old transport closed; while the
    // fault is active that retry is safely deferred, and an early terminal restore
    // is likewise coalesced behind the same drain.
    replaceSessionAfterDrain(rewarmAfterDrain: true)
    log("RealtimeHub: activated one-turn physical PTT transport fault")
    return true
  }

  func replaceSessionAfterDrain(
    preservingReconnectAudio: Bool = false,
    preservingBargeInReplacement: Bool = false,
    reconnectDelayNanoseconds: UInt64 = 0,
    rewarmAfterDrain: Bool = true
  ) {
    guard !sessionReplacementGate.isPending else {
      log("RealtimeHub: coalescing physical replacement while transport drain is pending")
      return
    }
    let detachedSession = detachPhysicalSessionForTeardown(
      preservingReconnectAudio: preservingReconnectAudio,
      preservingBargeInReplacement: preservingBargeInReplacement)
    let ownerGeneration = ownerBoundaryGeneration
    let detachedSessionID = detachedSession.map(ObjectIdentifier.init)
    if let detachedSession, let detachedSessionID {
      detachedSessionsAwaitingDrain[detachedSessionID] = detachedSession
    }
    sessionReplacementGate.replace(
      reconnectDelayNanoseconds: reconnectDelayNanoseconds,
      stop: { [weak self, weak detachedSession] in
        guard let self else { return }
        if let detachedSession {
          await detachedSession.stopAndWait()
        }
        if let detachedSessionID {
          self.detachedSessionsAwaitingDrain.removeValue(forKey: detachedSessionID)
        }
      },
      start: { [weak self] in
        guard let self, self.ownerBoundaryGeneration == ownerGeneration else { return }
        self.reconnectPending = false
        let abandonedBargeInReplacement =
          preservingBargeInReplacement && self.pendingBargeInOwnerScope == nil
        if rewarmAfterDrain || abandonedBargeInReplacement, self.session == nil {
          #if DEBUG
            if let testingWarmAfterDrain = self.testingWarmAfterDrain {
              testingWarmAfterDrain()
              return
            }
          #endif
          self.ensureWarm()
        }
      })
  }

  func schedulePhysicalSessionTeardown(_ detachedSession: RealtimeHubSession) {
    let sessionID = ObjectIdentifier(detachedSession)
    guard detachedSessionsAwaitingDrain[sessionID] == nil else { return }
    detachedSessionsAwaitingDrain[sessionID] = detachedSession
    Task { @MainActor [weak self, weak detachedSession] in
      guard let detachedSession else { return }
      await detachedSession.stopAndWait()
      self?.detachedSessionsAwaitingDrain.removeValue(forKey: sessionID)
    }
  }
}
