import XCTest

@testable import Omi_Computer

final class SignInIdentityPresentationTests: XCTestCase {
  func testSignInCopyNamesIntentiveAndBoundsTheLocalFirstPromise() {
    XCTAssertEqual(SignInIdentityPresentation.productName, "Intentive")
    XCTAssertEqual(SignInIdentityPresentation.headline, "A second brain you can trust")
    XCTAssertEqual(
      SignInIdentityPresentation.detail,
      "Your conversations and memories stay on this Mac. Intentive uses managed services when a feature needs them.")
    XCTAssertEqual(SignInIdentityPresentation.footer, "open source · local-first · pause anytime")
    XCTAssertFalse(SignInIdentityPresentation.allText.localizedCaseInsensitiveContains("Omi"))
    XCTAssertFalse(SignInIdentityPresentation.allText.localizedCaseInsensitiveContains("every conversation"))
  }

  func testOAuthReturnPageUsesIntentiveIdentityAndEscapesTheOwnedScheme() {
    let html = OAuthLoopbackCallbackServer.responseHTML(
      for: .success,
      appOpenURL: "heyintentive-dev://auth/callback?value=\"owned\"&next=<home>"
    )

    XCTAssertTrue(html.contains("<title>Signed in - Intentive</title>"))
    XCTAssertTrue(html.contains("return to Intentive"))
    XCTAssertTrue(html.contains("Opening Intentive…"))
    XCTAssertTrue(html.contains(">Open Intentive</a>"))
    XCTAssertTrue(
      html.contains(
        "href=\"heyintentive-dev://auth/callback?value=&quot;owned&quot;&amp;next=&lt;home&gt;\""))
    XCTAssertFalse(html.localizedCaseInsensitiveContains("Omi"))
  }
}
