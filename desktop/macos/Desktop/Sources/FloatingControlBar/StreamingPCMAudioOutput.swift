@preconcurrency import AVFoundation
import Foundation

/// The audio SDK boundary. Every operation, including creation and teardown,
/// belongs to StreamingPCMPlayer's one serial audio owner, never MainActor.
protocol StreamingPCMAudioOutput: AnyObject {
  func ensureRunning() -> Bool
  func rebuild()
  func schedule(_ pcm: Data, completion: @escaping @Sendable () -> Void) -> Bool
  func stop()
}

final class AVFoundationStreamingPCMOutput: StreamingPCMAudioOutput {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format: AVAudioFormat
  private var observer: NSObjectProtocol?

  init(
    sampleRate: Double,
    configurationChanged: @escaping @Sendable () -> Void,
    level: @escaping @Sendable (Float) -> Void
  ) {
    guard
      let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    else { preconditionFailure("Streaming PCM requires a valid mono output format") }
    format = pcmFormat
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.installTap(
      onBus: 0, bufferSize: 1024, format: engine.mainMixerNode.outputFormat(forBus: 0)
    ) { buffer, _ in level(StreamingPCMPlayer.rmsLevel(of: buffer)) }
    observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { _ in configurationChanged() }
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  func ensureRunning() -> Bool {
    if !engine.isRunning {
      engine.prepare()
      do {
        try engine.start()
        log("StreamingPCMPlayer: engine started")
      } catch {
        log("StreamingPCMPlayer: engine start failed")
        return false
      }
    }
    if !player.isPlaying { player.play() }
    return player.isPlaying
  }

  func rebuild() {
    stop()
    engine.disconnectNodeOutput(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }

  func schedule(_ pcm: Data, completion: @escaping @Sendable () -> Void) -> Bool {
    let sampleCount = pcm.count / 2
    guard sampleCount > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
      let channel = buffer.floatChannelData?[0]
    else { return false }
    buffer.frameLength = AVAudioFrameCount(sampleCount)
    pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let samples = raw.bindMemory(to: Int16.self)
      for index in 0..<sampleCount {
        channel[index] = max(-1, min(1, Float(samples[index]) / 32768))
      }
    }
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
    return true
  }

  func stop() {
    player.stop()
    engine.stop()
  }
}
