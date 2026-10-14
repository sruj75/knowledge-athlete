@preconcurrency import AVFoundation
import Foundation

/// Disposable visual levels derived from real audio samples, never synthesized
/// from a provider state or queued answer. Render buffers stay on the worker.
enum ConversationAudioLevel {
  static func pcm16(_ data: Data) -> Float {
    guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Int16>.size) else { return 0 }
    return data.withUnsafeBytes { bytes in
      let samples = bytes.bindMemory(to: Int16.self)
      var sum: Double = 0
      for sample in samples {
        let value = Double(Int16(littleEndian: sample)) / 32768
        sum += value * value
      }
      return Float(min(1, sqrt(sum / Double(samples.count))))
    }
  }

  static func rendered(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let channelCount = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    guard channelCount > 0 else { return 0 }
    var sum: Double = 0
    for channel in 0..<channelCount {
      for frame in 0..<frames {
        let sample =
          buffer.format.isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
        let value = Double(sample)
        if value.isFinite { sum += value * value }
      }
    }
    return Float(min(1, sqrt(sum / Double(channelCount * frames))))
  }
}
