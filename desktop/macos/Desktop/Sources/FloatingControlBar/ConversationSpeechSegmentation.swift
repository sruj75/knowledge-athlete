import Foundation

/// PCM is already echo-cancelled, mono, signed 16-bit 16 kHz. This deterministic
/// segmenter owns only bounded in-memory audio; Silero supplies the probability.
struct ConversationSpeechSegmentation {
  enum Event {
    case began
    case ended(Data)
  }
  static let frameBytes = 1024
  static let prerollBytes = 16_000
  static let maximumBytes = 270 * 16_000 * 2
  private var preroll = Data()
  private var speech = Data()
  private var speechFrames = 0
  private var silentFrames = 0
  private(set) var speaking = false

  mutating func consume(_ pcm: Data, probability: Float) -> [Event] {
    guard pcm.count == Self.frameBytes else { return [] }
    if !speaking {
      preroll.append(pcm)
      if preroll.count > Self.prerollBytes { preroll.removeFirst(preroll.count - Self.prerollBytes) }
      speechFrames = probability >= 0.5 ? speechFrames + 1 : 0
      guard speechFrames >= 3 else { return [] }
      speaking = true
      speech = preroll
      preroll.removeAll(keepingCapacity: true)
      silentFrames = 0
      return [.began]
    }
    speech.append(pcm)
    silentFrames = probability < 0.35 ? silentFrames + 1 : 0
    guard silentFrames >= 25 || speech.count >= Self.maximumBytes else { return [] }
    let result = speech
    speech.removeAll(keepingCapacity: true)
    speaking = false
    speechFrames = 0
    silentFrames = 0
    return [.ended(result)]
  }

  mutating func reset() { self = Self() }
}

/// A single worker serializes model state and segmentation. No ONNX inference
/// runs on the audio render callback or the main actor.
final class ConversationSpeechDetector: @unchecked Sendable {
  enum Event: Sendable {
    case began
    case ended(Data)
  }
  private let queue = DispatchQueue(label: "com.heyintentive.conversation.speech")
  private var model: SileroVADModel?
  private var pending = Data()
  private var segmentation = ConversationSpeechSegmentation()
  private var generation: UInt64 = 0

  func start() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        self.generation &+= 1
        self.model = SileroVADModel()
        self.pending.removeAll()
        self.segmentation.reset()
        continuation.resume(returning: self.model != nil)
      }
    }
  }

  func consume(_ data: Data, events: @escaping @Sendable ([Event]) -> Void) {
    queue.async {
      guard let model = self.model else { return }
      self.pending.append(data)
      var emitted: [Event] = []
      while self.pending.count >= ConversationSpeechSegmentation.frameBytes {
        let frame = Data(self.pending.prefix(ConversationSpeechSegmentation.frameBytes))
        self.pending.removeFirst(ConversationSpeechSegmentation.frameBytes)
        let samples = frame.withUnsafeBytes { raw in
          raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32768 }
        }
        for event in self.segmentation.consume(frame, probability: model.predict(samples)) {
          switch event {
          case .began: emitted.append(.began)
          case .ended(let pcm): emitted.append(.ended(pcm))
          }
        }
      }
      if !emitted.isEmpty { events(emitted) }
    }
  }

  func stop() {
    queue.async {
      self.generation &+= 1
      self.model = nil
      self.pending.removeAll()
      self.segmentation.reset()
    }
  }
}
