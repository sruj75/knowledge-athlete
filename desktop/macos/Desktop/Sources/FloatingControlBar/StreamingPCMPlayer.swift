@preconcurrency import AVFoundation
import Foundation

/// Tracks buffers that AVAudioPlayerNode owns but has not reported as played yet.
///
/// `AVAudioPlayerNode.stop()` discards every scheduled buffer. Route/sample-rate
/// changes force us to stop and rebuild the node graph, so the app must own a
/// mirror of the scheduled tail and replay it after recovery. Keep this small
/// state machine separate from AVFoundation calls so route-change behavior is
/// testable without real audio hardware.
final class StreamingPCMPlaybackQueue<Buffer: AnyObject> {
  private(set) var scheduledBuffers: [Buffer] = []
  private(set) var generation = 0

  var isEmpty: Bool { scheduledBuffers.isEmpty }

  @discardableResult
  func appendScheduled(_ buffer: Buffer) -> Int {
    scheduledBuffers.append(buffer)
    return generation
  }

  @discardableResult
  func markPlayed(_ buffer: Buffer, generation completionGeneration: Int) -> Bool {
    guard completionGeneration == generation else { return false }
    if let index = scheduledBuffers.firstIndex(where: { $0 === buffer }) {
      scheduledBuffers.remove(at: index)
      return true
    }
    return false
  }

  func buffersToReplayAfterConfigurationChange() -> [Buffer] {
    let buffers = scheduledBuffers
    generation += 1
    scheduledBuffers.removeAll()
    return buffers
  }

  func clearForExplicitStop() {
    generation += 1
    scheduledBuffers.removeAll()
  }
}

/// Plays streamed mono PCM16 audio incrementally (Gemini Live
/// output is 24 kHz). Feed chunks with `enqueue(_:)`; they play back-to-back in
/// arrival order. Used by `RealtimeHubController` to play the realtime model's
/// spoken response as it streams in.
///
/// Retained from Omi's proven streaming voice playback path.
@MainActor
final class StreamingPCMPlayer {
  typealias OutputFactory =
    @Sendable (
      @escaping @Sendable () -> Void, @escaping @Sendable (Float) -> Void
    ) -> any StreamingPCMAudioOutput

  private let authority = PCMPlaybackAuthority()
  private let levels = AudioLevelDelivery()
  private let worker: PCMPlaybackWorker
  private var meterCapture: AudioLevelDelivery.Capture
  private var pendingEnqueues = 0
  private var enqueueWaiters: [@MainActor @Sendable () -> Void] = []
  var hasPendingEnqueues: Bool { pendingEnqueues > 0 }
  private(set) var playbackEpoch = 0
  var onPlaybackScheduled: (@MainActor @Sendable (Int) -> Void)?
  var onPlaybackIdle: (@MainActor @Sendable (Int) -> Void)?
  var onPlaybackFailed: (@MainActor @Sendable (Int) -> Void)?

  init(sampleRate: Double = 24000, makeOutput: OutputFactory? = nil) {
    meterCapture = levels.invalidate()
    worker = PCMPlaybackWorker(
      authority: authority, levels: levels,
      makeOutput: makeOutput ?? { changed, level in
        AVFoundationStreamingPCMOutput(
          sampleRate: sampleRate, configurationChanged: changed, level: level)
      })
    worker.setEventHandler { [weak self] token, event in
      guard let self, self.authority.current == token else { return }
      switch event {
      case .scheduled(let epoch):
        self.playbackEpoch = epoch
        self.onPlaybackScheduled?(epoch)
      case .idle(let epoch):
        guard !self.hasPendingEnqueues, self.playbackEpoch == epoch else { return }
        self.onPlaybackIdle?(epoch)
      case .failed(let epoch): self.onPlaybackFailed?(epoch)
      }
    }
  }

  deinit {
    authority.invalidate()
    levels.invalidate()
    worker.stop()
  }

  /// Completion means the audio SDK accepted this chunk, not just that it was
  /// placed on a work queue. Stop invalidates this and all older callbacks.
  func enqueue(_ data: Data, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
    let token = authority.current
    pendingEnqueues += 1
    worker.enqueue(data, token: token, meterCapture: meterCapture) { [weak self] accepted in
      guard let self, self.authority.current == token else { return }
      self.pendingEnqueues -= 1
      completion(accepted)
      if self.pendingEnqueues == 0 {
        let waiters = self.enqueueWaiters
        self.enqueueWaiters.removeAll()
        for waiter in waiters where self.authority.current == token { waiter() }
      }
    }
  }

  /// Provider text/end events must not overtake physical enqueue acceptance.
  /// Stop discards the old turn's waiters along with its audio callbacks.
  func afterPendingEnqueues(_ action: @escaping @MainActor @Sendable () -> Void) {
    if hasPendingEnqueues { enqueueWaiters.append(action) } else { action() }
  }

  func stop(completion: @escaping @MainActor @Sendable () -> Void = {}) {
    playbackEpoch = authority.invalidate()
    meterCapture = levels.invalidate()
    pendingEnqueues = 0
    enqueueWaiters.removeAll()
    AudioLevelMonitor.shared.updateVoicePlaybackLevel(0)
    worker.stop(completion: completion)
  }

  /// Root-mean-square level of a float PCM buffer across all channels, 0…1.
  nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let channelCount = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    var sum: Float = 0
    for channel in 0..<channelCount {
      let samples = channels[channel]
      for frame in 0..<frames {
        let sample = samples[frame]
        sum += sample * sample
      }
    }
    return min(1, sqrt(sum / Float(frames * channelCount)))
  }
}

private struct PCMPlaybackToken: Sendable, Equatable { let generation: UInt64 }

/// Only cancellation/epoch counters cross queues. Never hold this lock while
/// calling the audio SDK: Stop must remain immediate even if hardware stalls.
private final class PCMPlaybackAuthority: @unchecked Sendable {
  private let lock = NSLock()
  private var generation: UInt64 = 0
  private var epoch = 0
  var current: PCMPlaybackToken { lock.withLock { PCMPlaybackToken(generation: generation) } }
  @discardableResult
  func invalidate() -> Int {
    lock.withLock {
      generation &+= 1
      epoch += 1
      return epoch
    }
  }
  func nextEpoch(for token: PCMPlaybackToken) -> Int? {
    lock.withLock {
      guard generation == token.generation else { return nil }
      epoch += 1
      return epoch
    }
  }
}

/// All graph, scheduled-tail and completion mutation is confined to queue.
/// SDK callbacks enqueue work; UI notifications carry only immutable values.
private final class PCMPlaybackWorker: @unchecked Sendable {
  enum Event: Sendable {
    case scheduled(Int)
    case idle(Int)
    case failed(Int)
  }
  private final class Buffer: Sendable {
    let data: Data
    init(_ data: Data) { self.data = data }
  }
  private let queue = DispatchQueue(label: "com.heyintentive.streaming-pcm", qos: .userInitiated)
  private let authority: PCMPlaybackAuthority
  private let levels: AudioLevelDelivery
  private let makeOutput: StreamingPCMPlayer.OutputFactory
  private var output: (any StreamingPCMAudioOutput)?
  private let pending = StreamingPCMPlaybackQueue<Buffer>()
  private var lastEpoch = 0
  private var failedToken: PCMPlaybackToken?
  private var activeToken: PCMPlaybackToken?
  private var events: (@MainActor @Sendable (PCMPlaybackToken, Event) -> Void)?

  init(
    authority: PCMPlaybackAuthority, levels: AudioLevelDelivery, makeOutput: @escaping StreamingPCMPlayer.OutputFactory
  ) {
    self.authority = authority
    self.levels = levels
    self.makeOutput = makeOutput
  }

  func setEventHandler(_ handler: @escaping @MainActor @Sendable (PCMPlaybackToken, Event) -> Void) {
    // The facade queues this before playback; all reads and writes stay here.
    queue.async { self.events = handler }
  }

  func enqueue(
    _ data: Data, token: PCMPlaybackToken, meterCapture: AudioLevelDelivery.Capture,
    completion: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    queue.async {
      guard self.authority.current == token else { return }
      guard self.failedToken != token else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      if self.activeToken != token {
        self.stopOnQueue()
        self.activeToken = token
      }
      if self.output == nil {
        self.output = self.makeOutput(
          { [weak self] in self?.configurationChanged() },
          { [levels = self.levels] level in
            levels.submit(level) { AudioLevelMonitor.shared.updateVoicePlaybackLevel($0) }
          })
      }
      guard data.count >= 2, data.count.isMultiple(of: 2), self.output?.ensureRunning() == true else {
        self.failedToken = token
        DispatchQueue.main.async { completion(false) }
        return
      }
      guard self.authority.current == token else {
        self.stopOnQueue()
        return
      }
      self.levels.activate(meterCapture)
      let accepted = self.schedule(Buffer(data), token: token)
      if !accepted { self.failedToken = token }
      DispatchQueue.main.async { completion(accepted) }
    }
  }

  func stop(completion: @escaping @MainActor @Sendable () -> Void = {}) {
    queue.async {
      self.stopOnQueue()
      DispatchQueue.main.async { completion() }
    }
  }

  private func stopOnQueue() {
    activeToken = nil
    pending.clearForExplicitStop()
    output?.stop()
  }

  private func configurationChanged() {
    queue.async {
      guard let token = self.activeToken, self.authority.current == token, self.failedToken != token else { return }
      log("StreamingPCMPlayer: audio config changed — rebuilding off-main")
      let replay = self.pending.buffersToReplayAfterConfigurationChange()
      self.output?.rebuild()
      // An idle device notification must not restart playback or revive a stop.
      guard !replay.isEmpty, self.authority.current == token else { return }
      guard self.output?.ensureRunning() == true else {
        self.failedToken = token
        self.stopOnQueue()
        self.emit(.failed(self.lastEpoch), token: token)
        return
      }
      guard self.authority.current == token else {
        self.stopOnQueue()
        return
      }
      for buffer in replay {
        guard self.schedule(buffer, token: token) else {
          self.failedToken = token
          self.stopOnQueue()
          self.emit(.failed(self.lastEpoch), token: token)
          return
        }
      }
    }
  }

  private func schedule(_ buffer: Buffer, token: PCMPlaybackToken) -> Bool {
    guard let epoch = authority.nextEpoch(for: token) else { return false }
    let generation = pending.appendScheduled(buffer)
    guard
      output?.schedule(
        buffer.data,
        completion: { [weak self] in
          guard let self else { return }
          self.queue.async {
            guard self.authority.current == token,
              self.pending.markPlayed(buffer, generation: generation), self.pending.isEmpty
            else { return }
            self.emit(.idle(self.lastEpoch), token: token)
          }
        }) == true
    else {
      _ = pending.markPlayed(buffer, generation: generation)
      return false
    }
    guard authority.current == token else {
      stopOnQueue()
      return false
    }
    lastEpoch = epoch
    emit(.scheduled(epoch), token: token)
    return true
  }

  private func emit(_ event: Event, token: PCMPlaybackToken) {
    let handler = events
    DispatchQueue.main.async { handler?(token, event) }
  }
}
