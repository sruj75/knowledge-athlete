@preconcurrency import AVFoundation
import Foundation

/// Synthesis produces PCM, never a second audio device. All audible output
/// returns to the conversation's duplex engine and its playback lease.
@MainActor
final class ConversationSpeechRenderer {
  private let synthesizer = AVSpeechSynthesizer()
  private var generation = UUID()

  func cancel() {
    generation = UUID()
    synthesizer.stopSpeaking(at: .immediate)
  }

  func render(
    _ text: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot,
    audio: @escaping @MainActor @Sendable (Data) -> Void,
    completed: @escaping @MainActor @Sendable (Bool) -> Void
  ) async {
    cancel()
    let token = generation
    let voice = ShortcutSettings.voiceOption(for: ShortcutSettings.shared.selectedVoiceID)
    if voice.isOpenAI, let name = voice.openAIVoice {
      do {
        let compressed = try await APIClient.shared.synthesizeSpeech(
          request: .init(text: text, voiceId: name, instructions: voice.openAIInstructions),
          authorizationSnapshot: authorizationSnapshot)
        let pcm = try await Task.detached { try Self.decode(compressed) }.value
        guard generation == token, !Task.isCancelled,
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
        else { return }
        audio(pcm)
        completed(true)
        return
      } catch {
        guard generation == token, !Task.isCancelled,
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
        else { return }
        DesktopDiagnosticsManager.shared.recordFallback(
          area: "tts_fallback", from: "openai_tts",
          to: "system_voice", reason: "other", outcome: .degraded)
        // The existing local voice is the bounded synthesis fallback.
      }
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice =
      voice.preferredSystemVoiceIdentifiers.compactMap(AVSpeechSynthesisVoice.init(identifier:)).first
      ?? AVSpeechSynthesisVoice.speechVoices().first(where: { voice.preferredSystemVoiceNames.contains($0.name) })
      ?? AVSpeechSynthesisVoice(language: "en-US")
    synthesizer.write(utterance) { [weak self] buffer in
      guard let pcm = buffer as? AVAudioPCMBuffer else { return }
      let finished = pcm.frameLength == 0
      let data = finished ? nil : try? Self.convert(pcm)
      DispatchQueue.main.async {
        guard let self, self.generation == token,
          RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
        else { return }
        if let data { audio(data) }
        if finished {
          completed(true)
        } else if data == nil {
          self.cancel()
          completed(false)
        }
      }
    }
  }

  private nonisolated static func decode(_ compressed: Data) throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("intentive-voice-\(UUID()).mp3")
    try compressed.write(to: url, options: .atomic)
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.length <= 24_000 * 600,
      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
    else { throw ConversationDuplexAudio.Failure.conversion }
    try file.read(into: buffer)
    return try convert(buffer)
  }

  private nonisolated static func convert(_ input: AVAudioPCMBuffer) throws -> Data {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: input.format, to: format),
      let output = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 24_000 / input.format.sampleRate + 64))
    else { throw ConversationDuplexAudio.Failure.conversion }
    let source = ConversationSynthesisInput(input)
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      guard !source.supplied else {
        status.pointee = .endOfStream
        return nil
      }
      source.supplied = true
      status.pointee = .haveData
      return source.buffer
    }
    if let error { throw error }
    guard let samples = output.int16ChannelData?[0] else { throw ConversationDuplexAudio.Failure.conversion }
    return Data(bytes: samples, count: Int(output.frameLength) * 2)
  }
}

private final class ConversationSynthesisInput: @unchecked Sendable {
  let buffer: AVAudioPCMBuffer
  var supplied = false
  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
