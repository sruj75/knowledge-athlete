import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationAudioLevelMonitorTests: XCTestCase {
  func testConversationMeterOwnsVisibleLevelsAcrossAmbientReset() {
    let monitor = AudioLevelMonitor()
    monitor.updateMicrophoneLevel(0.9)
    let receipt = monitor.beginConversationMeter()
    monitor.updateConversationMicrophoneLevel(0.4, receipt: receipt)
    monitor.updateConversationPlaybackLevel(0.7, receipt: receipt)
    monitor.updateMicrophoneLevel(0.1)
    monitor.updateVoicePlaybackLevel(0.2)
    monitor.reset()
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0.4)
    XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0.7)
    monitor.updateConversationPlaybackLevel(0, receipt: receipt)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0.4, "Stopping a reply leaves the microphone meter alive")
    XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0)
    monitor.endConversationMeter(receipt: receipt)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0)
    XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0)
  }
  func testOldConversationCannotChangeOrCloseReplacementMeter() {
    let monitor = AudioLevelMonitor()
    let old = monitor.beginConversationMeter()
    monitor.updateConversationMicrophoneLevel(0.8, receipt: old)
    let current = monitor.beginConversationMeter()
    monitor.updateConversationMicrophoneLevel(0.3, receipt: current)
    monitor.updateConversationPlaybackLevel(0.6, receipt: current)
    monitor.updateConversationMicrophoneLevel(1, receipt: old)
    monitor.updateConversationPlaybackLevel(1, receipt: old)
    monitor.endConversationMeter(receipt: old)
    XCTAssertEqual(monitor.liveMicrophoneLevel, 0.3)
    XCTAssertEqual(monitor.liveVoicePlaybackLevel, 0.6)
  }

}
