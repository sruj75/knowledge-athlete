import Foundation

/// Bounded connection-start buffering. Overflow invalidates the entire prefix:
/// fallback consumes the separately retained, complete speech segment instead.
struct ConversationPendingAudio {
  private let maximumBytes: Int
  private var data = Data()
  private var overflowed = false

  init(maximumBytes: Int = 16_000 * 2 * 10) { self.maximumBytes = maximumBytes }

  mutating func append(_ pcm: Data) -> Bool {
    guard !overflowed else { return false }
    guard data.count + pcm.count <= maximumBytes else {
      overflowed = true
      data.removeAll()
      return false
    }
    data.append(pcm)
    return true
  }

  mutating func take() -> Data? {
    guard !overflowed else { return nil }
    defer { data.removeAll() }
    return data
  }

  mutating func reset() {
    data.removeAll()
    overflowed = false
  }
}
