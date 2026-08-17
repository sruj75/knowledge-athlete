import XCTest

@testable import Omi_Computer

final class APIClientUserProfileDecodingTests: XCTestCase {
  private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)

      let isoWithFractional = ISO8601DateFormatter()
      isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = isoWithFractional.date(from: value) {
        return date
      }

      let iso = ISO8601DateFormatter()
      if let date = iso.date(from: value) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid ISO8601 date: \(value)")
    }
    return decoder
  }

  func testUserProfileRequiresUidButToleratesOptionalProfileFields() throws {
    let json = Data(
      """
      {
        "uid": "user-123",
        "name": "Desktop User",
        "unexpected_profile_field": "ignored"
      }
      """.utf8)

    let profile = try makeDecoder().decode(UserProfileResponse.self, from: json)

    XCTAssertEqual(profile.uid, "user-123")
    XCTAssertEqual(profile.name, "Desktop User")
    XCTAssertNil(profile.email)
    XCTAssertNil(profile.timeZone)
  }

  func testUserProfileStillFailsWithoutUid() {
    let json = Data(
      """
      {
        "name": "Legacy User"
      }
      """.utf8)

    XCTAssertThrowsError(try makeDecoder().decode(UserProfileResponse.self, from: json))
  }
}
