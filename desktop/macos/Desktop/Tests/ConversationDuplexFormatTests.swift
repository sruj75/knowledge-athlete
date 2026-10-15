import AVFoundation
import XCTest

@testable import Omi_Computer

final class ConversationDuplexFormatTests: XCTestCase {
  func testDiscreteDeviceChannelsPreserveMicrophoneSignalThroughProductionConversion() throws {
    for rate in [44_100.0, 48_000.0] {
      for channels in [3, 7] {
        try assertSignalPreserved(sampleRate: rate, deviceChannels: channels)
      }
    }
  }

  func testMonoDevicePreservesMicrophoneSignalThroughProductionConversion() throws {
    for rate in [44_100.0, 48_000.0] {
      try assertSignalPreserved(sampleRate: rate, deviceChannels: 1)
    }
  }

  private func assertSignalPreserved(sampleRate: Double, deviceChannels: Int) throws {
    let context = "\(deviceChannels) device channels at \(sampleRate) Hz"
    let layout = try XCTUnwrap(
      AVAudioChannelLayout(
        layoutTag: deviceChannels == 1
          ? kAudioChannelLayoutTag_Mono
          : kAudioChannelLayoutTag_DiscreteInOrder | UInt32(deviceChannels)))
    let deviceFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
      interleaved: false, channelLayout: layout)
    let clientFormat = try XCTUnwrap(
      ConversationDuplexAudio.voiceProcessingClientFormat(for: deviceFormat))
    XCTAssertEqual(clientFormat.sampleRate, sampleRate, context)
    XCTAssertEqual(clientFormat.channelCount, 1, context)
    XCTAssertEqual(clientFormat.commonFormat, .pcmFormatFloat32, context)
    XCTAssertFalse(clientFormat.isInterleaved, context)
    let targetFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000,
        channels: 1, interleaved: false))
    let converter = try XCTUnwrap(AVAudioConverter(from: clientFormat, to: targetFormat))
    let chunkFrames = 1_024
    let chunkCount = 8
    var pcm = Data()
    for chunk in 0..<chunkCount {
      let buffer = try XCTUnwrap(
        AVAudioPCMBuffer(pcmFormat: clientFormat, frameCapacity: AVAudioFrameCount(chunkFrames)))
      buffer.frameLength = buffer.frameCapacity
      let samples = try XCTUnwrap(buffer.floatChannelData)
      for channel in 0..<Int(clientFormat.channelCount) {
        for frame in 0..<chunkFrames {
          let time = Double(chunk * chunkFrames + frame) / sampleRate
          samples[channel][frame] = Float(0.02 * sin(2 * .pi * 440 * time))
        }
      }
      let converted = try ConversationDuplexAudio.microphonePCM(from: buffer, using: converter)
      XCTAssertFalse(converted.isEmpty, context)
      XCTAssertEqual(converted.count % MemoryLayout<Int16>.size, 0, context)
      pcm.append(converted)
    }
    let outputFrames = pcm.count / MemoryLayout<Int16>.size
    let expectedFrames = Double(chunkFrames * chunkCount) * 16_000 / sampleRate
    // The streaming converter may retain its small resampling tail without EOF.
    XCTAssertEqual(Double(outputFrames), expectedFrames, accuracy: 64, context)
    var squared = 0.0
    var nonzero = 0
    pcm.withUnsafeBytes { raw in
      for sample in raw.bindMemory(to: Int16.self) {
        let value = Double(Int16(littleEndian: sample)) / 32768
        squared += value * value
        if sample != 0 { nonzero += 1 }
      }
    }
    XCTAssertGreaterThan(nonzero, Int(expectedFrames * 0.9), context)
    let rms = outputFrames > 0 ? sqrt(squared / Double(outputFrames)) : 0
    XCTAssertEqual(rms, 0.02 / sqrt(2), accuracy: 0.001, context)
  }
}
