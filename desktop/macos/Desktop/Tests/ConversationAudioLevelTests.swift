import AVFoundation
import XCTest

@testable import Omi_Computer

final class ConversationAudioLevelTests: XCTestCase {
  func testMicrophoneLevelComesFromProcessedSignedPCMIncludingNegativePeaks() {
    let samples: [Int16] = [16384, -16384, 16384, -16384]
    let pcm = samples.withUnsafeBytes { Data($0) }
    XCTAssertEqual(ConversationAudioLevel.pcm16(pcm), 0.5, accuracy: 0.0001)
    XCTAssertEqual(ConversationAudioLevel.pcm16(Data(repeating: 0, count: 1024)), 0)
    XCTAssertEqual(ConversationAudioLevel.pcm16(Data([0])), 0)
    let negativePeak: [Int16] = [.min]
    XCTAssertEqual(ConversationAudioLevel.pcm16(negativePeak.withUnsafeBytes { Data($0) }), 1)
  }

  func testPlaybackLevelUsesRenderedSamplesAcrossChannels() throws {
    let format = try XCTUnwrap(
      AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 2, interleaved: false))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    let channels = try XCTUnwrap(buffer.floatChannelData)
    for frame in 0..<4 {
      channels[0][frame] = 0.5
      channels[1][frame] = -0.5
    }
    XCTAssertEqual(ConversationAudioLevel.rendered(buffer), 0.5, accuracy: 0.0001)
    for frame in 0..<4 {
      channels[0][frame] = 0
      channels[1][frame] = 0
    }
    XCTAssertEqual(ConversationAudioLevel.rendered(buffer), 0)
  }
  func testPlaybackLevelReadsInterleavedStereoWithoutTreatingChannelsAsSeparateBuffers() throws {
    let format = try XCTUnwrap(
      AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 2, interleaved: true))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    let samples = try XCTUnwrap(buffer.floatChannelData)[0]
    for index in 0..<8 { samples[index] = index < 4 ? 0.5 : 0 }
    XCTAssertEqual(ConversationAudioLevel.rendered(buffer), 0.353553, accuracy: 0.0001)
  }

}
