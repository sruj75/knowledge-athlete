import XCTest

@testable import Omi_Computer

final class UserFacingErrorPresentationTests: XCTestCase {
  func testHidesRawBackendDetailOnNonChatSurfaces() {
    let message = UserFacingErrorPresentation.message(
      for: APIError.httpError(statusCode: 404, detail: "route v1/internal-control was not found"),
      while: .dashboard
    )

    XCTAssertEqual(message, "Couldn't refresh the dashboard. Try again.")
    XCTAssertFalse(message.contains("internal-control"))
  }

  func testUsesSignInRecoveryForUnauthorizedRequests() {
    XCTAssertEqual(
      UserFacingErrorPresentation.message(for: APIError.unauthorized, while: .memories),
      "Please sign in again, then try once more."
    )
  }

  func testHidesDecodingDiagnostics() {
    let decodingError = DecodingError.keyNotFound(
      CodingKeys.example,
      .init(codingPath: [], debugDescription: "unexpected backend field")
    )

    XCTAssertEqual(
      UserFacingErrorPresentation.message(for: APIError.decodingError(decodingError), while: .screenshots),
      "Intentive received an unexpected response. Try again."
    )
  }

  func testUsesFinalIdentityForServiceStateErrors() {
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        for: APIError.httpError(statusCode: 409, detail: "conflict"),
        while: .tasks),
      "This changed while Intentive was updating. Refresh and try again."
    )
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        for: APIError.httpError(statusCode: 429, detail: "busy"),
        while: .tasks),
      "Intentive is busy right now. Try again in a moment."
    )
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        for: APIError.httpError(statusCode: 503, detail: "unavailable"),
        while: .tasks),
      "Intentive's service is unavailable right now. Try again."
    )
  }

  func testSanitizesStoredErrorCopyAtDisplayTime() {
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        from: "route v1/internal-control was not found (404)",
        while: .chatSessions
      ),
      "Couldn't load chats. Try again."
    )
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        from: "Didn't hear back from X. If you approved access, try again.",
        while: .tasks
      ),
      "Didn't hear back from X. If you approved access, try again."
    )
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        from: "Intentive needs access before it can continue.",
        while: .tasks
      ),
      "Intentive needs access before it can continue."
    )
  }

  func testProvidesNetworkRecovery() {
    XCTAssertEqual(
      UserFacingErrorPresentation.message(
        for: URLError(.notConnectedToInternet),
        while: .conversations
      ),
      "Check your connection and try again."
    )
  }
}

private enum CodingKeys: String, CodingKey {
  case example
}
