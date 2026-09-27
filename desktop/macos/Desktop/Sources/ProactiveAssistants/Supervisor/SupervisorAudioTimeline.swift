import Foundation

/// Capture time on the monotonic host clock, independent of decoder/network latency.
struct SupervisorCaptureInterval: Equatable, Sendable {
  let start: TimeInterval
  let end: TimeInterval

  static func captured(byteCount: Int, endingAt time: TimeInterval = ProcessInfo.processInfo.systemUptime)
    -> Self
  {
    Self(start: time - Double(byteCount) / 32_000, end: time)
  }

  func overlaps(_ other: Self) -> Bool { start < other.end && other.start < end }

  func union(_ other: Self) -> Self {
    Self(start: min(start, other.start), end: max(end, other.end))
  }
}

/// A bounded sidecar for 16 kHz PCM. Missing/retired spans fail closed for B only.
/// Offsets advance even for unknown timestamps, so later known audio cannot be
/// rebound to earlier decoder timestamps after a gap or reconnect.
struct SupervisorAudioTimeline: Sendable {
  private struct Span: Sendable {
    let start: Double
    let end: Double
    let capture: SupervisorCaptureInterval?
  }
  private var spans: [Span] = []
  private(set) var duration: TimeInterval = 0

  mutating func append(byteCount: Int, interval: SupervisorCaptureInterval?) {
    guard byteCount > 0 else { return }
    let next = duration + Double(byteCount) / 32_000
    spans.append(Span(start: duration, end: next, capture: interval))
    duration = next
    if spans.count > 4096 { spans.removeFirst(spans.count - 4096) }
  }

  func interval(start: Double, end: Double) -> SupervisorCaptureInterval? {
    guard start.isFinite, end.isFinite, start >= 0, end > start,
      let first = spans.first, start >= first.start - 0.000_001,
      end <= duration + 0.000_001
    else { return nil }
    let matching = spans.filter { $0.start < end && start < $0.end }
    guard !matching.isEmpty else { return nil }
    var result: SupervisorCaptureInterval?
    for span in matching {
      guard let capture = span.capture, capture.start.isFinite, capture.end.isFinite,
        capture.end >= capture.start
      else { return nil }
      let scale = (capture.end - capture.start) / (span.end - span.start)
      let mapped = SupervisorCaptureInterval(
        start: capture.start + (max(start, span.start) - span.start) * scale,
        end: capture.start + (min(end, span.end) - span.start) * scale)
      result = result.map { $0.union(mapped) } ?? mapped
    }
    return result
  }
}
