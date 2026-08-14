import Foundation
import XCTest

@testable import Omi_Computer

final class OneAssistantChatContractTests: XCTestCase {
  func testLegacyAppIdentityIsIgnoredByChatSessionContract() throws {
    let payload = Data(
      #"{"id":"session-1","title":"New Chat","app_id":"legacy-marketplace-app","message_count":0,"starred":false}"#.utf8
    )

    let session = try JSONDecoder().decode(ChatSession.self, from: payload)
    let encoded = try JSONEncoder().encode(session)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertNil(object["app_id"])
  }
}
