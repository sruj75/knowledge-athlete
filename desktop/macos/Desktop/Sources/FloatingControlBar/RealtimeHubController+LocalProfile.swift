import Foundation
import OmiSupport
import VoiceTurnDomain

#if DEBUG
  @MainActor
  extension RealtimeHubController {
    /// Hermetic `ptt_test_turn` transport for `OMI_DESKTOP_LOCAL_PROFILE=1`.
    /// Provider events are synthesized, but every logical boundary remains the
    /// production boundary: voice reducer, external-run capability, tool ledger,
    /// spawn journal receipt, and kernel turn finalization.
    func runLocalProfileHeadlessPTTTurn(
      pcm16k: Data,
      timeout: Double,
      forceTranscript: String?,
      textOnly: Bool
    ) async -> [String: String] {
      guard !RuntimeOwnerIdentity.effectiveOwnerTransitionInProgress else {
        return ["error": "local-profile realtime transport unavailable during owner transition"]
      }
      guard let forceTranscript,
        !forceTranscript.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      else {
        return ["error": "local-profile ptt_test_turn requires a non-empty force_transcript"]
      }

      let localOwnerScope = currentOwnerScope
      guard let localOwnerID = localOwnerScope.authenticatedOwnerID,
        let localAuthorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot(
          expectedOwnerID: localOwnerID)
      else {
        return ["error": "local-profile realtime transport requires an authenticated owner"]
      }
      revokeManagedMintForLocalProfileTransportPreparation()
      teardownSession()
      let localSession = RealtimeHubSession(
        provider: .openai,
        auth: .hermeticStub,
        instructions: "Hermetic local-profile realtime transport.",
        delegate: self)
      lastWarmAt = nil
      hubConnected = false
      session = localSession
      voiceSessionID = VoiceSessionID()
      sessionProvider = .openai
      sessionAuth = .hermeticStub
      sessionOwnerBinding = PhysicalSessionOwnerBinding(
        sourceID: ObjectIdentifier(localSession),
        ownerScope: localOwnerScope)
      localProfileTransportAuthority = RealtimeLocalProfileTransportAuthority(
        sourceID: ObjectIdentifier(localSession),
        ownerScope: localOwnerScope,
        authorizationSnapshot: localAuthorization)
      defer {
        if session === localSession {
          teardownSession()
        }
      }
      guard await refreshVoiceContextSnapshot(),
        !RuntimeOwnerIdentity.effectiveOwnerTransitionInProgress,
        !prefetchedVoiceContextSessionID.isEmpty
      else {
        return ["error": "local-profile realtime voice context session is unavailable"]
      }
      let preparedContext = voiceSessionContext(for: localOwnerScope)
      guard preparedContext.isResolved else {
        return ["error": "local-profile realtime voice context did not resolve"]
      }
      sessionVoiceContextFreshnessIdentity = preparedContext.snapshotFreshnessIdentity
      sessionVoiceContextSurface = preparedContext.surface
      idleVoiceContextRefreshTask?.cancel()
      idleVoiceContextRefreshTask = nil
      guard
        let plan = RealtimeLocalProfileTurnPlan.make(
          transcript: forceTranscript,
          voiceContext: prefetchedVoiceContext,
          localProfileEnabled: DesktopLocalProfile.isEnabled)
      else {
        return ["error": "local-profile realtime provider could not plan the test turn"]
      }
      localSession.markReadyForTesting()
      guard
        await waitUntilLocalProfileTransportReady(
          localSession,
          ownerScope: localOwnerScope,
          timeout: min(3, max(1, timeout)))
      else {
        return ["error": "local-profile realtime transport did not become active"]
      }

      lastTurnDiagnostics = [:]
      let turnID = RealtimeAutomationTurnHarness.begin(on: VoiceTurnCoordinator.shared)
      VoiceTurnCoordinator.shared.publish(
        .selectRoute(turnID: turnID, route: .hub(sessionID: voiceSessionID)))
      if plan.requestsCurrentScreen {
        _ = PushToTalkManager.shared.captureScreenEvidenceForAutomation(turnID: turnID)
      }
      // Screen capture can overlap a kernel-context refresh. The hermetic socket has no
      // provider-side context to rebuild, so bind it to the latest resolved requirement at
      // the same input-admission boundary where a physical socket would be replaced.
      let admissionContext = voiceSessionContext(for: localOwnerScope)
      guard admissionContext.isResolved else {
        VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .providerFailed))
        return ["error": "local-profile realtime voice context changed before input admission"]
      }
      sessionVoiceContextFreshnessIdentity = admissionContext.snapshotFreshnessIdentity
      sessionVoiceContextSurface = admissionContext.surface
      guard beginTurn(turnID: turnID) == .accepted else {
        VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .providerFailed))
        return ["error": "local-profile realtime reducer rejected synthetic input admission"]
      }
      if !textOnly {
        feedAudio(Data(pcm16k.prefix(3_200)), turnID: turnID)
      }
      VoiceTurnCoordinator.shared.publish(.finalize(turnID: turnID))
      let commitResult = commitTurn()
      guard commitResult == .accepted, let responseID = voiceResponseID else {
        let failedTurn = VoiceTurnCoordinator.shared.activeTurn
        let recentTimeline = VoiceTurnCoordinator.shared.timelineSnapshot().suffix(6).map {
          "\($0.sequence):\($0.event):"
            + "\($0.phaseBefore.map(VoiceTurnCoordinator.phaseLabel) ?? "idle")->"
            + "\($0.phaseAfter.map(VoiceTurnCoordinator.phaseLabel) ?? "idle")"
        }.joined(separator: ",")
        let phase = failedTurn.map { VoiceTurnCoordinator.phaseLabel($0.phase) } ?? "idle"
        let route = failedTurn.map { VoiceTurnCoordinator.routeLabel($0.route) } ?? "none"
        let diagnostic = RealtimeLocalProfileRejectedCommitDiagnostics.make(
          commitResult: "\(commitResult)",
          phase: phase,
          route: route,
          ownerID: failedTurn?.ownerID,
          recentTimeline: recentTimeline)
        log(diagnostic.logMessage)
        VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .providerFailed))
        return diagnostic.response
      }

      let eventIdentity = RealtimeHubEventIdentity(turnID: turnID, responseID: responseID)
      hubDidReceiveInputTranscript(
        forceTranscript,
        isFinal: true,
        identity: eventIdentity,
        source: localSession)

      if plan.requestsCurrentScreen {
        let screenshotCallID = "local-profile-screenshot-\(turnID.rawValue.uuidString.lowercased())"
        hubDidRequestTool(
          name: HubTool.screenshot.rawValue,
          callId: screenshotCallID,
          argumentsJSON: "{}",
          identity: eventIdentity,
          source: localSession)

        let screenshotDeadline = Date().addingTimeInterval(max(1, timeout))
        var shouldReportObservation = false
        while Date() < screenshotDeadline {
          switch screenGroundingState {
          case .awaitingReport:
            shouldReportObservation = true
          case .inactive where lastScreenEvidenceProtocolCompletion == .completed:
            break
          case .rejected:
            return ["error": "local-profile screen evidence protocol was rejected"]
          case .inactive, .awaitingScreenshot, .accepted:
            try? await Task.sleep(nanoseconds: 50_000_000)
            continue
          }
          break
        }

        if shouldReportObservation {
          let reportCallID = "local-profile-screen-report-\(turnID.rawValue.uuidString.lowercased())"
          hubDidRequestTool(
            name: HubTool.reportScreenObservation.rawValue,
            callId: reportCallID,
            argumentsJSON: #"{"observation":"Current screen evidence reviewed."}"#,
            identity: eventIdentity,
            source: localSession)
        }

        let reportDeadline = Date().addingTimeInterval(max(1, timeout))
        while Date() < reportDeadline {
          if lastScreenEvidenceProtocolCompletion == .completed,
            VoiceTurnCoordinator.shared.activeTurn?.screenEvidenceProtocol == nil
          {
            break
          }
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard lastScreenEvidenceProtocolCompletion == .completed else {
          VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .toolTimeout))
          return ["error": "local-profile screen evidence protocol did not finish within \(Int(timeout))s"]
        }
      }

      var reply = plan.assistantText
      if let spawn = plan.spawn {
        let callID = "local-profile-spawn-\(turnID.rawValue.uuidString.lowercased())"
        hubDidRequestTool(
          name: "spawn_agent",
          callId: callID,
          argumentsJSON: Self.localProfileSpawnArgumentsJSON(spawn),
          identity: eventIdentity,
          source: localSession)

        let toolDeadline = Date().addingTimeInterval(max(1, timeout))
        while Date() < toolDeadline {
          let pending =
            VoiceTurnCoordinator.shared.activeTurn?.pendingToolCallIDs
            .contains(VoiceToolCallID(callID)) == true
          if !pending {
            if let receipt = acceptedSpawnJournalReceiptByContinuityKey[turnIdempotencyKey] {
              reply = receipt.receipt.assistantText
              break
            }
            VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .providerFailed))
            return ["error": "local-profile spawn_agent completed without a canonical journal receipt"]
          }
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard acceptedSpawnJournalReceiptByContinuityKey[turnIdempotencyKey] != nil else {
          VoiceTurnCoordinator.shared.publish(.finish(turnID: turnID, reason: .toolTimeout))
          return ["error": "local-profile spawn_agent did not finish within \(Int(timeout))s"]
        }
      }

      // A post-tool provider continuation clears the reducer's continuation fence.
      // `isFinal=false` avoids physical speech in a cursor-free hermetic run; the
      // following turn-finished event remains the authoritative provider boundary.
      assistantText = ""
      hubDidEmitText(
        reply,
        isFinal: false,
        identity: eventIdentity,
        source: localSession)
      hubDidFinishTurn(identity: eventIdentity, source: localSession)

      let completionDeadline = Date().addingTimeInterval(max(1, timeout))
      while Date() < completionDeadline {
        if let terminal = VoiceTurnCoordinator.shared.model.lastTerminal,
          terminal.turnID == turnID
        {
          guard terminal.reason == .success else {
            return ["error": "local-profile voice turn terminated with \(terminal.reason.rawValue)"]
          }
          if !lastTurnDiagnostics.isEmpty { return lastTurnDiagnostics }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
      return ["error": "local-profile voice turn did not finalize within \(Int(timeout))s"]
    }

    /// A managed mint admitted before the local-profile action cannot be allowed to publish
    /// provider state after the exact hermetic transport authority has taken ownership.
    func revokeManagedMintForLocalProfileTransportPreparation() {
      mintGeneration &+= 1
      minting = false
      mintOwnerScope = nil
    }

    /// Waits on the exact hermetic socket without entering `ensureWarm()` or
    /// comparing it with the user's provider preference. Both operations are
    /// correct for production warm sessions and wrong for an offline transport.
    func waitUntilLocalProfileTransportReady(
      _ source: RealtimeHubSession,
      ownerScope: RealtimeHubOwnerScope,
      timeout: TimeInterval
    ) async -> Bool {
      let deadline = Date().addingTimeInterval(timeout)
      repeat {
        guard localProfileTransportAuthority?.ownerScope == ownerScope,
          isAuthorizedLocalProfileTransport(source),
          source === session
        else { return false }
        if hubConnected, await source.activityWindowOpen() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
        if Task.isCancelled { return false }
      } while Date() < deadline
      guard isAuthorizedLocalProfileTransport(source), source === session, hubConnected else {
        return false
      }
      return await source.activityWindowOpen()
    }

    nonisolated static func localProfileSpawnArgumentsJSON(
      _ spawn: RealtimeLocalProfileTurnPlan.Spawn
    ) -> String {
      let payload: [String: Any] = [
        "objective": spawn.objective,
        "title": spawn.title,
        "visible": true,
      ]
      guard
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8)
      else { return "{}" }
      return json
    }
  }
#endif
