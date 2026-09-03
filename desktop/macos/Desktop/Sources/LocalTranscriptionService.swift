@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import SoundAnalysis

protocol LocalTranscriptionAudioReceiving: AnyObject, Sendable {
  func appendAudio(_ data: Data)
}

final class LocalTranscriptionAudioSink: @unchecked Sendable {
  private let lock = NSLock()
  private var service: (any LocalTranscriptionAudioReceiving)?
  private var buffered: [Data] = []
  private var buffering = false

  func append(_ data: Data) {
    lock.withLock {
      if buffering {
        buffered.append(data)
      } else {
        // Delivery is part of the sink's synchronization boundary. `beginHandoff()` must not
        // return while an append already admitted to the retiring receiver is still in flight.
        service?.appendAudio(data)
      }
    }
  }

  func beginHandoff() {
    lock.withLock {
      buffering = true
      service = nil
    }
  }

  func completeHandoff(to newService: any LocalTranscriptionAudioReceiving) {
    lock.withLock {
      // Keep live callbacks behind the sink lock until every older buffered chunk has reached
      // the new receiver. Publishing the receiver first would let newer PCM overtake the replay.
      buffered.forEach { newService.appendAudio($0) }
      buffered.removeAll()
      service = newService
      buffering = false
    }
  }

  func clear() {
    lock.withLock {
      service = nil
      buffering = false
      buffered.removeAll()
    }
  }
}

/// Tallies Apple SoundAnalysis frames over one window to decide if it's music/singing vs speech.
/// Used to keep songs / TV / videos playing through *system audio* from becoming "conversations".
@available(macOS 12.0, *)
private final class MusicTally: NSObject, SNResultsObserving {
  private(set) var frames = 0
  private(set) var musicFrames = 0
  private(set) var speechFrames = 0

  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let cr = result as? SNClassificationResult, let top = cr.classifications.first else { return }
    frames += 1
    guard top.confidence > 0.3 else { return }
    let id = top.identifier.lowercased()
    if id == "speech" {
      speechFrames += 1
    } else if id == "music" || id == "singing" || id.contains("music") {
      musicFrames += 1
    }
  }

  /// Music when music frames dominate speech *and* make up a meaningful share of the window —
  /// so a call (other party's speech through system audio) is kept, but a song is dropped.
  var isMusic: Bool { frames > 0 && musicFrames > speechFrames && musicFrames * 3 >= frames }
}

/// On-device speech-to-text via FluidAudio (NVIDIA Parakeet TDT, CoreML on the Apple Neural Engine).
///
/// Drop-in alternative to the cloud `TranscriptionService` for the desktop mono path: it accepts the
/// *same* 16 kHz mono Int16 little-endian PCM the WebSocket path receives, accumulates it into fixed
/// windows, transcribes each window locally, and emits `TranscriptionService.BackendSegment` so the
/// existing UI / DB pipeline (`handleBackendSegments`) is unchanged.
///
/// Enabled via `OMI_LOCAL_STT=1` (or `defaults write <bundle> useLocalSTT -bool true`). No network,
/// no Deepgram. Model weights (~600 MB–1.2 GB) download from HuggingFace on first run and are cached.
final class LocalTranscriptionService: @unchecked Sendable {

  typealias SegmentsHandler = @MainActor ([TranscriptionService.BackendSegment]) async -> Void
  typealias ModelLoader = @Sendable (AsrModelVersion) async throws -> AsrManager
  typealias WindowTranscriber = @Sendable (AsrManager, [Float]) async throws -> ASRResult

  enum FailureReason: String, Sendable {
    case modelLoad = "model_load_failed"
    case bufferExhausted = "buffer_exhausted"
    case inference = "inference_failed"
  }

  typealias FailureHandler = @MainActor (FailureReason) -> Void

  private struct DrainSnapshot {
    let manager: AsrManager
    let window: [Float]
    let startSec: Double
    let durSec: Double
  }

  private let language: String
  /// Source-based diarization: mic = the user ("You"), system audio = another speaker.
  private let isUser: Bool
  private let speakerId: Int
  private let modelLoader: ModelLoader
  private let windowTranscriber: WindowTranscriber
  private let sampleRate = 16000
  private let maxBufferedSamples: Int
  /// Window length transcribed at a time. Not real-time — gives a ~10 s "lag" like the user wants.
  private let windowSeconds = 10.0
  private var windowSamples: Int { Int(Double(sampleRate) * windowSeconds) }

  private var asrManager: AsrManager?
  private var onSegments: SegmentsHandler?
  /// Fired (on the main actor) if Parakeet can no longer capture for any typed reason. Lets
  /// AppState stop or fall back instead of silently producing a blank transcript.
  private var onFailure: FailureHandler?

  // 16 kHz mono Float32 sample buffer, guarded by `lock`.
  private let lock = NSLock()
  private var buffer: [Float] = []
  private var isReady = false
  private var isFlushing = false
  /// Set false when retiring the service (stop/finish) so no new samples enter the buffer while
  /// the final drain is in flight — otherwise audio captured during the ~100ms drain (capture is
  /// still running across a finishConversation rotation) would be appended past the snapshot and
  /// silently dropped.
  private var acceptingAudio = true
  private var isRetiring = false
  private var readinessResult: Bool?
  private var terminalFailureReasonStorage: FailureReason?
  private var readinessWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
  private var flushWaiters: [CheckedContinuation<Void, Never>] = []
  private var emittedSeconds = 0.0  // absolute start offset of the next emitted segment

  private var pumpTask: Task<Void, Never>?
  private var modelLoadTask: Task<Void, Never>?

  init(
    language: String = "en",
    isUser: Bool = true,
    maxBufferedSeconds: Double = 120,
    modelLoader: @escaping ModelLoader = { version in
      let models = try await AsrModels.downloadAndLoad(version: version)
      let manager = AsrManager()
      try await manager.loadModels(models)
      return manager
    },
    windowTranscriber: @escaping WindowTranscriber = { manager, window in
      var decoderState = try TdtDecoderState()
      return try await manager.transcribe(window, decoderState: &decoderState, language: nil)
    }
  ) {
    self.language = language
    self.isUser = isUser
    self.speakerId = isUser ? 0 : 1
    self.maxBufferedSamples = max(1, Int(16000 * maxBufferedSeconds))
    self.modelLoader = modelLoader
    self.windowTranscriber = windowTranscriber
  }

  /// Begin loading the model (async) and start the periodic flush loop.
  /// `onFailure` fires once with a typed reason when the local engine can no longer capture.
  func start(onSegments: @escaping SegmentsHandler, onFailure: FailureHandler? = nil) {
    self.onSegments = onSegments
    self.onFailure = onFailure

    modelLoadTask = Task { [weak self] in
      guard let self else { return }
      do {
        // Test hook: force a model-load failure to exercise the cloud fallback path.
        // Toggle with env OMI_FORCE_PARAKEET_FAIL=1 or `defaults write <bundle> forceParakeetFail -bool true`.
        if ProcessInfo.processInfo.environment["OMI_FORCE_PARAKEET_FAIL"] == "1"
          || UserDefaults.standard.bool(forKey: "forceParakeetFail")
        {
          throw NSError(
            domain: "LocalTranscriptionService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "forced model-load failure (OMI_FORCE_PARAKEET_FAIL)"])
        }
        // v2 = English-only (better recall); v3 = 25 European languages.
        let version: AsrModelVersion = self.language.hasPrefix("en") ? .v2 : .v3
        let started = Date()
        let manager = try await self.modelLoader(version)
        let waiters = self.lock.withLock {
          guard self.readinessResult != false, self.acceptingAudio, !self.isRetiring else {
            return [] as [CheckedContinuation<Bool, Never>]
          }
          self.asrManager = manager
          self.isReady = true
          self.readinessResult = true
          self.terminalFailureReasonStorage = nil
          let waiters = Array(self.readinessWaiters.values)
          self.readinessWaiters.removeAll()
          return waiters
        }
        waiters.forEach { $0.resume(returning: true) }
        log(
          "LocalTranscriptionService: Parakeet \(version) ready in \(String(format: "%.1f", Date().timeIntervalSince(started)))s"
        )
      } catch {
        logError("LocalTranscriptionService: model load failed", error: error)
        let failure = self.lock.withLock {
          guard self.readinessResult != false else {
            return ([], nil)
              as (
                [CheckedContinuation<Bool, Never>], FailureHandler?
              )
          }
          self.readinessResult = false
          self.terminalFailureReasonStorage = .modelLoad
          let waiters = Array(self.readinessWaiters.values)
          self.readinessWaiters.removeAll()
          let callback = self.onFailure
          self.onFailure = nil
          return (waiters, callback)
        }
        failure.0.forEach { $0.resume(returning: false) }
        if let callback = failure.1 {
          await MainActor.run { callback(.modelLoad) }
        }
      }
    }

    pumpTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { break }
        await self?.drain(force: false)
      }
    }
  }

  /// Wait until the asynchronous Parakeet load has either succeeded or failed.
  /// Fair-use handoff uses this before claiming that local transcription recovered.
  func waitUntilReady(timeoutNanoseconds: UInt64? = nil) async -> Bool {
    let waiterID = UUID()
    return await withCheckedContinuation { continuation in
      let immediate = lock.withLock { () -> Bool? in
        if let readinessResult {
          return readinessResult && isReady && asrManager != nil && acceptingAudio && !isRetiring
        }
        guard modelLoadTask != nil, acceptingAudio, !isRetiring else { return false }
        readinessWaiters[waiterID] = continuation
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
        return
      }
      guard let timeoutNanoseconds else { return }
      Task { [weak self] in
        do {
          try await Task.sleep(nanoseconds: timeoutNanoseconds)
        } catch {
          return
        }
        guard let self else { return }
        let timedOut = self.lock.withLock { self.readinessWaiters.removeValue(forKey: waiterID) }
        timedOut?.resume(returning: false)
      }
    }
  }

  var isUsableForCapture: Bool {
    lock.withLock { readinessResult == true && isReady && asrManager != nil && acceptingAudio && !isRetiring }
  }

  var terminalFailureReason: FailureReason? {
    lock.withLock { terminalFailureReasonStorage }
  }

  /// Feed 16 kHz mono Int16 little-endian PCM — the same `Data` the WebSocket path sends.
  func appendAudio(_ data: Data) {
    let floats = Self.int16ToFloat32(data)
    guard !floats.isEmpty else { return }
    let overflow = lock.withLock {
      () -> (
        [CheckedContinuation<Bool, Never>], FailureHandler?,
        Task<Void, Never>?, Task<Void, Never>?
      )? in
      guard acceptingAudio else { return nil }
      guard buffer.count + floats.count <= maxBufferedSamples else {
        acceptingAudio = false
        isRetiring = true
        buffer.removeAll()
        readinessResult = false
        terminalFailureReasonStorage = .bufferExhausted
        let waiters = Array(readinessWaiters.values)
        readinessWaiters.removeAll()
        let callback = onFailure
        onFailure = nil
        let tasks = (pumpTask, modelLoadTask)
        pumpTask = nil
        modelLoadTask = nil
        return (waiters, callback, tasks.0, tasks.1)
      }
      buffer.append(contentsOf: floats)
      return nil
    }
    guard let overflow else { return }
    overflow.2?.cancel()
    overflow.3?.cancel()
    overflow.0.forEach { $0.resume(returning: false) }
    logError(
      "LocalTranscriptionService: bounded model-readiness audio buffer exhausted",
      error: NSError(domain: "LocalTranscriptionService", code: -2))
    if let callback = overflow.1 {
      Task { @MainActor in callback(.bufferExhausted) }
    }
  }

  /// Fire-and-forget stop. Prefer `await finish()` whenever the session lifecycle allows it —
  /// `finish()` guarantees the final tail is persisted before the caller rotates/clears the
  /// session. `stop()` only drains on a detached Task, so a caller that mutates session state
  /// right after (e.g. the 4-hour restart path) can still race; it exists for teardown sites
  /// that don't have an async context.
  func stop() {
    Task { await self.finish() }
  }

  /// Owner transitions revoke capture instead of flushing it. A flush can call the segment
  /// callback and must not wait on the owner-transition fence or reach a retargeted database.
  func discardBufferedAudio() {
    let state = lock.withLock {
      () -> (
        Task<Void, Never>?, Task<Void, Never>?, [CheckedContinuation<Bool, Never>]
      ) in
      acceptingAudio = false
      isRetiring = true
      readinessResult = false
      buffer.removeAll()
      onSegments = nil
      onFailure = nil
      let waiters = Array(readinessWaiters.values)
      readinessWaiters.removeAll()
      let tasks = (pumpTask, modelLoadTask)
      pumpTask = nil
      modelLoadTask = nil
      return (tasks.0, tasks.1, waiters)
    }
    state.0?.cancel()
    state.1?.cancel()
    state.2.forEach { $0.resume(returning: false) }
  }

  /// Awaitable flush. Cancels the pump and transcribes ALL remaining audio, delivering the
  /// final segments (synchronously on the main actor) before returning. Callers must `await`
  /// this before clearing/rotating the session so the last words persist to the right
  /// conversation instead of racing the async drain.
  func finish() async {
    let mustWaitForFlush = lock.withLock {
      acceptingAudio = false
      isRetiring = true
      onFailure = nil
      return isFlushing
    }
    if mustWaitForFlush {
      await withCheckedContinuation { continuation in
        let resumeNow = lock.withLock {
          guard isFlushing else { return true }
          flushWaiters.append(continuation)
          return false
        }
        if resumeNow { continuation.resume() }
      }
    }
    let pump = pumpTask
    pumpTask = nil
    pump?.cancel()
    await pump?.value
    let loader = modelLoadTask
    await loader?.value
    modelLoadTask = nil
    await drain(force: true)
  }

  /// Flush every remaining buffered sample (called on stop). Waits out any in-flight window
  /// flush first, then transcribes the sub-window tail so the last words aren't dropped.
  /// Transcribe one window (or whatever remains, when `force`) and emit a segment.
  private func drain(force: Bool) async {
    guard
      let snapshot = lock.withLock({
        guard isReady, let manager = asrManager, !isFlushing, force || !isRetiring else {
          return nil as DrainSnapshot?
        }
        let available = buffer.count
        // On force (stop/finish) flush whatever is left, even a sub-window tail; otherwise wait for a full window.
        let ready = available >= windowSamples || (force && available > 0)
        guard ready else { return nil }
        let take = force ? available : windowSamples
        let window = Array(buffer.prefix(take))
        buffer.removeFirst(take)
        let startSec = emittedSeconds
        let durSec = Double(take) / Double(sampleRate)
        emittedSeconds += durSec
        isFlushing = true
        return DrainSnapshot(manager: manager, window: window, startSec: startSec, durSec: durSec)
      })
    else { return }

    defer {
      let waiters = lock.withLock {
        isFlushing = false
        let values = flushWaiters
        flushWaiters.removeAll()
        return values
      }
      waiters.forEach { $0.resume() }
    }

    // Only skip DEAD silence (noise floor). The previous 0.012 threshold was tuned on loud
    // speaker playback and ate real (quieter) microphone speech — users saw "nothing
    // transcribed". A low floor lets normal mic speech through; hallucinations on near-silence
    // are filtered below by the model's own confidence score instead.
    let rms = (snapshot.window.reduce(Float(0)) { $0 + $1 * $1 } / Float(snapshot.window.count)).squareRoot()
    guard rms > 0.004 else { return }

    // Music/video gate: don't turn songs, TV, or videos playing through *system audio* into
    // "conversations" — only real conversations/calls should be transcribed. Applied to the
    // system channel only; the mic channel (the user's own voice) is never gated. Runs Apple's
    // on-device SoundAnalysis classifier *before* Parakeet, so music also costs us no transcription.
    if !isUser, Self.windowIsMusic(snapshot.window, sampleRate: sampleRate) {
      log(
        String(
          format: "LocalTranscriptionService[sys]: skipped %.1fs music/video window (rms=%.4f)", snapshot.durSec, rms))
      return
    }

    do {
      // Fresh decoder state per window. Persisting TdtDecoderState across arbitrary 10 s
      // windows makes the transducer decoder drift — it starts looping ("...AND AND AND"),
      // Title-Casing every word, and emitting gibberish. Independent per-window decode is stable.
      let result = try await windowTranscriber(snapshot.manager, snapshot.window)

      var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
      // Silence makes the TDT decoder emit just "." / "..." — drop windows with no real speech.
      guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
      // NOTE: confidence is logged (below) but NOT yet used to gate — we don't know its scale
      // for real speech vs noise-hallucinations. Once the logs show the distribution we add a
      // confidence floor here to catch near-silence gibberish without dropping quiet speech.
      // Strip stray leading punctuation the streaming decoder prepends at window boundaries.
      while let first = text.first, !first.isLetter && !first.isNumber {
        text.removeFirst()
      }

      let segment = TranscriptionService.BackendSegment(
        segmentId: UUID().uuidString.lowercased(),
        speakerId: speakerId,
        text: text,
        isUser: isUser,
        start: snapshot.startSec,
        end: snapshot.startSec + snapshot.durSec
      )
      // Deliver synchronously on the main actor so an awaited finish() guarantees the
      // segment is persisted (to the current session) before the caller rotates state.
      if self.onSegments != nil {
        let segs = [segment]
        await self.onSegments?(segs)
      }
      log(
        String(
          format: "LocalTranscriptionService[%@]: %.1fs rms=%.4f conf=%.2f rtfx=%.0fx → %@",
          isUser ? "mic" : "sys", snapshot.durSec, rms, result.confidence, result.rtfx, text))
    } catch {
      await retireAfterInferenceFailure(error)
    }
  }

  /// Deterministic production-behavior seam for exercising a full buffered window in tests.
  func processBufferedAudioForTesting() async {
    await drain(force: false)
  }

  private func retireAfterInferenceFailure(_ error: Error) async {
    let failure = lock.withLock {
      () -> (
        [CheckedContinuation<Bool, Never>], FailureHandler?, Task<Void, Never>?,
        Task<Void, Never>?
      ) in
      acceptingAudio = false
      isRetiring = true
      isReady = false
      asrManager = nil
      readinessResult = false
      terminalFailureReasonStorage = .inference
      buffer.removeAll()
      let waiters = Array(readinessWaiters.values)
      readinessWaiters.removeAll()
      let callback = onFailure
      onFailure = nil
      let tasks = (pumpTask, modelLoadTask)
      pumpTask = nil
      modelLoadTask = nil
      return (waiters, callback, tasks.0, tasks.1)
    }
    failure.2?.cancel()
    failure.3?.cancel()
    failure.0.forEach { $0.resume(returning: false) }
    logError("LocalTranscriptionService: transcribe failed", error: error)
    if let callback = failure.1 {
      await MainActor.run { callback(.inference) }
    }
  }

  /// Classify a 16 kHz mono window as music/singing (vs speech) using Apple's on-device
  /// SoundAnalysis. Returns true → caller skips transcribing it. Fails *open* (returns false) on
  /// any error or on macOS < 12, so audio is never silently dropped when classification is unsure.
  private static func windowIsMusic(_ window: [Float], sampleRate: Int) -> Bool {
    guard #available(macOS 12.0, *) else { return false }
    guard window.count >= sampleRate,  // need ~1s+ for a stable classification
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(sampleRate), channels: 1, interleaved: false),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(window.count)),
      let channel = buffer.floatChannelData
    else { return false }
    buffer.frameLength = AVAudioFrameCount(window.count)
    window.withUnsafeBufferPointer { channel[0].update(from: $0.baseAddress!, count: window.count) }

    // SoundAnalysis ships a file analyzer and a stream analyzer; the file analyzer's synchronous
    // analyze() blocks until the observer has all results, so we write the window to a temp WAV.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("intentive_music_\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }

    do {
      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: Double(sampleRate),
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ]
      let file = try AVAudioFile(forWriting: url, settings: settings)
      try file.write(from: buffer)

      let analyzer = try SNAudioFileAnalyzer(url: url)
      let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
      let tally = MusicTally()
      try analyzer.add(request, withObserver: tally)
      analyzer.analyze()  // synchronous: tally fully populated before this returns
      return tally.isMusic
    } catch {
      return false
    }
  }

  /// Convert 16-bit little-endian mono PCM to normalized Float32 [-1, 1].
  private static func int16ToFloat32(_ data: Data) -> [Float] {
    let count = data.count / 2
    guard count > 0 else { return [] }
    return data.withUnsafeBytes { raw -> [Float] in
      let samples = raw.bindMemory(to: Int16.self)
      var out = [Float](repeating: 0, count: count)
      for i in 0..<count {
        out[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
      }
      return out
    }
  }
}

extension LocalTranscriptionService: LocalTranscriptionAudioReceiving {}
