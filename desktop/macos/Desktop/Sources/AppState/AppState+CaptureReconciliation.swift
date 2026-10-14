import Foundation

@MainActor
extension AppState {
  /// Reconcile independent ambient sources while Listening is armed. A failed
  /// input never stops another healthy input. Async starts remain session-fenced.
  func reconcileCapture() async {
    guard isTranscribing else { return }
    if captureGateInFlight {
      captureReconcilePending = true
      return
    }

    let generation = recordingGeneration
    captureGateInFlight = true
    let microphoneRequested = AssistantSettings.shared.ambientMicrophoneEnabled
    let microphoneAllowed = microphoneRequested && hasMicrophonePermission
    if let mic = audioCaptureService {
      if microphoneAllowed, !mic.capturing {
        await startMicCaptureIfNeeded()
        guard isTranscribing, recordingGeneration == generation else { return }
      } else if !microphoneAllowed, mic.capturing {
        mic.stopCapture()
        AudioLevelMonitor.shared.updateMicrophoneLevel(0)
      }
    }

    if #available(macOS 14.4, *) {
      let systemRequested = ambientSystemAudioRequested
      if systemRequested, systemAudioCaptureService == nil {
        systemAudioCaptureService = SystemAudioCaptureService()
      }
      if let system = systemAudioCaptureService as? SystemAudioCaptureService {
        if systemRequested, !system.capturing {
          await startSystemAudioCaptureIfNeeded()
          guard isTranscribing, recordingGeneration == generation else { return }
        } else if !systemRequested, system.capturing {
          system.stopCapture()
          AudioLevelMonitor.shared.updateSystemLevel(0)
        }
      }
    }

    captureGateInFlight = false
    if captureReconcilePending {
      captureReconcilePending = false
      await reconcileCapture()
      return
    }
    // With both switches off Listening remains armed, ready for an explicit
    // input enablement. Requested inputs that both fail must not claim capture.
    let anyRequested = AssistantSettings.shared.ambientMicrophoneEnabled || ambientSystemAudioRequested
    let systemCapturing: Bool
    if #available(macOS 14.4, *) {
      systemCapturing = (systemAudioCaptureService as? SystemAudioCaptureService)?.capturing == true
    } else {
      systemCapturing = false
    }
    if anyRequested, audioCaptureService?.capturing != true, !systemCapturing {
      stopTranscription()
      return
    }
    if let recoveryReason = pendingCoreAudioCaptureRecoveryReason {
      pendingCoreAudioCaptureRecoveryReason = nil
      await rebuildCoreAudioCaptureStack(reason: recoveryReason)
    }
  }
}
