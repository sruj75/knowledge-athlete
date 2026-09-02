import Foundation

enum AuthLogPrivacy {
  static func callbackReceived(_: URL) -> String {
    "INTENTIVE AUTH: Received OAuth callback"
  }

  static func responseFailure(_ operation: String, _ statusCode: Int, _: Data) -> String {
    "INTENTIVE AUTH: \(operation) failed (HTTP \(statusCode))"
  }

  static func responseParsingFailure(_ operation: String, _: Data) -> String {
    "INTENTIVE AUTH: \(operation) returned an invalid response"
  }
}
