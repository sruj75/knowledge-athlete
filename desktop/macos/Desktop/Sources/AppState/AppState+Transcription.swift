@preconcurrency import AVFoundation
import Combine
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
extension AppState {
  func quiesceAmbientCaptureForOwnerTransition() async {
    guard isTranscribing || transcriptionStartTask != nil else { return }
    recordingGeneration &+= 1
    transcriptionStartTask?.cancel()
    transcriptionStartTask = nil
    conversationLocationTask?.cancel()
    conversationLocationTask = nil

    let wasLocalSTT = sttSession.useLocalSTT
    let mic = localMicService
    let system = localSystemService
    let cloud = transcriptionService
    localMicService = nil
    localSystemService = nil
    transcriptionService = nil
    stopAudioCapture()
    if wasLocalSTT {
      mic?.discardBufferedAudio()
      system?.discardBufferedAudio()
    } else {
      cloud?.stop(discardBufferedAudio: true)
      await segmentDeliveryQueue.drain()
    }
    localMicAudioSink.clear()
    localSystemAudioSink.clear()
    clearTranscriptionState(runFinalizer: false, finishSession: false)
  }

  func toggleTranscription() {
    if isTranscribing {
      stopTranscription()
    } else {
      OnboardingExitPersistence.recordExplicitCapabilityEnablement()
      startTranscription()
    }
  }

  /// Start real-time transcription
  func startTranscription() {
    guard !isTranscribing, transcriptionStartTask == nil else { return }
    sttSession.prepareForStart()
    silentMicRecoveryAttempts = 0
    meetingEndFinalizationInProgress = false

    // Paywall hard-stop: every code path that enables the mic + WS streaming
    // funnels through here, including auto-restart from sleep and toggle
    // shortcuts. Refuse to start and surface the upgrade popup.
    if blockIfPaywalled() { return }

    guard AudioCaptureService.checkPermission() else {
      requestMicrophonePermission()
      return
    }

    recordingGeneration &+= 1
    let admissionGeneration = recordingGeneration
    transcriptionStartTask = Task { @MainActor [weak self] in
      await self?.startTranscriptionAfterLocalAdmission(
        admissionGeneration: admissionGeneration)
    }
  }

  private func startTranscriptionAfterLocalAdmission(admissionGeneration: UInt64) async {
    defer {
      if recordingGeneration == admissionGeneration {
        transcriptionStartTask = nil
      }
    }
    do {
      // Get effective language from settings (handles auto-detect vs single language)
      let effectiveLanguage = AssistantSettings.shared.effectiveTranscriptionLanguage
      log(
        "Transcription: Using language=\(effectiveLanguage) (autoDetect=\(AssistantSettings.shared.transcriptionAutoDetect), selected=\(AssistantSettings.shared.transcriptionLanguage))"
      )

      recordingInputDeviceName = AudioCaptureService.getCurrentMicrophoneName()
      let admission = try await beginLocalConversation(
        language: effectiveLanguage, inputDeviceName: recordingInputDeviceName)
      let handle = admission.handle
      guard !Task.isCancelled, recordingGeneration == admissionGeneration else {
        try? await TranscriptionStorage.shared.deleteConversationCascade(
          id: handle.conversationId, authorization: admission.authorization)
        return
      }
      currentSessionId = handle.sessionId
      currentConversationId = handle.conversationId
      currentSessionAuthorization = admission.authorization
      let producerSessionId = handle.sessionId
      LiveNotesMonitor.shared.startSession(sessionId: handle.sessionId)
      startConversationLocationCaptureIfEnabled(
        conversationId: handle.conversationId,
        admissionGeneration: admissionGeneration)
      log("Transcription: Created DB session \(handle.sessionId) before capture")

      // Desktop transcribes on-device with Parakeet by default on Apple Silicon — no Deepgram.
      // Intel Macs (no Neural Engine) fall back to the cloud path. Force cloud for debugging with
      // OMI_FORCE_CLOUD_STT=1 or `defaults write <bundle> forceCloudSTT -bool true`.
      let debugForceCloud = STTSessionState.debugForceCloudSTT(
        environmentForceCloud: ProcessInfo.processInfo.environment["OMI_FORCE_CLOUD_STT"] == "1",
        userDefaultsForceCloud: UserDefaults.standard.bool(forKey: "forceCloudSTT")
      )
      sttSession.beginRecording(
        isAppleSilicon: Self.isAppleSilicon,
        debugForceCloud: debugForceCloud
      )
      if sttSession.useLocalSTT {
        log("Transcription: ON-DEVICE Parakeet mode (OMI_LOCAL_STT) — no cloud STT")
        // Segments are delivered on the main actor by the service, so no Task hop here.
        let onLocalSegments: LocalTranscriptionService.SegmentsHandler = { [weak self] segments in
          await self?.handleBackendSegments(segments, expectedSessionId: producerSessionId)
        }
        // If the on-device model can't load, fall back to cloud STT instead of recording
        // into a void (the failure is otherwise silent — a blank transcript).
        let onModelLoadFailed: @MainActor () -> Void = { [weak self] in
          guard self?.currentSessionId == producerSessionId else { return }
          self?.handleLocalSTTModelLoadFailure()
        }
        // Mic = the user; system audio = another speaker. Transcribed separately for diarization.
        let mic = LocalTranscriptionService(language: effectiveLanguage, isUser: true)
        mic.start(onSegments: onLocalSegments, onModelLoadFailed: onModelLoadFailed)
        localMicService = mic
        localMicAudioSink.completeHandoff(to: mic)
        let system = LocalTranscriptionService(language: effectiveLanguage, isUser: false)
        system.start(onSegments: onLocalSegments, onModelLoadFailed: onModelLoadFailed)
        localSystemService = system
        localSystemAudioSink.completeHandoff(to: system)
      } else {
        // Always streaming via Python backend /v4/listen
        let settings = AssistantSettings.shared
        transcriptionService = try TranscriptionService(
          language: effectiveLanguage,
          translationTarget: settings.transcriptionAutoDetect ? settings.transcriptionLanguage : nil,
          vocabulary: settings.effectiveVocabulary
        )
      }

      audioCaptureService = AudioCaptureService()
      audioMixer = AudioMixer()
      vadGateService = nil

      // Initialize system audio capture if supported (macOS 14.4+) and not in "Never" mode.
      // The actual start/stop is driven by reconcileCapture() based on the user's System Audio
      // mode (Always / Only during meetings / Never) and meeting state. `.never` is also forced
      // by the hidden `disableSystemAudioCapture` debug flag — see effectiveSystemAudioMode.
      let systemAudioMode = effectiveSystemAudioMode
      if systemAudioMode == .never {
        log("Transcription: System audio capture mode = never — not initializing")
      } else if #available(macOS 14.4, *) {
        systemAudioCaptureService = SystemAudioCaptureService()
        log(
          "Transcription: System audio capture initialized (mode=\(systemAudioMode.rawValue), macOS 14.4+)"
        )
      } else {
        log("Transcription: System audio capture not available (requires macOS 14.4+)")
      }

      // Streaming mode: start transcription service first, then audio on connect.
      // Local (Parakeet) mode has no WebSocket — start capture immediately instead.
      if sttSession.useLocalSTT {
        Task { @MainActor [weak self] in
          guard self?.currentSessionId == producerSessionId else { return }
          await self?.startAudioCapture()
        }
      } else {
        transcriptionService?.start(
          onSegments: { [weak self] segments in
            self?.segmentDeliveryQueue.submit { [weak self] in
              await self?.handleBackendSegments(segments, expectedSessionId: producerSessionId)
            }
          },
          onEvent: { [weak self] event in
            self?.segmentDeliveryQueue.submit { [weak self] in
              await self?.handleListenEvent(event, expectedSessionId: producerSessionId)
            }
          },
          onError: { [weak self] error in
            Task { @MainActor in
              guard let self, self.currentSessionId == producerSessionId else { return }
              logError("Transcription error", error: error)
              AnalyticsManager.shared.recordingError(
                error: error.localizedDescription,
                reason: "cloud_stt_error",
                source: "desktop",
                stage: "streaming"
              )
              // Cloud WS gave up (reconnects exhausted) → try to keep recording on-device
              // instead of dropping it. Falls through to stopTranscription if not possible.
              self.handleCloudSTTReconnectFailure()
            }
          },
          onConnected: { [weak self] in
            Task { @MainActor in
              guard let self, self.currentSessionId == producerSessionId else { return }
              log("Transcription: Connected to Python backend")
              // Start audio capture once connected
              await self.startAudioCapture()
            }
          },
          onDisconnected: {
            log("Transcription: Disconnected from Python backend")
          }
        )
      }

      isTranscribing = true
      AssistantSettings.shared.transcriptionEnabled = true
      currentTranscript = ""
      speakerSegments = []
      totalSegmentCount = 0
      totalWordCount = 0
      liveSpeakerNames = [:]
      LiveTranscriptMonitor.shared.clear()
      recordingStartTime = Date()
      AudioLevelMonitor.shared.reset()
      RecordingTimer.shared.start()

      log(
        "Transcription: Using source: desktop, device: \(recordingInputDeviceName ?? "Unknown")"
      )

      // Start 4-hour max recording timer
      maxRecordingTimer = Timer.scheduledTimer(
        withTimeInterval: maxRecordingDuration, repeats: false
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self = self, self.isTranscribing else { return }
          log("Transcription: 4-hour limit reached - restarting session")
          let sessionId = self.currentSessionId
          let authorization = self.currentSessionAuthorization
          let wasLocalSTT = self.sttSession.useLocalSTT
          let mic = self.localMicService
          let sys = self.localSystemService
          if wasLocalSTT {
            self.localMicService = nil
            self.localSystemService = nil
          }
          // Stop, durably queue finalization, and restart.
          self.stopAudioCapture()
          if wasLocalSTT {
            await mic?.finish()
            await sys?.finish()
          } else {
            await self.segmentDeliveryQueue.drain()
          }
          let finishedConversationId = await self.finishSessionAndRefreshImmediately(
            sessionId: sessionId,
            reason: .maxDurationRotation,
            authorization: authorization)
          self.clearTranscriptionState(
            finalizationReason: .maxDurationRotation,
            runFinalizer: false,
            finishSession: false
          )
          if let finishedConversationId {
            Task {
              await self.processFinishedConversationAndRefresh(
                conversationId: finishedConversationId)
            }
          }
          self.startTranscription()
        }
      }

      // Track transcription started
      AnalyticsManager.shared.transcriptionStarted()

      log("Transcription: Starting...")

    } catch {
      guard !Task.isCancelled, recordingGeneration == admissionGeneration else { return }
      AnalyticsManager.shared.recordingError(
        error: error.localizedDescription,
        reason: "start_transcription_failed",
        source: "desktop",
        stage: "startup"
      )
      showAlert(
        title: "Couldn't Start Transcription",
        message: UserFacingErrorPresentation.message(for: error, while: .transcription)
      )
    }
  }

  /// Start microphone and optional system-audio capture.
  func startAudioCapture() async {
    await startMicrophoneAudioCapture()
  }

  /// Arm microphone + system audio capture for the session. Actual capture is managed by
  /// `reconcileCapture()` according to the System Audio mode + meeting state:
  ///  - Always / Never: the microphone runs for the whole session (system audio per mode).
  ///  - Only during meetings: nothing is captured until a call is detected, then mic + system
  ///    start, and both pause when the call ends — so the mic (and its indicator) stays off
  ///    outside meetings.
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
      audioMixer?.start { [weak self] monoMixed in
        self?.transcriptionService?.sendAudio(monoMixed)
      }
    }

    // Start (or gate) microphone + system capture according to the System Audio mode + meeting state.
    await reconcileCapture()

    log("Transcription: Audio capture armed (mic + system managed by meeting gate)")
  }

  /// Start microphone capture and wire its chunks/level to the active sink (the mixer in cloud mode,
  /// the mic Parakeet instance in local mode).
  /// - Returns: true if the mic is capturing after the call (already capturing or started OK);
  ///   false on a hard start failure (or if the session was torn down during the async start).
  @discardableResult
  func startMicCaptureIfNeeded() async -> Bool {
    guard let mic = audioCaptureService else { return false }
    guard !mic.capturing else { return true }
    do {
      let useLocalSTT = sttSession.useLocalSTT
      let localSink = localMicAudioSink
      let mixer = audioMixer
      try await mic.startCapture(
        onAudioChunk: { audioData in
          if useLocalSTT {
            localSink.append(audioData)
          } else {
            mixer?.setMicAudio(audioData)
          }
        },
        onAudioLevel: { level in
          // Use dedicated monitor to avoid triggering AppState re-renders
          Task { @MainActor in
            AudioLevelMonitor.shared.updateMicrophoneLevel(level)
          }
        }
      )
      // The HAL setup above is async and can be slow. If recording stopped — or the service was
      // swapped (silent-mic fallback) — while we were awaiting it, undo the just-started capture.
      guard isTranscribing, audioCaptureService === mic else {
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

  // MARK: - Capture Gating (meeting-aware)

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
          if useLocalSTT {
            localSink.append(audioData)
          } else {
            mixer?.setSystemAudio(audioData)
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
      guard isTranscribing,
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

  /// Bring microphone + system-audio capture into line with the current System Audio mode and
  /// meeting state. Idempotent and safe to call repeatedly — invoked on capture start, when the
  /// System Audio mode setting changes, and when the meeting detector flips.
  ///
  /// In "Only during meetings" mode the *entire* recording is gated: with no active call neither the
  /// microphone nor system audio is captured (the mic indicator stays dark). When a call is
  /// detected, both start; when it ends, both pause. In Always/Never the microphone runs for the
  /// whole session and system audio follows the mode. Overlapping async start/stop is serialized
  /// via `captureGateInFlight` / `captureReconcilePending`.
  func reconcileCapture() async {
    guard isTranscribing else {
      meetingDetector?.stop()
      meetingDetector = nil
      isAwaitingMeeting = false
      return
    }

    // Coalesce: if an async start/stop is in flight, request another pass when it finishes.
    if captureGateInFlight {
      captureReconcilePending = true
      return
    }

    let mode = effectiveSystemAudioMode

    // The meeting detector runs only in "Only during meetings" mode.
    if mode == .onlyDuringMeetings {
      if meetingDetector == nil {
        let detector = MeetingDetector(
          onInitialStateObserved: { [weak self] in
            Task { @MainActor in await self?.reconcileCapture() }
          },
          onChange: { [weak self] active in
            Task { @MainActor in await self?.reconcileCapture() }
            _ = active
          }
        )
        meetingDetector = detector
        detector.start()
      }
    } else {
      meetingDetector?.stop()
      meetingDetector = nil
    }

    let meetingStateReady = mode != .onlyDuringMeetings || meetingDetector?.hasObservedState == true
    let meetingActive = meetingDetector?.isMeetingActive ?? false
    // Only during meetings → capture (mic + system) only while in a call. Always/Never → the mic
    // runs continuously (system audio still respects the mode below).
    let shouldCapture = mode != .onlyDuringMeetings || meetingActive
    isAwaitingMeeting = mode == .onlyDuringMeetings && !meetingActive
    let hadActiveMeeting = meetingCaptureWasActive
    if mode == .onlyDuringMeetings, meetingActive {
      meetingCaptureWasActive = true
    } else if mode != .onlyDuringMeetings {
      meetingCaptureWasActive = false
    }

    guard meetingStateReady else {
      log("Transcription: waiting for meeting detector before changing capture state")
      return
    }

    captureGateInFlight = true

    // Microphone
    if let mic = audioCaptureService {
      if shouldCapture, !mic.capturing {
        let started = await startMicCaptureIfNeeded()
        if !started, isTranscribing {
          // Hard mic failure on a required start — stop the session rather than leave it silently
          // "recording" with no audio (the silent-mic watchdog handles zero-sample mics separately).
          log("Transcription: stopping — microphone could not start")
          captureGateInFlight = false
          stopTranscription()
          return
        }
      } else if !shouldCapture, mic.capturing {
        mic.stopCapture()
        AudioLevelMonitor.shared.updateMicrophoneLevel(0)
        log("Transcription: Microphone capture paused (no active call)")
      }
    }

    // System audio (macOS 14.4+). Captured when we should capture AND the mode isn't "never".
    if #available(macOS 14.4, *) {
      let systemShouldCapture = shouldCapture && mode != .never
      if systemShouldCapture, systemAudioCaptureService == nil {
        systemAudioCaptureService = SystemAudioCaptureService()
        log("Transcription: System audio capture service created on demand (mode=\(mode.rawValue))")
      }
      if let systemService = systemAudioCaptureService as? SystemAudioCaptureService {
        if systemShouldCapture, !systemService.capturing {
          await startSystemAudioCaptureIfNeeded()
        } else if !systemShouldCapture, systemService.capturing {
          systemService.stopCapture()
          AudioLevelMonitor.shared.updateSystemLevel(0)
          log("Transcription: System audio capture paused")
        }
      }
    }

    if !meetingEndFinalizationInProgress,
      MeetingConversationBoundaryPolicy.shouldFinishConversation(
        mode: mode,
        meetingStateReady: meetingStateReady,
        shouldCapture: shouldCapture,
        hadActiveMeeting: hadActiveMeeting
      )
    {
      meetingEndFinalizationInProgress = true
      meetingCaptureWasActive = false
      log("Transcription: Meeting ended — finishing conversation and waiting for the next meeting")
      Task { @MainActor in
        defer { self.meetingEndFinalizationInProgress = false }
        guard
          MeetingConversationBoundaryPolicy.shouldFinishConversation(
            mode: self.effectiveSystemAudioMode,
            meetingStateReady: self.meetingDetector?.hasObservedState == true,
            shouldCapture: self.meetingDetector?.isMeetingActive == true,
            hadActiveMeeting: true
          )
        else {
          log("Transcription: skipped meeting-ended finalization because meeting state changed")
          return
        }
        _ = await self.finishConversation(finalizationReason: .meetingEnded)
      }
    }

    captureGateInFlight = false
    if let recoveryReason = pendingCoreAudioCaptureRecoveryReason {
      pendingCoreAudioCaptureRecoveryReason = nil
      await rebuildCoreAudioCaptureStack(reason: recoveryReason)
      return
    }
    if captureReconcilePending {
      captureReconcilePending = false
      await reconcileCapture()
    }
  }

  /// Fall back from a silent Bluetooth mic to the built-in microphone.
  /// Triggered by `AudioCaptureService.onSilentMicDetected`.
  @MainActor
  func handleSilentMicFallback() {
    guard isTranscribing, !silentMicFallbackInProgress else { return }
    silentMicFallbackInProgress = true

    guard let builtInID = AudioCaptureService.findBuiltInMicDeviceID() else {
      log("Transcription: silent-mic detected but no built-in microphone available — leaving capture as-is")
      silentMicFallbackInProgress = false
      return
    }

    log("Transcription: silent-mic fallback — switching to built-in mic (deviceID=\(builtInID))")
    DesktopDiagnosticsManager.shared.recordFallback(
      area: "silent_mic",
      from: "bluetooth",
      to: "built_in",
      reason: "local_heal",
      outcome: .recovered,
      extra: ["user_visible": false])

    // Tear down the dead Bluetooth capture and spin a new one pinned to the built-in mic.
    // Silent healing — no user-facing UI, the recording just keeps working.
    audioCaptureService?.stopCapture()
    audioCaptureService = AudioCaptureService(overrideDeviceID: builtInID)
    recordingInputDeviceName =
      AudioCaptureService.getCurrentMicrophoneName() ?? "Built-in Microphone"

    Task { @MainActor in
      await self.startMicrophoneAudioCapture()
      self.silentMicFallbackInProgress = false
    }
  }

  @MainActor
  func rebuildCoreAudioCaptureStack(reason: String) async {
    guard isTranscribing, audioCaptureService != nil else { return }

    if captureGateInFlight {
      pendingCoreAudioCaptureRecoveryReason = reason
      return
    }

    log("Transcription: rebuilding CoreAudio capture stack — \(reason)")
    captureReconcilePending = false
    silentMicFallbackInProgress = false

    if #available(macOS 14.4, *) {
      if let systemService = systemAudioCaptureService as? SystemAudioCaptureService {
        systemService.stopCapture()
      }
      systemAudioCaptureService = nil
      AudioLevelMonitor.shared.updateSystemLevel(0)
    }

    audioCaptureService?.stopCapture()
    audioCaptureService = AudioCaptureService()
    AudioLevelMonitor.shared.updateMicrophoneLevel(0)

    if !sttSession.useLocalSTT {
      audioMixer?.stop()
      audioMixer = AudioMixer()
    }

    recordingInputDeviceName = AudioCaptureService.getCurrentMicrophoneName() ?? recordingInputDeviceName
    await startMicrophoneAudioCapture()
  }

  /// A fresh `AudioCaptureService` resets its own watchdog cap. Keep the terminal policy at
  /// the session owner so an unrecoverable USB/built-in route cannot loop forever while the
  /// UI continues to claim it is recording.
  @MainActor
  func handleSharedCaptureSilentMicDetection(reason: String) async {
    guard isTranscribing else { return }
    silentMicRecoveryAttempts += 1

    switch SharedCaptureSilentMicRecoveryPolicy.action(for: silentMicRecoveryAttempts) {
    case .rebuild:
      log("Transcription: silent microphone detected — rebuilding CoreAudio capture stack")
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "silent_mic",
        from: "stalled_route",
        to: "rebuilt_capture",
        reason: "local_heal",
        outcome: .degraded,
        extra: ["recovery_attempts": silentMicRecoveryAttempts, "user_visible": false])
      await rebuildCoreAudioCaptureStack(reason: reason)
    case .stopAndSurfaceError:
      log("Transcription: stopping after repeated silent microphone recovery failures")
      DesktopDiagnosticsManager.shared.recordTranscriptionSilentCaptureExhausted(
        recoveryAttempts: silentMicRecoveryAttempts)
      stopTranscription()
      showAlert(
        title: "Microphone Isn't Capturing Audio",
        message:
          "Omi stopped recording because your microphone returned no audio. Check your input device and try again.")
    }
  }

  /// Stop real-time transcription.
  /// Both local and managed STT feed the same locally authoritative finalization path.
  func stopTranscription() {
    guard transcriptionStopTask == nil else { return }
    recordingGeneration &+= 1
    transcriptionStartTask?.cancel()
    transcriptionStartTask = nil
    conversationLocationTask?.cancel()
    conversationLocationTask = nil
    let capturedSessionId = currentSessionId
    let capturedAuthorization = currentSessionAuthorization
    // On-device path stops capture, then awaits both Parakeet instances'
    // final tail flushes (delivered to the still-current session) BEFORE clearing state, so the
    // last words persist to the right conversation instead of racing the async drain.
    if sttSession.useLocalSTT {
      let mic = localMicService
      let sys = localSystemService
      localMicService = nil
      localSystemService = nil
      transcriptionStopTask = Task { @MainActor in
        defer { self.transcriptionStopTask = nil }
        self.stopAudioCapture()
        await mic?.finish()
        await sys?.finish()
        self.clearTranscriptionState(
          finalizationReason: .userStop, runFinalizer: false, finishSession: false)
        self.silentMicFallbackInProgress = false
        if let capturedSessionId, let capturedAuthorization {
          await self.finalizeSessionAndRefresh(
            sessionId: capturedSessionId,
            reason: .userStop,
            authorization: capturedAuthorization)
        }
      }
      return
    }

    stopAudioCapture()
    transcriptionStopTask = Task { @MainActor in
      defer { self.transcriptionStopTask = nil }
      await segmentDeliveryQueue.drain()
      clearTranscriptionState(
        finalizationReason: .userStop,
        runFinalizer: false,
        finishSession: false
      )
      silentMicFallbackInProgress = false
      if let sessionId = capturedSessionId, let capturedAuthorization {
        await finalizeSessionAndRefresh(
          sessionId: sessionId,
          reason: .userStop,
          authorization: capturedAuthorization)
      }
    }
  }

  /// Stop ambient capture and wait for the real transport teardown boundary.
  /// Local STT owns asynchronous final-tail flushes, so account authority must
  /// not change until the task created by `stopTranscription()` completes.
  func stopTranscriptionAndWait() async {
    stopTranscription()
    await transcriptionStopTask?.value
  }

  /// On-device Parakeet failed to load — fall back to cloud STT instead of silently recording a
  /// blank transcript. Cleanly stops the dead on-device session and restarts the SAME recording in
  /// cloud mode (no fragile mid-stream audio rerouting). Sticky for the app run so we don't retry a
  /// broken model on every recording.
  @MainActor
  func handleLocalSTTModelLoadFailure() {
    guard sttSession.canBeginLocalToCloudFallback(isTranscribing: isTranscribing) else { return }
    sttSession.beginLocalToCloudFallback()
    log("Transcription: Parakeet model load failed — falling back to cloud STT")
    AnalyticsManager.shared.recordingError(
      error: "parakeet_model_load_failed_fallback_cloud",
      reason: "local_stt_model_load_failed",
      source: "desktop",
      stage: "fallback"
    )
    stopTranscription()
    // Restart in cloud mode once stop has settled (isTranscribing flips false inside the stop's
    // async teardown). Bounded wait avoids racing the `!isTranscribing` guard in startTranscription.
    Task { @MainActor [weak self] in
      guard let self else { return }
      for _ in 0..<20 {
        if !self.isTranscribing { break }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      self.startTranscription()
      self.sttSession.completeFallback()
    }
  }

  /// Cloud STT websocket gave up (reconnects exhausted). On Apple Silicon, keep the recording
  /// alive by switching to on-device Parakeet (which works offline) instead of stopping. Skipped
  /// — and falls back to a normal stop — if we're only on cloud because Parakeet already failed,
  /// or we've already tried this once this session.
  @MainActor
  func handleCloudSTTReconnectFailure() {
    guard
      sttSession.canBeginCloudToLocalFallback(
        isTranscribing: isTranscribing,
        isAppleSilicon: Self.isAppleSilicon
      )
    else {
      // Could not fail open (no local STT): record the exhausted cloud→stopped rotation.
      DesktopDiagnosticsManager.shared.recordFallback(
        area: "cloud_stt",
        from: "cloud",
        to: "stopped",
        reason: "cloud_stt_reconnect_failed",
        outcome: .exhausted,
        extra: ["source": "desktop"])
      stopTranscription()
      return
    }
    sttSession.beginCloudToLocalFallback()
    log("Transcription: cloud STT unreachable (reconnects exhausted) — falling back to on-device Parakeet")
    // Fail-open cloud → on-device Parakeet switch: shared fallback telemetry (AGENTS.md).
    DesktopDiagnosticsManager.shared.recordFallback(
      area: "cloud_stt",
      from: "cloud",
      to: "local",
      reason: "cloud_stt_reconnect_failed",
      outcome: .recovered,
      extra: ["source": "desktop"])
    AnalyticsManager.shared.recordingError(
      error: "cloud_stt_reconnect_failed_fallback_local",
      reason: "cloud_stt_reconnect_failed",
      source: "desktop",
      stage: "fallback"
    )
    stopTranscription()
    Task { @MainActor [weak self] in
      guard let self else { return }
      for _ in 0..<20 {
        if !self.isTranscribing { break }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      self.startTranscription()
      self.sttSession.completeFallback()
    }
  }

  /// Finish the current conversation and keep recording for a new one.
  /// Rotates the transient STT producer after closing the current local conversation.
  func finishConversation(
    finalizationReason: TranscriptionFinalizationReason = .finishAndContinue
  ) async -> FinishConversationResult {
    log("Transcription: Finishing conversation — reason=\(finalizationReason.rawValue)")

    let sessionToFinalize = currentSessionId
    let authorizationToFinalize = currentSessionAuthorization

    // Local mode: flush both Parakeet instances' final tails to the CURRENT session BEFORE we
    // rotate currentSessionId, so the last sub-window words attach to THIS conversation rather
    // than racing into the next one. `finish()` delivers its segments on the main actor and
    // returns only once they're persisted. Fresh instances are armed in the reconnect block below.
    if sttSession.useLocalSTT {
      localMicAudioSink.beginHandoff()
      localSystemAudioSink.beginHandoff()
      await localMicService?.finish()
      await localSystemService?.finish()
    } else {
      // Close the cloud stream before marking the old local session finished, so no late
      // WebSocket segments can be persisted after the finalization snapshot starts.
      transcriptionService?.stop()
      transcriptionService = nil
      await segmentDeliveryQueue.drain()
    }

    let retainedContentWasFlushed = totalSegmentCount > 0 || !speakerSegments.isEmpty

    // Mark the authoritative local session as finished before reconnecting.
    let finishedConversationId = await finishSessionAndRefreshImmediately(
      sessionId: sessionToFinalize,
      reason: finalizationReason,
      authorization: authorizationToFinalize)

    // Clear currentSessionId BEFORE reconnecting — any segments arriving on the new WebSocket
    // must not be persisted against the finished session. They'll be buffered in memory until
    // the new session ID is set in the Task below.
    currentSessionId = nil
    currentConversationId = nil
    currentSessionAuthorization = nil

    // Clear segments for the next conversation but keep recording active
    speakerSegments = []
    totalSegmentCount = 0
    totalWordCount = 0
    liveSpeakerNames = [:]
    LiveTranscriptMonitor.shared.clear()
    LiveNotesMonitor.shared.endSession()
    LiveNotesMonitor.shared.clear()

    // Reset the recording start time for the next local conversation.
    recordingStartTime = Date()
    RecordingTimer.shared.restart()

    if let finishedConversationId {
      Task {
        await self.processFinishedConversationAndRefresh(
          conversationId: finishedConversationId)
      }
    }

    let nextAdmissionGeneration = recordingGeneration
    let lang = AssistantSettings.shared.effectiveTranscriptionLanguage
    let producerSessionId: Int64
    do {
      let admission = try await beginLocalConversation(
        language: lang, inputDeviceName: recordingInputDeviceName)
      let handle = admission.handle
      guard recordingGeneration == nextAdmissionGeneration else {
        try? await TranscriptionStorage.shared.deleteConversationCascade(
          id: handle.conversationId, authorization: admission.authorization)
        return .discarded
      }
      currentSessionId = handle.sessionId
      currentConversationId = handle.conversationId
      currentSessionAuthorization = admission.authorization
      producerSessionId = handle.sessionId
      LiveNotesMonitor.shared.startSession(sessionId: handle.sessionId)
      startConversationLocationCaptureIfEnabled(
        conversationId: handle.conversationId,
        admissionGeneration: nextAdmissionGeneration)
      log("Transcription: Created next DB session \(handle.sessionId) before producer rotation")
    } catch {
      logError("Transcription: Failed to create DB session for next conversation", error: error)
      return .error(error.localizedDescription)
    }

    // Restart the 4-hour max recording timer
    maxRecordingTimer?.invalidate()
    maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self = self, self.isTranscribing else { return }
        log("Transcription: 4-hour limit reached — stopping and restarting")
        let sessionId = self.currentSessionId
        let authorization = self.currentSessionAuthorization
        let wasLocalSTT = self.sttSession.useLocalSTT
        let mic = self.localMicService
        let sys = self.localSystemService
        if wasLocalSTT {
          self.localMicService = nil
          self.localSystemService = nil
        }
        self.stopAudioCapture()
        if wasLocalSTT {
          await mic?.finish()
          await sys?.finish()
        } else {
          await self.segmentDeliveryQueue.drain()
        }
        let finishedConversationId = await self.finishSessionAndRefreshImmediately(
          sessionId: sessionId,
          reason: .maxDurationRotation,
          authorization: authorization)
        self.clearTranscriptionState(
          finalizationReason: .maxDurationRotation,
          runFinalizer: false,
          finishSession: false
        )
        if let finishedConversationId {
          Task {
            await self.processFinishedConversationAndRefresh(
              conversationId: finishedConversationId)
          }
        }
        self.startTranscription()
      }
    }

    // Reconnect transcription service for the next conversation
    do {
      let effectiveLanguage = AssistantSettings.shared.effectiveTranscriptionLanguage
      if sttSession.useLocalSTT {
        // On-device mode: re-arm fresh local Parakeet instances (mic + system) for the next
        // conversation — do NOT reconnect the cloud WebSocket. Stopping the old ones flushes
        // their final tails; the source-routed capture callbacks feed the new instances.
        let onLocalSegments: LocalTranscriptionService.SegmentsHandler = { [weak self] segments in
          await self?.handleBackendSegments(segments, expectedSessionId: producerSessionId)
        }
        // Mirror startTranscription: wire onModelLoadFailed so a Parakeet model
        // load failure on the re-armed instances falls back to cloud instead of
        // recording into a void (a silent blank transcript). Without this, every
        // conversation after the first in a session loses that protection.
        let onModelLoadFailed: @MainActor () -> Void = { [weak self] in
          guard self?.currentSessionId == producerSessionId else { return }
          self?.handleLocalSTTModelLoadFailure()
        }
        let mic = LocalTranscriptionService(language: effectiveLanguage, isUser: true)
        mic.start(onSegments: onLocalSegments, onModelLoadFailed: onModelLoadFailed)
        localMicService = mic
        localMicAudioSink.completeHandoff(to: mic)
        let system = LocalTranscriptionService(language: effectiveLanguage, isUser: false)
        system.start(onSegments: onLocalSegments, onModelLoadFailed: onModelLoadFailed)
        localSystemService = system
        localSystemAudioSink.completeHandoff(to: system)
        log("Transcription: Re-armed on-device Parakeet (mic + system) for next conversation")
      } else {
        let settings = AssistantSettings.shared
        transcriptionService = try TranscriptionService(
          language: effectiveLanguage,
          translationTarget: settings.transcriptionAutoDetect ? settings.transcriptionLanguage : nil,
          vocabulary: settings.effectiveVocabulary
        )
        transcriptionService?.start(
          onSegments: { [weak self] segments in
            self?.segmentDeliveryQueue.submit { [weak self] in
              await self?.handleBackendSegments(segments, expectedSessionId: producerSessionId)
            }
          },
          onEvent: { [weak self] event in
            self?.segmentDeliveryQueue.submit { [weak self] in
              await self?.handleListenEvent(event, expectedSessionId: producerSessionId)
            }
          },
          onError: { [weak self] error in
            Task { @MainActor in
              guard let self, self.currentSessionId == producerSessionId else { return }
              logError("Transcription error (reconnect)", error: error)
              // Mirror startTranscription: on cloud reconnect exhaustion, fail
              // over to on-device Parakeet (Apple Silicon) instead of hard-
              // stopping capture mid-meeting. Plain stopTranscription() here
              // dropped the cloud->local resilience for every conversation after
              // the first.
              self.handleCloudSTTReconnectFailure()
            }
          },
          onConnected: {
            log("Transcription: Reconnected to Python backend for next conversation")
          },
          onDisconnected: {
            log("Transcription: Disconnected from Python backend")
          }
        )
      }
    } catch {
      logError("Transcription: Failed to reconnect for next conversation", error: error)
      return .error(error.localizedDescription)
    }

    // Refresh the conversations list to show the new conversation
    await loadConversations()

    log("Transcription: Ready for next conversation")
    return retainedContentWasFlushed ? .saved : .discarded
  }

  /// Stop audio capture services (but keep transcript data for saving)
  func stopAudioCapture() {
    // Cancel timers
    maxRecordingTimer?.invalidate()
    maxRecordingTimer = nil
    RecordingTimer.shared.stop()

    // Reset audio levels
    AudioLevelMonitor.shared.reset()

    // Stop the meeting detector (only active in "Only during meetings" mode)
    meetingDetector?.stop()
    meetingDetector = nil
    captureGateInFlight = false
    captureReconcilePending = false
    pendingCoreAudioCaptureRecoveryReason = nil
    silentMicRecoveryAttempts = 0
    isAwaitingMeeting = false
    meetingEndFinalizationInProgress = false

    // Stop system audio capture first (if available)
    if #available(macOS 14.4, *) {
      if let systemService = systemAudioCaptureService as? SystemAudioCaptureService {
        systemService.stopCapture()
      }
    }
    systemAudioCaptureService = nil

    // Stop microphone capture
    audioCaptureService?.stopCapture()
    audioCaptureService = nil

    // Stop audio mixer
    audioMixer?.stop()
    audioMixer = nil

    // Clear VAD gate
    vadGateService = nil

    // Stop transcription service
    transcriptionService?.stop()
    transcriptionService = nil

    // Stop on-device Parakeet services (if active) — both flush their final tails.
    localMicService?.stop()
    localMicService = nil
    localSystemService?.stop()
    localSystemService = nil
    localMicAudioSink.clear()
    localSystemAudioSink.clear()
    sttSession.endRecording()

    isTranscribing = false
  }

  /// Clear transcription state after saving
  func clearTranscriptionState(
    finalizationReason: TranscriptionFinalizationReason = .userStop,
    runFinalizer: Bool = true,
    finishSession: Bool = true
  ) {
    log(
      "Transcription: Final segments count: \(totalSegmentCount) (in-memory: \(speakerSegments.count)), words: \(totalWordCount)"
    )

    // End live notes session
    LiveNotesMonitor.shared.endSession()

    // A terminal STT error belongs to the session that just ended. Leaving it
    // set after an explicit stop/reset makes the idle home header look
    // permanently blocked even though no audio is being handed to STT.
    transcriptionServiceError = nil

    // Mark the local conversation finished and admit durable local compute work.
    if finishSession, let sessionId = currentSessionId,
      let authorization = currentSessionAuthorization
    {
      Task {
        do {
          let conversation = try await TranscriptionStorage.shared.finishConversation(
            sessionId: sessionId,
            reason: finalizationReason,
            authorization: authorization)
          log("Transcription: Finished DB session \(sessionId)")
          await self.loadConversations()
          if runFinalizer {
            await ConversationFinalizationService.shared.processFinishedConversation(
              conversationId: conversation.conversationId)
            await self.loadConversations()
          }
        } catch {
          logError("Transcription: Failed to finish DB session \(sessionId)", error: error)
        }
      }
    }

    // Clear segments after finalization
    speakerSegments = []
    liveSpeakerNames = [:]
    LiveTranscriptMonitor.shared.clear()
    LiveNotesMonitor.shared.clear()
    recordingStartTime = nil
    currentSessionId = nil
    currentConversationId = nil
    currentSessionAuthorization = nil
    conversationLocationTask?.cancel()
    conversationLocationTask = nil
    meetingEndFinalizationInProgress = false

    // Track transcription stopped
    AnalyticsManager.shared.transcriptionStopped(wordCount: totalWordCount)
    totalSegmentCount = 0
    totalWordCount = 0
    currentTranscript = ""

    log("Transcription: Stopped")
  }

  /// Aggressively trim transcript state to free memory (called by ResourceMonitor during critical memory pressure).
  /// Segments are already persisted in SQLite, so trimming in-memory state is safe.
  func trimTranscriptStateForMemoryPressure() {
    let beforeCount = speakerSegments.count
    if speakerSegments.count > 50 {
      speakerSegments = Array(speakerSegments.suffix(50))
    }
    currentTranscript = ""
    LiveTranscriptMonitor.shared.updateSegments(speakerSegments)
    log(
      "ResourceMonitor: Trimmed transcript state \(beforeCount) -> \(speakerSegments.count) segments"
    )
  }

  // MARK: - Automation capture test seam (non-prod hermetic E2E)

  /// Start a headless capture session without mic/audio — T2 hermetic only.
  func automationStartCaptureTestSession() async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "capture test session disabled on production bundles"]
    }
    if isTranscribing {
      if automationCaptureTestSessionActive {
        return [
          "already_recording": "true",
          "session_id": currentSessionId.map { "\($0)" } ?? "",
          "segment_count": "\(totalSegmentCount)",
        ]
      }
      return ["error": "real capture session already active"]
    }
    do {
      let admission = try await beginLocalConversation(
        language: AssistantSettings.shared.effectiveTranscriptionLanguage,
        inputDeviceName: "harness-capture")
      let handle = admission.handle
      let sessionId = handle.sessionId
      currentSessionId = sessionId
      currentConversationId = handle.conversationId
      currentSessionAuthorization = admission.authorization
      recordingStartTime = Date()
      isTranscribing = true
      sttSession.activeMode = .local
      speakerSegments = []
      totalSegmentCount = 0
      totalWordCount = 0
      currentTranscript = ""
      LiveNotesMonitor.shared.startSession(sessionId: sessionId)
      automationCaptureTestSessionActive = true
      return [
        "started": "true",
        "session_id": "\(sessionId)",
        "is_transcribing": "true",
      ]
    } catch {
      return ["error": "failed to start capture session: \(error.localizedDescription)"]
    }
  }

  func automationInjectCaptureTestTranscript(text: String) async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "capture test transcript disabled on production bundles"]
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ["error": "missing transcript text"] }
    guard automationCaptureTestSessionActive else {
      if isTranscribing {
        return ["error": "cannot inject into non-automation capture session"]
      }
      return ["error": "no active capture session"]
    }
    guard isTranscribing else { return ["error": "no active capture session"] }
    let start = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
    let segment = TranscriptionService.BackendSegment(
      segmentId: UUID().uuidString.lowercased(),
      speakerId: 0,
      text: trimmed,
      isUser: true,
      start: max(0, start),
      end: max(0.1, start + 0.5)
    )
    await handleBackendSegments([segment])
    return [
      "injected": trimmed,
      "session_id": currentSessionId.map { "\($0)" } ?? "",
      "segment_count": "\(totalSegmentCount)",
      "conversation_count": "\(totalConversationsCount ?? conversations.count)",
    ]
  }

  /// Hermetic multi-speaker inject: accepts a JSON array of segment objects
  /// `[{"text":"...","speaker":"SPEAKER_00","speaker_id":0,"is_user":true}, ...]`.
  func automationInjectCaptureTestTranscriptMulti(segmentsJSON: String) async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "capture test transcript disabled on production bundles"]
    }
    let trimmed = segmentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ["error": "missing segments JSON"] }
    guard automationCaptureTestSessionActive else {
      if isTranscribing {
        return ["error": "cannot inject into non-automation capture session"]
      }
      return ["error": "no active capture session"]
    }
    guard isTranscribing else { return ["error": "no active capture session"] }
    guard let data = trimmed.data(using: .utf8),
      let rawSegments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
      !rawSegments.isEmpty
    else {
      return ["error": "segments must be a non-empty JSON array"]
    }

    let start = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
    var backendSegments: [TranscriptionService.BackendSegment] = []
    var offset = max(0, start)
    var speakerLabels: [String] = []
    for (index, raw) in rawSegments.enumerated() {
      guard let text = raw["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return ["error": "segment \(index) missing text"]
      }
      let speaker = (raw["speaker"] as? String) ?? "SPEAKER_00"
      var speakerId = raw["speaker_id"] as? Int ?? 0
      // Derive speaker_id from the label (e.g. SPEAKER_02 → 2) when omitted,
      // preventing silent collapse to SPEAKER_00 for multi-speaker fixtures.
      if raw["speaker_id"] == nil, let labelNum = speaker.split(separator: "_").last,
        let parsed = Int(labelNum)
      {
        speakerId = parsed
      }
      let isUser = raw["is_user"] as? Bool ?? (speakerId == 0)
      let segmentStart = raw["start"] as? Double ?? offset
      let segmentEnd = raw["end"] as? Double ?? (segmentStart + 0.5)
      backendSegments.append(
        TranscriptionService.BackendSegment(
          segmentId: UUID().uuidString.lowercased(),
          speakerId: speakerId,
          text: text,
          isUser: isUser,
          start: segmentStart,
          end: max(segmentEnd, segmentStart + 0.1)
        )
      )
      speakerLabels.append(speaker)
      offset = max(segmentEnd, segmentStart + 0.5) + 0.1
    }

    await handleBackendSegments(backendSegments)
    let uniqueSpeakers = Set(speakerLabels).sorted().joined(separator: ",")
    return [
      "injected_count": "\(backendSegments.count)",
      "session_id": currentSessionId.map { "\($0)" } ?? "",
      "segment_count": "\(totalSegmentCount)",
      "unique_speakers": uniqueSpeakers,
      "conversation_count": "\(totalConversationsCount ?? conversations.count)",
    ]
  }

  /// Hermetic capture teardown: mirrors the session-finalization portion of
  /// `stopTranscription()` (finish session, finalize conversation, clear live
  /// transcript state, reload conversations) without stopping the audio engine
  /// or cloud STT WebSocket. Keep this in sync when `stopTranscription()` changes.
  func automationStopCaptureTestSession() async -> [String: String] {
    guard AppBuild.isNonProduction else {
      return ["error": "capture test session disabled on production bundles"]
    }
    guard automationCaptureTestSessionActive else {
      if isTranscribing {
        return ["error": "cannot stop non-automation capture session"]
      }
      return [
        "already_stopped": "true",
        "conversation_count": "\(totalConversationsCount ?? conversations.count)",
      ]
    }
    guard isTranscribing else {
      automationCaptureTestSessionActive = false
      return [
        "already_stopped": "true",
        "conversation_count": "\(totalConversationsCount ?? conversations.count)",
      ]
    }
    let beforeCount = totalConversationsCount ?? conversations.count
    let sessionId = currentSessionId
    let authorization = currentSessionAuthorization
    let segmentCount = totalSegmentCount

    isTranscribing = false
    LiveNotesMonitor.shared.endSession()

    var finalizeError: String?
    if let sessionId, let authorization {
      await finalizeSessionAndRefresh(
        sessionId: sessionId,
        reason: .userStop,
        authorization: authorization)
    } else if sessionId != nil {
      finalizeError = "failed to finalize capture session: owner authorization unavailable"
    }

    // Reset cleanup state regardless of finalize outcome so a failed finalize
    // can't leave `automationCaptureTestSessionActive` stuck true (which made a
    // retried stop silently report "already_stopped" without ever finalizing).
    speakerSegments = []
    liveSpeakerNames = [:]
    LiveTranscriptMonitor.shared.clear()
    LiveNotesMonitor.shared.clear()
    recordingStartTime = nil
    currentSessionId = nil
    currentConversationId = nil
    currentSessionAuthorization = nil
    sttSession.endRecording()
    totalSegmentCount = 0
    totalWordCount = 0
    currentTranscript = ""
    automationCaptureTestSessionActive = false

    if let finalizeError {
      return ["error": finalizeError]
    }

    await loadConversations()
    let afterCount = totalConversationsCount ?? conversations.count
    let latestConversationId = conversations.first?.id ?? ""
    return [
      "stopped": "true",
      "conversation_count_before": "\(beforeCount)",
      "conversation_count_after": "\(afterCount)",
      "conversation_count_increased": afterCount > beforeCount ? "true" : "false",
      "segment_count": "\(segmentCount)",
      "latest_conversation_id": latestConversationId,
    ]
  }

  private func beginLocalConversation(
    language: String,
    inputDeviceName: String?
  ) async throws -> (handle: ConversationCaptureHandle, authorization: LocalMutationAuthorization) {
    let settings = AssistantSettings.shared
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    let authorization = LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    let handle = try await TranscriptionStorage.shared.beginConversation(
      configuration: ConversationCaptureConfiguration(
        language: language,
        autoDetectLanguage: settings.transcriptionAutoDetect,
        vocabulary: settings.transcriptionVocabulary,
        timezone: TimeZone.current.identifier,
        inputDeviceName: inputDeviceName,
        location: nil),
      authorization: authorization)
    return (handle, authorization)
  }

  private func finalizeSessionAndRefresh(
    sessionId: Int64,
    reason: TranscriptionFinalizationReason,
    authorization: LocalMutationAuthorization
  ) async {
    do {
      try await ConversationFinalizationProjectionFlow.run(
        finish: {
          let conversation = try await TranscriptionStorage.shared.finishConversation(
            sessionId: sessionId, reason: reason, authorization: authorization)
          return conversation.conversationId
        },
        refresh: { [weak self] in await self?.loadConversations() },
        postProcess: { conversationId in
          await ConversationFinalizationService.shared.processFinishedConversation(
            conversationId: conversationId)
        })
    } catch {
      logError("Transcription: Failed to finish DB session \(sessionId)", error: error)
    }
  }

  private func finishSessionAndRefreshImmediately(
    sessionId: Int64?,
    reason: TranscriptionFinalizationReason,
    authorization: LocalMutationAuthorization?
  ) async -> String? {
    guard let sessionId, let authorization else { return nil }
    do {
      let conversation = try await TranscriptionStorage.shared.finishConversation(
        sessionId: sessionId,
        reason: reason,
        authorization: authorization)
      await loadConversations()
      return conversation.conversationId
    } catch {
      logError("Transcription: Failed to finish DB session \(sessionId)", error: error)
      return nil
    }
  }

  private func processFinishedConversationAndRefresh(conversationId: String) async {
    await ConversationFinalizationService.shared.processFinishedConversation(
      conversationId: conversationId)
    await loadConversations()
  }

  private func startConversationLocationCaptureIfEnabled(
    conversationId: String,
    admissionGeneration: UInt64
  ) {
    conversationLocationTask?.cancel()
    guard AssistantSettings.shared.conversationLocationEnabled else { return }
    let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    conversationLocationTask = Task { @MainActor [weak self] in
      let provider = CoreLocationConversationLocationProvider()
      let location = await ConversationLocationSnapshotter.capture(using: provider)
      guard
        let self,
        !Task.isCancelled,
        self.recordingGeneration == admissionGeneration,
        self.currentConversationId == conversationId,
        let location,
        let authorizationSnapshot
      else { return }
      let authorization = LocalMutationAuthorization {
        RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
      }
      do {
        _ = try await TranscriptionStorage.shared.setConversationLocation(
          id: conversationId,
          location: location,
          authorization: authorization)
      } catch LocalMutationAuthorizationError.revoked {
        // The previous owner's delayed one-shot result is intentionally dropped.
      } catch {
        logError("Transcription: Failed to persist local location snapshot", error: error)
      }
    }
  }

  // MARK: - Conversations
}
