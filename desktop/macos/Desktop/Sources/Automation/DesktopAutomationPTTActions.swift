import Foundation

extension DesktopAutomationActionRegistry {
  func registerPTTActions() {
    // Drive the real push-to-talk state machine headlessly (MIC-01). ptt_start begins
    // capture like the shortcut key-down; ptt_stop finalizes like a long-hold release.
    // Releasing with no mic audio exercises the empty-batch release path — it must end
    // the turn with a hint, not hang. Both hit the exact private startListening/finalize
    // the shortcut handler calls, so no synthetic key events or cursor are involved.
    register(
      name: "ptt_start",
      summary: "Begin a push-to-talk capture (mirrors the PTT shortcut key-down)"
    ) { _ in
      PushToTalkManager.shared.beginPushToTalkForAutomation()
    }

    register(
      name: "ptt_stop",
      summary: "Finalize the in-progress push-to-talk capture (mirrors a long-hold release)"
    ) { _ in
      PushToTalkManager.shared.endPushToTalkForAutomation()
    }

    // Manager-level PTT harness: this crosses the real shortcut lifecycle,
    // routing decision, realtime admission, warm buffering, and replay seam.
    // Unlike `ptt_test_turn`, it does not bypass PushToTalkManager; unlike a
    // physical test, it needs neither microphone permission nor a device.
    register(
      name: "ptt_manager_turn",
      summary:
        "Inject a PCM16/16k mono hold through PushToTalkManager and realtime admission; returns lifecycle diagnostics",
      params: ["pcm"]
    ) { params in
      guard let path = params["pcm"],
        let pcm16k = try? Data(contentsOf: URL(fileURLWithPath: path)),
        !pcm16k.isEmpty
      else { return ["error": "missing or unreadable 'pcm' file (expected raw s16le 16k mono)"] }

      var result = PushToTalkManager.shared.beginRealtimePushToTalkForAutomation()
      guard result["listening"] == "true" else { return result }
      let chunkSize = 3_200
      var offset = 0
      var injected = 0
      while offset < pcm16k.count {
        let end = min(offset + chunkSize, pcm16k.count)
        if PushToTalkManager.shared.injectRealtimePTTAutomationAudio(pcm16k.subdata(in: offset..<end)) {
          injected += end - offset
        }
        offset = end
      }
      let stopped = PushToTalkManager.shared.endPushToTalkForAutomation()
      result["injected_bytes"] = "\(injected)"
      result["finalized"] = stopped["finalized"] ?? "false"
      for (key, value) in RealtimeHubController.shared.automationPTTDiagnostics() {
        result[key] = value
      }
      return result
    }

    register(
      name: "ptt_turn_snapshot",
      summary: "Return typed PTT lifecycle state, pending-tool fences, and safe screen-evidence diagnostics"
    ) { _ in
      RealtimeHubController.shared.automationPTTDiagnostics()
    }

    register(
      name: "ptt_live_transport_fault",
      summary:
        "Arm or clear a named-development-only Gemini outage for the next physical microphone PTT turn",
      params: ["operation"],
      category: "voice",
      surfaces: ["floating_bar"],
      safety: "non_production_fault",
      sideEffects: ["temporarily detaches Gemini transport for one physical PTT turn"],
      examples: ["./scripts/omi-ctl action ptt_live_transport_fault operation=arm"]
    ) { params in
      RealtimeHubController.shared.configurePhysicalPTTTransportFault(
        operation: params["operation"] ?? "arm",
        bundleIdentifier: AppBuild.bundleIdentifier)
    }
  }
}
