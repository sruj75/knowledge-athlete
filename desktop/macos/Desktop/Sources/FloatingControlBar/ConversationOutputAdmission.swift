import Foundation

/// Audible output waits for a canonical journal target. A slow or rejected
/// write cannot accumulate an unbounded answer or speak an untracked response.
struct ConversationOutputAdmission {
  enum AppendResult: Equatable {
    case held
    case ready(Data)
    case rejected
  }
  private enum State { case waiting, accepted, rejected }
  private var state: State = .waiting
  private var buffered = Data()
  private let maximumBufferedBytes: Int
  var isAccepted: Bool { state == .accepted }

  init(maximumBufferedBytes: Int = 24_000 * 2 * 5) {
    self.maximumBufferedBytes = maximumBufferedBytes
  }

  mutating func append(_ data: Data) -> AppendResult {
    switch state {
    case .accepted: return .ready(data)
    case .rejected: return .rejected
    case .waiting:
      guard buffered.count + data.count <= maximumBufferedBytes else {
        reject()
        return .rejected
      }
      buffered.append(data)
      return .held
    }
  }

  mutating func accept() -> Data? {
    guard state != .rejected else { return nil }
    state = .accepted
    defer { buffered.removeAll() }
    return buffered
  }

  mutating func reject() {
    state = .rejected
    buffered.removeAll()
  }
}
