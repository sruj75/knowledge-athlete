import Foundation

struct AIUserProfileResponse: Codable {
  let profileText: String
  let generatedAt: Date
  let dataSourcesUsed: Int

  enum CodingKeys: String, CodingKey {
    case profileText = "profile_text"
    case generatedAt = "generated_at"
    case dataSourcesUsed = "data_sources_used"
  }
}

extension APIClient {
  func syncAIUserProfile(profileText: String, generatedAt: Date, dataSourcesUsed: Int) async throws {
    struct SyncRequest: Encodable {
      let profile_text: String
      let generated_at: String
      let data_sources_used: Int
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let body = SyncRequest(
      profile_text: profileText,
      generated_at: formatter.string(from: generatedAt),
      data_sources_used: dataSourcesUsed
    )

    let _: AIUserProfileResponse = try await patch("v1/users/ai-profile", body: body)
  }
}
