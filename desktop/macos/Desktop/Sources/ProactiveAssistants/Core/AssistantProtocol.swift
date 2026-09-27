import Foundation

/// Result from an assistant's analysis
protocol AssistantResult: Sendable {
  /// Convert result to dictionary for Flutter communication
  func toDictionary() -> [String: Any]
}
