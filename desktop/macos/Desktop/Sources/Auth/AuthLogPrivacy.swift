import Foundation

enum AuthLogPrivacy {
  static func callbackReceived(_: URL) -> String {
    "INTENTIVE AUTH: Received OAuth callback"
  }

  static func recordCallbackReceived(_ url: URL, sink: (String) -> Void) {
    sink(callbackReceived(url))
  }

  static func responseFailure(_ operation: String, _ statusCode: Int, _: Data) -> String {
    "INTENTIVE AUTH: \(operation) failed (HTTP \(statusCode))"
  }

  static func responseParsingFailure(_ operation: String, _: Data) -> String {
    "INTENTIVE AUTH: \(operation) returned an invalid response"
  }

  static func idTokenProfileClaimsExtracted(_: [String: Any]) -> String {
    "INTENTIVE AUTH: Extracted profile claims from id_token"
  }

  static func analyticsIdentificationSucceeded(_: String) -> String {
    "INTENTIVE ANALYTICS: Identified signed-in user"
  }

  static func recordAnalyticsIdentification(_ userIdentifier: String, sink: (String) -> Void) {
    sink(analyticsIdentificationSucceeded(userIdentifier))
  }

  static func authStateInitialized(
    localProfile: Bool,
    savedSignedIn: Bool,
    email _: String?,
    isRestoringAuth: Bool
  ) -> String {
    "INTENTIVE AUTH: Initialized localProfile=\(localProfile) savedSignedIn=\(savedSignedIn) "
      + "isRestoringAuth=\(isRestoringAuth)"
  }

  static func recordAuthStateInitialization(
    localProfile: Bool,
    savedSignedIn: Bool,
    email: String?,
    isRestoringAuth: Bool,
    sink: (String) -> Void
  ) {
    sink(
      authStateInitialized(
        localProfile: localProfile,
        savedSignedIn: savedSignedIn,
        email: email,
        isRestoringAuth: isRestoringAuth
      ))
  }

  static func authStateSaved(isSignedIn: Bool, email _: String?) -> String {
    "INTENTIVE AUTH: Saved auth state signedIn=\(isSignedIn)"
  }

  static func recordPersistedAuthState(
    isSignedIn: Bool,
    email: String?,
    sink: (String) -> Void
  ) {
    sink(authStateSaved(isSignedIn: isSignedIn, email: email))
  }
}
