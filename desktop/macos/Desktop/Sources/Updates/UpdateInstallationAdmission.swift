import Foundation

struct UpdateInstallationActivitySnapshot: Equatable {
  var ambientTranscriptionActive = false
  var voiceCaptureActive = false
  var voiceProviderActive = false
  var voicePlaybackActive = false
  var pendingVoiceToolCount = 0
  var realtimeTokenMintActive = false
  var voiceTurnActive = false
  var chatSendActive = false
  var chatStreamingActive = false

  static let idle = UpdateInstallationActivitySnapshot()

  @MainActor
  static func current() -> UpdateInstallationActivitySnapshot {
    let appState = AppState.current
    let realtime = RealtimeHubController.shared.lifecycleSnapshot
    let chat = ChatProvider.mainInstance

    return UpdateInstallationActivitySnapshot(
      ambientTranscriptionActive: appState?.isTranscribing == true
        || appState?.transcriptionStartTask != nil
        || appState?.transcriptionStopTask != nil
        || appState?.isSavingConversation == true,
      voiceCaptureActive: realtime.capturingInput,
      voiceProviderActive: realtime.providerActive,
      voicePlaybackActive: realtime.playbackActive
        || FloatingBarVoicePlaybackService.shared.isSpeaking,
      pendingVoiceToolCount: realtime.pendingToolCount,
      realtimeTokenMintActive: realtime.minting,
      voiceTurnActive: realtime.coordinatorTurnActive,
      chatSendActive: chat?.isSending == true,
      chatStreamingActive: chat?.messages.contains(where: { $0.isStreaming }) == true
    )
  }
}

enum UpdateInstallationAdmission {
  static func canInstall(snapshot: UpdateInstallationActivitySnapshot) -> Bool {
    !snapshot.ambientTranscriptionActive
      && !snapshot.voiceCaptureActive
      && !snapshot.voiceProviderActive
      && !snapshot.voicePlaybackActive
      && snapshot.pendingVoiceToolCount == 0
      && !snapshot.realtimeTokenMintActive
      && !snapshot.voiceTurnActive
      && !snapshot.chatSendActive
      && !snapshot.chatStreamingActive
  }
}

/// Owns Sparkle's immediate-install block from download completion until every
/// retained local activity owner reports idle. There is deliberately no
/// timeout: an update stays install-on-quit rather than interrupting live work.
@MainActor
final class DeferredUpdateInstall {
  private let version: String
  private let retryInterval: TimeInterval
  private let scheduler: DelayedActionScheduling
  private let activitySnapshotProvider: @MainActor () -> UpdateInstallationActivitySnapshot
  private let install: @MainActor () -> Void
  private var pendingCancellation: DelayedActionCancellation?
  private var generation: UInt64 = 0
  private var didInstall = false
  private var didLogDeferral = false

  init(
    version: String,
    retryInterval: TimeInterval = 5,
    scheduler: DelayedActionScheduling? = nil,
    activitySnapshotProvider: @escaping @MainActor () -> UpdateInstallationActivitySnapshot,
    install: @escaping @MainActor () -> Void
  ) {
    self.version = version
    self.retryInterval = retryInterval
    self.scheduler = scheduler ?? TaskDelayedActionScheduler()
    self.activitySnapshotProvider = activitySnapshotProvider
    self.install = install
  }

  func start() {
    guard !didInstall else { return }
    generation &+= 1
    pendingCancellation?.cancel()
    pendingCancellation = nil
    evaluate(expectedGeneration: generation)
  }

  func cancel() {
    generation &+= 1
    pendingCancellation?.cancel()
    pendingCancellation = nil
  }

  private func evaluate(expectedGeneration: UInt64) {
    guard expectedGeneration == generation, !didInstall else { return }

    let snapshot = activitySnapshotProvider()
    guard UpdateInstallationAdmission.canInstall(snapshot: snapshot) else {
      if !didLogDeferral {
        didLogDeferral = true
        logSync(
          "Sparkle: Deferred install for v\(version) is waiting for retained user activity to become idle"
        )
      }
      pendingCancellation = scheduler.schedule(after: retryInterval) { [weak self] in
        guard let self, self.generation == expectedGeneration else { return }
        self.pendingCancellation = nil
        self.evaluate(expectedGeneration: expectedGeneration)
      }
      return
    }

    didInstall = true
    pendingCancellation = nil
    logSync("Sparkle: Retained user activity is idle, installing deferred update v\(version)")
    install()
  }
}
