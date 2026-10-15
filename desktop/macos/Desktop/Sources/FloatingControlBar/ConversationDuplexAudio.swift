@preconcurrency import AVFoundation
import Foundation

/// One voice-processing engine owns both render and capture. Routing generated
/// and system speech through its player supplies the echo canceller's reference.
/// Device operation is deliberately off the main actor and audio render thread.
final class ConversationDuplexAudio: @unchecked Sendable {
  enum Failure: Error { case unavailableInput, conversion, playback }
  private let microphoneLevels: AudioLevelDelivery
  private let playbackLevels: AudioLevelDelivery
  private let queue = DispatchQueue(label: "com.heyintentive.conversation.duplex")
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var converter: AVAudioConverter?
  private var playback = ConversationPlaybackQueue()
  private var generation: UInt64 = 0
  private var drain: (@Sendable () -> Void)?
  private var progress: (@Sendable () -> Void)?
  private var started: (@Sendable () -> Void)?
  private var playbackEpoch: UInt64 = 0
  private var outputTapInstalled = false
  private var scheduledOutput = false
  private var playbackLevelHandler: AudioLevelDelivery.Handler?
  private var playbackCapture: AudioLevelDelivery.Capture?
  private var configurationObserver: NSObjectProtocol?
  private let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)
  private let inputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)

  init(
    microphoneLevels: AudioLevelDelivery = AudioLevelDelivery(),
    playbackLevels: AudioLevelDelivery = AudioLevelDelivery()
  ) {
    self.microphoneLevels = microphoneLevels
    self.playbackLevels = playbackLevels
  }

  func start(
    input: @escaping @Sendable (Data) -> Void,
    microphoneLevel: @escaping AudioLevelDelivery.Handler,
    playbackLevel: @escaping AudioLevelDelivery.Handler,
    failure: @escaping @Sendable () -> Void
  ) async throws {
    let microphoneCapture = microphoneLevels.invalidate()
    playbackLevels.invalidate()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        self.stopNow()
        do {
          guard let inputFormat = self.inputFormat, let outputFormat = self.outputFormat else {
            throw Failure.conversion
          }
          let engine = AVAudioEngine()
          let player = AVAudioPlayerNode()
          // Must be configured while stopped. Enabling on input also switches
          // the paired output to voice processing on macOS.
          try engine.inputNode.setVoiceProcessingEnabled(true)
          let captureFormat = engine.inputNode.outputFormat(forBus: 0)
          guard captureFormat.sampleRate > 0, captureFormat.channelCount > 0,
            let converter = AVAudioConverter(from: captureFormat, to: inputFormat)
          else { throw Failure.unavailableInput }
          self.converter = converter
          self.engine = engine
          self.player = player
          self.playbackLevelHandler = playbackLevel
          engine.attach(player)
          engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
          // Voice processing requires identical input/output client formats.
          // The mixer converts the provider's 24 kHz playback to that format.
          engine.connect(engine.mainMixerNode, to: engine.outputNode, format: captureFormat)
          let generation = self.generation
          engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: captureFormat) {
            [weak self] buffer, _ in
            // AVAudioEngine reuses tap buffers. Copy before leaving the callback.
            guard let self, let copy = Self.copy(buffer) else { return }
            let box = ConversationAudioBufferBox(copy)
            self.queue.async {
              guard self.generation == generation, self.engine != nil else { return }
              do {
                let pcm = try self.convertInput(box.buffer)
                self.microphoneLevels.submit(
                  ConversationAudioLevel.pcm16(pcm), capture: microphoneCapture, to: microphoneLevel)
                input(pcm)
              } catch { failure() }
            }
          }
          self.configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
          ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
              guard self.generation == generation else { return }
              // A route change invalidates the graph. Fail visibly instead of
              // retaining an apparently listening conversation with no input.
              failure()
            }
          }
          engine.prepare()
          try engine.start()
          player.play()
          self.microphoneLevels.activate(microphoneCapture)
          continuation.resume()
        } catch {
          self.stopNow()
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func beginPlayback(
    started: @escaping @Sendable () -> Void,
    progress: @escaping @Sendable () -> Void, drained: @escaping @Sendable () -> Void
  ) {
    let capture = playbackLevels.invalidate()
    queue.async {
      self.stopPlaybackNow()
      self.playbackCapture = capture
      self.started = started
      self.progress = progress
      self.drain = drained
      if let engine = self.engine {
        let epoch = self.playbackEpoch
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) {
          [weak self] buffer, _ in
          guard let self, let copy = Self.copy(buffer) else { return }
          let box = ConversationAudioBufferBox(copy)
          self.queue.async {
            guard self.playbackEpoch == epoch, self.scheduledOutput,
              let handler = self.playbackLevelHandler
            else { return }
            let level = ConversationAudioLevel.rendered(box.buffer)
            self.playbackLevels.submit(level, capture: capture, to: handler)
            if level > 0, let started = self.started {
              self.started = nil
              started()
            }
          }
        }
        self.outputTapInstalled = true
      }
      self.playbackLevels.activate(capture)
      self.player?.play()
    }
  }

  func enqueue(_ pcm24k: Data) {
    queue.async {
      guard let player = self.player, self.engine?.isRunning == true,
        let outputFormat = self.outputFormat,
        let buffer = AVAudioPCMBuffer(
          pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(pcm24k.count / 2)),
        let channel = buffer.floatChannelData?[0], !pcm24k.isEmpty
      else { return }
      buffer.frameLength = buffer.frameCapacity
      pcm24k.withUnsafeBytes { raw in
        let samples = raw.bindMemory(to: Int16.self)
        for index in samples.indices { channel[index] = Float(Int16(littleEndian: samples[index])) / 32768 }
      }
      let token = self.playback.enqueue()
      self.scheduledOutput = true
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        guard let self else { return }
        self.queue.async {
          guard self.playback.contains(token) else { return }
          let finished = self.playback.played(token)
          self.progress?()
          if finished { self.finishPlayback() }
        }
      }
      if !player.isPlaying { player.play() }
    }
  }

  func sealPlayback() {
    queue.async { if self.playback.seal() { self.finishPlayback() } }
  }

  /// Flush output while leaving processed microphone capture running for reply.
  func stopPlayback() {
    playbackLevels.invalidate()
    queue.async { self.stopPlaybackNow() }
  }

  private func stopPlaybackNow() {
    playbackEpoch &+= 1
    playback.reset()
    drain = nil
    progress = nil
    started = nil
    scheduledOutput = false
    playbackCapture = nil
    player?.stop()
    removeOutputTap()
  }

  private func removeOutputTap() {
    guard outputTapInstalled else { return }
    engine?.mainMixerNode.removeTap(onBus: 0)
    outputTapInstalled = false
  }

  private func finishPlayback() {
    // Reject render work queued before this physical drain, but never invalidate
    // a receipt already reserved by a newer beginPlayback on the caller thread.
    playbackEpoch &+= 1
    removeOutputTap()
    scheduledOutput = false
    started = nil
    if let capture = playbackCapture, let handler = playbackLevelHandler {
      playbackLevels.submit(0, capture: capture, to: handler)
    }
    let completed = drain
    drain = nil
    completed?()
  }

  func stop() {
    microphoneLevels.invalidate()
    playbackLevels.invalidate()
    queue.async { self.stopNow() }
  }

  func stopAndWait() async {
    microphoneLevels.invalidate()
    playbackLevels.invalidate()
    await withCheckedContinuation { continuation in
      queue.async {
        self.stopNow()
        continuation.resume()
      }
    }
  }

  private func stopNow() {
    generation &+= 1
    if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    configurationObserver = nil
    stopPlaybackNow()
    playbackLevelHandler = nil
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    converter = nil
    player = nil
    engine = nil
  }

  private func convertInput(_ buffer: AVAudioPCMBuffer) throws -> Data {
    guard let converter, let inputFormat,
      let converted = AVAudioPCMBuffer(
        pcmFormat: inputFormat,
        frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate + 32))
    else { throw Failure.conversion }
    let source = ConversationAudioBufferBox(buffer)
    var error: NSError?
    converter.convert(to: converted, error: &error) { _, status in
      guard !source.supplied else {
        status.pointee = .noDataNow
        return nil
      }
      source.supplied = true
      status.pointee = .haveData
      return buffer
    }
    if let error { throw error }
    guard let samples = converted.int16ChannelData?[0] else { throw Failure.conversion }
    return Data(bytes: samples, count: Int(converted.frameLength) * 2)
  }

  private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
    copy.frameLength = buffer.frameLength
    let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for index in source.indices {
      guard let from = source[index].mData, let to = destination[index].mData else { return nil }
      memcpy(to, from, Int(source[index].mDataByteSize))
    }
    return copy
  }
}

private final class ConversationAudioBufferBox: @unchecked Sendable {
  let buffer: AVAudioPCMBuffer
  // Accessed only by AVAudioConverter's synchronous pull callback.
  var supplied = false
  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
