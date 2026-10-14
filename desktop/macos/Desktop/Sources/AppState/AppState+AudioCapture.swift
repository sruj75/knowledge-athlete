import Foundation

/// Owns ambient capture startup and capture-clock wiring to local or cloud transcription.
@MainActor
extension AppState {
  /// Master Listening arms the enabled ambient sources independently. Actual
  /// capture liveness determines B's status, not merely the session's armed bit.
  var supervisorAudioAvailability: (SupervisorInputAvailability, SupervisorInputAvailability) {
    let settings = AssistantSettings.shared
    guard settings.transcriptionEnabled else { return (.disabled, .disabled) }
    let microphone: SupervisorInputAvailability
    if !settings.ambientMicrophoneEnabled {
      microphone = .disabled
    } else if isTranscribing && audioCaptureService?.capturing == true {
      microphone = .available
    } else {
      microphone = AudioCaptureService.isPermissionDenied() ? .denied : .unavailable
    }
    let system: SupervisorInputAvailability
    if effectiveSystemAudioMode == .never {
      system = .disabled
    } else if #available(macOS 14.4, *), isTranscribing,
      (systemAudioCaptureService as? SystemAudioCaptureService)?.capturing == true
    {
      system = .available
    } else {
      system = systemAudioPermissionStatus == .denied ? .denied : .unavailable
    }
    return (microphone, system)
  }

  var ambientSystemAudioRequested: Bool {
    if #available(macOS 14.4, *) { return effectiveSystemAudioMode == .always }
    return false
  }

  /// Start the independently enabled microphone and system-audio sources.
  func startAudioCapture() async {
    await startMicrophoneAudioCapture()
  }

  /// Prepare the session's audio sinks. `reconcileCapture()` independently starts
  /// microphone and system audio according to their settings and permission.
  /// Captured audio is mixed into one mono stream (cloud) or fed to separate Parakeet instances
  /// (local) so calls/videos/music end up in the transcript alongside the user's voice.
  func startMicrophoneAudioCapture() async {
    guard let audioCaptureService = audioCaptureService else { return }

    // Silent-mic watchdog: CoreAudio can report a healthy IOProc while a Bluetooth, USB, or
    // built-in input returns only zeros. Listen/manual/Quick Note all flow through here, so
    // they must opt into all-transport detection just as PTT does.
    SharedCaptureSilentMicRecoveryPolicy.configure(audioCaptureService)
    audioCaptureService.onSilentMicDetected = { [weak self] detection in
      Task { @MainActor in
        switch detection.suggestedAction {
        case .fallbackToBuiltIn:
          self?.handleSilentMicFallback()
        case .rebuildCoreAudioStack:
          await self?.handleSharedCaptureSilentMicDetection(reason: detection.reason)
        }
      }
    }

    // Cloud mode: the mixer sums mic + system into one mono stream for the WebSocket.
    // Local mode: bypass the mixer — mic and system are transcribed by SEPARATE Parakeet
    // instances so transcripts are diarized by source (mic = you, system = another speaker).
    if !sttSession.useLocalSTT {
      audioMixer?.startObserved { [weak self] monoMixed, captureInterval in
        self?.transcriptionService?.sendAudio(monoMixed, captureInterval: captureInterval)
      }
    }

    // Apply each input setting; a missing microphone does not block system audio.
    await reconcileCapture()

    log("Transcription: Audio capture armed (microphone and system audio per setting)")
  }

  /// Start microphone capture and wire its chunks/level to the active sink (the mixer in cloud mode,
  /// the mic Parakeet instance in local mode).
  /// - Returns: true if the mic is capturing after the call (already capturing or started OK);
  ///   false on a hard start failure (or if the session was torn down during the async start).
  @discardableResult
  func startMicCaptureIfNeeded() async -> Bool {
    guard AssistantSettings.shared.ambientMicrophoneEnabled, hasMicrophonePermission,
      let mic = audioCaptureService
    else { return false }
    guard !mic.capturing else { return true }
    do {
      let useLocalSTT = sttSession.useLocalSTT
      let localSink = localMicAudioSink
      let mixer = audioMixer
      try await mic.startCapture(
        onAudioChunk: { audioData in
          let captureInterval = SupervisorCaptureInterval.captured(byteCount: audioData.count)
          if useLocalSTT {
            localSink.append(audioData, captureInterval: captureInterval)
          } else {
            mixer?.setMicAudio(audioData, captureInterval: captureInterval)
          }
        },
        onAudioLevel: { level in
          // Use dedicated monitor to avoid triggering AppState re-renders
          AudioLevelMonitor.shared.updateMicrophoneLevel(level)
        }
      )
      // The HAL setup above is async and can be slow. If recording stopped — or the service was
      // swapped (silent-mic fallback) — while we were awaiting it, undo the just-started capture.
      guard isTranscribing, audioCaptureService === mic,
        AssistantSettings.shared.ambientMicrophoneEnabled, hasMicrophonePermission
      else {
        mic.stopCapture()
        return false
      }
      log("Transcription: Microphone capture started")
      return true
    } catch {
      logError("Transcription: Failed to start microphone capture", error: error)
      return false
    }
  }

  /// Start the system-audio tap and wire its chunks/levels to the active sink (the mixer in cloud
  /// mode, the system Parakeet instance in local mode). No-op if already capturing. System audio is
  /// optional — a failure is logged and mic-only capture continues.
  @available(macOS 14.4, *)
  func startSystemAudioCaptureIfNeeded() async {
    guard let systemService = systemAudioCaptureService as? SystemAudioCaptureService else { return }
    guard !systemService.capturing else { return }
    do {
      let useLocalSTT = sttSession.useLocalSTT
      let localSink = localSystemAudioSink
      let mixer = audioMixer
      try await systemService.startCapture(
        onAudioChunk: { audioData in
          let captureInterval = SupervisorCaptureInterval.captured(byteCount: audioData.count)
          if useLocalSTT {
            localSink.append(audioData, captureInterval: captureInterval)
          } else {
            mixer?.setSystemAudio(audioData, captureInterval: captureInterval)
          }
        },
        onAudioLevel: { level in
          Task { @MainActor in
            AudioLevelMonitor.shared.updateSystemLevel(level)
          }
        }
      )
      // The HAL setup above is async and can be slow. If recording stopped — or the service was
      // torn down / recreated — while we were awaiting it, immediately stop the just-started tap
      // so we don't leave an orphaned capture running.
      guard isTranscribing, effectiveSystemAudioMode == .always,
        (systemAudioCaptureService as? SystemAudioCaptureService) === systemService
      else {
        systemService.stopCapture()
        log("Transcription: System audio capture aborted (recording stopped during start)")
        return
      }
      recordSystemAudioCaptureOutcome(.granted)
      log("Transcription: System audio capture started (mode=\(effectiveSystemAudioMode.rawValue))")
    } catch {
      // Mirror the success path's staleness guards: if recording stopped or the
      // service was replaced while startCapture was suspended, the failure says
      // nothing about permission for the CURRENT session — don't record it.
      guard isTranscribing,
        (systemAudioCaptureService as? SystemAudioCaptureService) === systemService
      else {
        log("Transcription: System audio capture failed after session ended — outcome not recorded")
        return
      }
      recordSystemAudioCaptureOutcome(SystemAudioPermissionStatus.classify(captureError: error))
      logError(
        "Transcription: System audio capture failed (continuing with mic only)", error: error)
    }
  }
}
