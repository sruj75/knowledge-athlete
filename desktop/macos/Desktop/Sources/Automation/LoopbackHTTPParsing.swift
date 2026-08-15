import Foundation

/// Shared fail-closed parsing for the retained development automation bridge.
enum LoopbackHTTPParsing {
  static func parseContentLength(_ value: String, maxBytes: Int) -> Int? {
    guard let parsed = Int(value), parsed >= 0, parsed <= maxBytes else {
      return nil
    }
    return parsed
  }
}
