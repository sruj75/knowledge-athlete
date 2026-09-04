import XCTest

@testable import Omi_Computer

final class AuthTokenDecodingTests: XCTestCase {
  func testDecodeJWTPayloadHandlesBase64URLWithoutPadding() throws {
    let jwt = makeJWT(payload: [
      "email": "person@example.com",
      "given_name": "Ada",
      "family_name": "Lovelace",
    ])

    let payload = try XCTUnwrap(AuthService.decodeJWTPayload(jwt))

    XCTAssertEqual(payload["email"] as? String, "person@example.com")
    XCTAssertEqual(payload["given_name"] as? String, "Ada")
    XCTAssertEqual(payload["family_name"] as? String, "Lovelace")
  }

  func testLocalUserIdPrefersUserIdThenFallsBackToSubject() {
    XCTAssertEqual(
      AuthService.localUserId(fromIDToken: makeJWT(payload: ["user_id": "firebase-user", "sub": "subject-user"])),
      "firebase-user"
    )
    XCTAssertEqual(
      AuthService.localUserId(fromIDToken: makeJWT(payload: ["sub": "subject-user"])),
      "subject-user"
    )
    XCTAssertNil(AuthService.localUserId(fromIDToken: "not-a-jwt"))
  }

  func testDecodeFirebaseTokenResultAcceptsStringAndIntegerExpiresIn() throws {
    let stringExpiryData = try firebaseTokenResponse(
      idToken: makeJWT(payload: ["sub": "fallback-user"]),
      expiresIn: "7200",
      localId: "explicit-user"
    )
    let stringExpiry = try AuthService.decodeFirebaseTokenResult(from: stringExpiryData)
    XCTAssertTrue(stringExpiry.idToken.hasSuffix("."))
    XCTAssertEqual(stringExpiry.refreshToken, "refresh-token")
    XCTAssertEqual(stringExpiry.expiresIn, 7200)
    XCTAssertEqual(stringExpiry.localId, "explicit-user")

    let integerExpiryData = try firebaseTokenResponse(
      idToken: makeJWT(payload: ["sub": "fallback-user"]),
      expiresIn: 1800,
      localId: "explicit-user"
    )
    let integerExpiry = try AuthService.decodeFirebaseTokenResult(from: integerExpiryData)
    XCTAssertEqual(integerExpiry.expiresIn, 1800)
  }

  func testDecodeFirebaseTokenResultFallsBackToJwtUserIdAndCanRequireIt() throws {
    let data = try firebaseTokenResponse(
      idToken: makeJWT(payload: ["user_id": "jwt-user"]),
      expiresIn: "3600",
      localId: nil
    )

    let token = try AuthService.decodeFirebaseTokenResult(from: data, requireLocalId: true)

    XCTAssertEqual(token.localId, "jwt-user")
  }

  func testDecodeFirebaseTokenResultRejectsMissingRequiredLocalId() throws {
    let data = try firebaseTokenResponse(
      idToken: makeJWT(payload: ["email": "person@example.com"]),
      expiresIn: "3600",
      localId: nil
    )

    XCTAssertThrowsError(try AuthService.decodeFirebaseTokenResult(from: data, requireLocalId: true)) { error in
      guard case AuthError.invalidResponse = error else {
        return XCTFail("expected invalidResponse, got \(error)")
      }
    }
  }

  func testOAuthCallbackDiagnosticExcludesCodeAndState() throws {
    let url = try XCTUnwrap(URL(string: "heyintentive://auth/callback?code=secret-code&state=secret-state"))
    var emitted: [String] = []

    AuthLogPrivacy.recordCallbackReceived(url) { emitted.append($0) }

    XCTAssertEqual(emitted, ["INTENTIVE AUTH: Received OAuth callback"])
    XCTAssertFalse(emitted.joined().contains("secret-code"))
    XCTAssertFalse(emitted.joined().contains("secret-state"))
  }

  func testFirebaseResponseDiagnosticExcludesTokensAndPII() throws {
    let response = try JSONSerialization.data(withJSONObject: [
      "idToken": "secret-id-token",
      "refreshToken": "secret-refresh-token",
      "email": "person@example.com",
    ])

    let diagnostic = AuthLogPrivacy.responseFailure("Firebase signInWithIdp", 400, response)

    XCTAssertEqual(diagnostic, "INTENTIVE AUTH: Firebase signInWithIdp failed (HTTP 400)")
    XCTAssertFalse(diagnostic.contains("secret-id-token"))
    XCTAssertFalse(diagnostic.contains("secret-refresh-token"))
    XCTAssertFalse(diagnostic.contains("person@example.com"))
  }

  func testSuccessfulIDTokenDiagnosticExcludesDecodedProfilePII() throws {
    let idToken = makeJWT(payload: [
      "email": "person@example.com",
      "given_name": "Ada",
      "family_name": "Lovelace",
    ])
    let payload = try XCTUnwrap(AuthService.decodeJWTPayload(idToken))
    XCTAssertEqual(payload["email"] as? String, "person@example.com")

    let diagnostic = AuthLogPrivacy.idTokenProfileClaimsExtracted(payload)

    XCTAssertEqual(diagnostic, "INTENTIVE AUTH: Extracted profile claims from id_token")
    XCTAssertFalse(diagnostic.contains("person@example.com"))
    XCTAssertFalse(diagnostic.contains("Ada"))
    XCTAssertFalse(diagnostic.contains("Lovelace"))
  }

  func testAnalyticsIdentificationDiagnosticExcludesUserIdentifier() {
    var emitted: [String] = []

    AuthLogPrivacy.recordAnalyticsIdentification("firebase-user-secret") { emitted.append($0) }

    XCTAssertEqual(emitted, ["INTENTIVE ANALYTICS: Identified signed-in user"])
    XCTAssertFalse(emitted.joined().contains("firebase-user-secret"))
  }

  func testAuthStateInitializationDiagnosticExcludesSavedEmail() {
    var emitted: [String] = []

    AuthLogPrivacy.recordAuthStateInitialization(
      localProfile: false,
      savedSignedIn: true,
      email: "person@example.com",
      isRestoringAuth: true
    ) { emitted.append($0) }

    XCTAssertEqual(
      emitted,
      ["INTENTIVE AUTH: Initialized localProfile=false savedSignedIn=true isRestoringAuth=true"]
    )
    XCTAssertFalse(emitted.joined().contains("person@example.com"))
  }

  func testPersistedAuthStateDiagnosticExcludesSavedEmail() {
    var emitted: [String] = []

    AuthLogPrivacy.recordPersistedAuthState(
      isSignedIn: true,
      email: "person@example.com"
    ) { emitted.append($0) }

    XCTAssertEqual(emitted, ["INTENTIVE AUTH: Saved auth state signedIn=true"])
    XCTAssertFalse(emitted.joined().contains("person@example.com"))
  }

  func testSensitiveAuthLoggingCallSitesUsePrivacyBoundaryStaticTripwire() throws {
    let postHog = try productionSource("PostHogManager.swift")
    let app = try productionSource("OmiApp.swift")
    let ownerTransition = try productionSource("Auth/AuthOwnerTransition.swift")

    XCTAssertTrue(postHog.contains("AuthLogPrivacy.recordAnalyticsIdentification(uid, sink: log)"))
    XCTAssertFalse(postHog.contains(#"log("PostHog: Identified user \(uid)")"#))
    XCTAssertTrue(app.contains("AuthLogPrivacy.recordAuthStateInitialization("))
    XCTAssertFalse(app.contains("Initialized localProfile=%@ savedSignedIn=%@ email=%@"))
    XCTAssertTrue(app.contains("AuthLogPrivacy.recordCallbackReceived(url)"))
    XCTAssertFalse(app.contains("Received URL event: %@"))
    XCTAssertTrue(ownerTransition.contains("AuthLogPrivacy.recordPersistedAuthState("))
    XCTAssertFalse(ownerTransition.contains("Saved auth state - signedIn: %@, email: %@"))
  }

  private func firebaseTokenResponse(idToken: String, expiresIn: Any, localId: String?) throws -> Data {
    var json: [String: Any] = [
      "idToken": idToken,
      "refreshToken": "refresh-token",
      "expiresIn": expiresIn,
    ]
    if let localId {
      json["localId"] = localId
    }
    return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
  }

  private func makeJWT(payload: [String: Any]) -> String {
    let header = base64URL(["alg": "none", "typ": "JWT"])
    let payload = base64URL(payload)
    return "\(header).\(payload)."
  }

  private func productionSource(_ relativePath: String) throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")
      .appendingPathComponent(relativePath)
    // omi-test-quality: source-inspection -- static contract: privacy wiring complements behavioral sink coverage
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }

  private func base64URL(_ json: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    return
      data
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
