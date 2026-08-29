import Foundation

// MARK: - User Settings API

extension APIClient {

  /// Fetches user language preference
  func getUserLanguage(
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> UserLanguageResponse {
    return try await get(
      "v1/users/language",
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
  }

  /// Updates user language preference. The PATCH endpoint's response shape differs
  /// from GET's (`{status, single_language_mode}`, not `{language}`) — decoding into
  /// UserLanguageResponse here always threw ("data couldn't be read because it is
  /// missing") even though the backend had already saved the language, silently
  /// (pre-await-fix) or now visibly blocking the caller on a save that succeeded.
  @discardableResult
  func updateUserLanguage(
    _ language: String,
    expectedOwnerId: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async throws -> SetUserLanguageResponse {
    struct UpdateRequest: Encodable {
      let language: String
    }
    let body = UpdateRequest(language: language)
    return try await patch(
      "v1/users/language",
      body: body,
      expectedOwnerId: expectedOwnerId,
      authorizationSnapshot: authorizationSnapshot)
  }

  /// Deletes the authenticated user's account and all server data.
  func deleteAccount() async throws {
    try await delete("v1/users/delete-account")
  }

  /// Fetches server-controlled desktop update/banner policy.
  func getDesktopUpdatePolicy(currentBuild: Int?) async throws -> DesktopUpdatePolicyResponse {
    var endpoint = "v2/desktop/update-policy?platform=macos"
    if let currentBuild {
      endpoint += "&current_build=\(currentBuild)"
    }
    return try await get(endpoint, requireAuth: false)
  }

}

// MARK: - User Settings Models

/// User language response (GET /v1/users/language)
struct UserLanguageResponse: Codable {
  let language: String
}

/// Response shape for PATCH /v1/users/language — deliberately distinct from
/// UserLanguageResponse; the backend's set_user_language handler returns
/// {status, single_language_mode}, never {language}.
struct SetUserLanguageResponse: Codable {
  let status: String
  let single_language_mode: Bool
}

enum SubscriptionPlanType: String, Codable {
  case free
  case bounded
  case unlimited
}

enum SubscriptionStatusType: String, Codable {
  case active
  case onHold = "on_hold"
  case cancelled
  case failed
  case expired
  case inactive
}

struct BillingAvailability: Codable, Equatable, Sendable {
  enum Presentation: String, Codable, Sendable {
    case skip
    case checkout
  }

  static let disabled = BillingAvailability(
    checkoutEnabled: false,
    portalEnabled: false,
    presentation: .skip)

  let checkoutEnabled: Bool
  let portalEnabled: Bool
  let presentation: Presentation

  enum CodingKeys: String, CodingKey {
    case checkoutEnabled = "checkout_enabled"
    case portalEnabled = "portal_enabled"
    case presentation
  }
}

struct SubscriptionLimitsResponse: Codable {
  let transcriptionSeconds: Int?
  let wordsTranscribed: Int?
  let insightsGained: Int?
  let chatQuestionsPerMonth: Int?
  let chatCostUsdPerMonth: Double?

  enum CodingKeys: String, CodingKey {
    case transcriptionSeconds = "transcription_seconds"
    case wordsTranscribed = "words_transcribed"
    case insightsGained = "insights_gained"
    case chatQuestionsPerMonth = "chat_questions_per_month"
    case chatCostUsdPerMonth = "chat_cost_usd_per_month"
  }
}

struct UserSubscriptionInfo: Codable {
  let plan: SubscriptionPlanType
  let planName: String
  let offerId: String?
  let billingCustomerId: String?
  let billingSubscriptionId: String?
  let billingProductId: String?
  let entitlementPolicy: SubscriptionPlanType
  let status: SubscriptionStatusType
  let currentPeriodStart: Int?
  let currentPeriodEnd: Int?
  let features: [String]
  let cancelAtNextBillingDate: Bool
  let billingInterval: String?
  let priceString: String?
  let providerUpdatedAt: Int?
  let limits: SubscriptionLimitsResponse

  enum CodingKeys: String, CodingKey {
    case plan, status, features, limits
    case planName = "plan_name"
    case offerId = "offer_id"
    case billingCustomerId = "billing_customer_id"
    case billingSubscriptionId = "billing_subscription_id"
    case billingProductId = "billing_product_id"
    case entitlementPolicy = "entitlement_policy"
    case currentPeriodStart = "current_period_start"
    case currentPeriodEnd = "current_period_end"
    case cancelAtNextBillingDate = "cancel_at_next_billing_date"
    case billingInterval = "billing_interval"
    case priceString = "price_string"
    case providerUpdatedAt = "provider_updated_at"
  }
}

struct SubscriptionPriceOption: Codable, Identifiable {
  let id: String
  let title: String
  let description: String?
  let priceString: String
  let interval: String

  enum CodingKeys: String, CodingKey {
    case id, title, description, interval
    case priceString = "price_string"
  }
}

struct SubscriptionPlanOption: Codable, Identifiable {
  let id: String
  let title: String
  let subtitle: String?
  let description: String?
  let eyebrow: String?
  let features: [String]
  let prices: [SubscriptionPriceOption]

  init(
    id: String, title: String, subtitle: String? = nil, description: String? = nil, eyebrow: String? = nil,
    features: [String] = [], prices: [SubscriptionPriceOption] = []
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.description = description
    self.eyebrow = eyebrow
    self.features = features
    self.prices = prices
  }
}

struct UserSubscriptionResponse: Codable {
  let subscription: UserSubscriptionInfo
  let transcriptionSecondsUsed: Int
  let transcriptionSecondsLimit: Int
  let wordsTranscribedUsed: Int
  let wordsTranscribedLimit: Int
  let insightsGainedUsed: Int
  let insightsGainedLimit: Int
  let availablePlans: [SubscriptionPlanOption]
  let billingAvailability: BillingAvailability
  let showSubscriptionUI: Bool

  enum CodingKeys: String, CodingKey {
    case subscription
    case transcriptionSecondsUsed = "transcription_seconds_used"
    case transcriptionSecondsLimit = "transcription_seconds_limit"
    case wordsTranscribedUsed = "words_transcribed_used"
    case wordsTranscribedLimit = "words_transcribed_limit"
    case insightsGainedUsed = "insights_gained_used"
    case insightsGainedLimit = "insights_gained_limit"
    case availablePlans = "available_plans"
    case billingAvailability = "billing_availability"
    case showSubscriptionUI = "show_subscription_ui"
  }

  // Defensive decode: only `subscription` is required. The usage counters and
  // plan catalog default when absent so a backend that's behind on schema and
  // omits newer fields like `memories_created_used` doesn't blank the entire
  // Plan & Usage page with "Failed to load plan information."
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    subscription = try c.decode(UserSubscriptionInfo.self, forKey: .subscription)
    transcriptionSecondsUsed = try c.decodeIfPresent(Int.self, forKey: .transcriptionSecondsUsed) ?? 0
    transcriptionSecondsLimit = try c.decodeIfPresent(Int.self, forKey: .transcriptionSecondsLimit) ?? 0
    wordsTranscribedUsed = try c.decodeIfPresent(Int.self, forKey: .wordsTranscribedUsed) ?? 0
    wordsTranscribedLimit = try c.decodeIfPresent(Int.self, forKey: .wordsTranscribedLimit) ?? 0
    insightsGainedUsed = try c.decodeIfPresent(Int.self, forKey: .insightsGainedUsed) ?? 0
    insightsGainedLimit = try c.decodeIfPresent(Int.self, forKey: .insightsGainedLimit) ?? 0
    availablePlans = try c.decodeIfPresent([SubscriptionPlanOption].self, forKey: .availablePlans) ?? []
    billingAvailability =
      try c.decodeIfPresent(BillingAvailability.self, forKey: .billingAvailability) ?? .disabled
    showSubscriptionUI = try c.decodeIfPresent(Bool.self, forKey: .showSubscriptionUI) ?? true
  }
}

struct CheckoutSessionResponse: Codable {
  let url: String
  let sessionId: String

  enum CodingKeys: String, CodingKey {
    case url
    case sessionId = "session_id"
  }
}

struct CustomerPortalResponse: Codable {
  let url: String
}

/// Trial metadata from `/v1/users/me/trial` (Python backend) — timing info for countdown UI
struct TrialMetadataResponse: Codable {
  let trialStartedAt: Int?
  let trialEndsAt: Int?
  let trialRemainingSeconds: Int
  let trialExpired: Bool
  let trialDurationSeconds: Int
  let trialFeatures: [String]
  let planAfterTrial: String

  enum CodingKeys: String, CodingKey {
    case trialStartedAt = "trial_started_at"
    case trialEndsAt = "trial_ends_at"
    case trialRemainingSeconds = "trial_remaining_seconds"
    case trialExpired = "trial_expired"
    case trialDurationSeconds = "trial_duration_seconds"
    case trialFeatures = "trial_features"
    case planAfterTrial = "plan_after_trial"
  }
}

// MARK: - Desktop Update Policy Models

struct DesktopUpdatePolicyResponse: Decodable, Equatable, Sendable {
  static let stableManualDownloadURL = URL(
    string: "https://github.com/sruj75/knowledge-athlete/releases/latest")!

  enum Severity: String, Codable, Sendable {
    case none
    case banner
    case required
  }

  let id: String
  let active: Bool
  let severity: Severity
  let maximumBuildNumber: Int?
  let latestBuildNumber: Int?
  let title: String?
  let message: String?
  let ctaText: String
  let downloadURL: String
  let canDismiss: Bool

  enum CodingKeys: String, CodingKey {
    case id, active, severity, title, message
    case maximumBuildNumber = "maximum_build_number"
    case latestBuildNumber = "latest_build_number"
    case ctaText = "cta_text"
    case downloadURL = "download_url"
    case canDismiss = "can_dismiss"
  }

  init(
    id: String,
    active: Bool,
    severity: Severity,
    maximumBuildNumber: Int?,
    latestBuildNumber: Int?,
    title: String?,
    message: String?,
    ctaText: String,
    downloadURL: String,
    canDismiss: Bool
  ) {
    self.id = id
    self.active = active
    self.severity = severity
    self.maximumBuildNumber = maximumBuildNumber
    self.latestBuildNumber = latestBuildNumber
    self.title = title
    self.message = message
    self.ctaText = ctaText
    self.downloadURL = Self.resolvedDownloadURL(from: downloadURL).absoluteString
    self.canDismiss = canDismiss
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = Self.nonEmptyString(try? container.decode(String.self, forKey: .id)) ?? "current"
    let active = (try? container.decode(Bool.self, forKey: .active)) ?? false
    let severity =
      (try? container.decode(String.self, forKey: .severity))
      .flatMap(Severity.init(rawValue:)) ?? .none
    let maximumBuildNumber = try? container.decode(Int.self, forKey: .maximumBuildNumber)
    let latestBuildNumber = try? container.decode(Int.self, forKey: .latestBuildNumber)
    let title = Self.nonEmptyString(try? container.decode(String.self, forKey: .title))
    let message = Self.nonEmptyString(try? container.decode(String.self, forKey: .message))
    let ctaText =
      Self.nonEmptyString(try? container.decode(String.self, forKey: .ctaText))
      ?? "Download latest"
    let downloadURL = (try? container.decode(String.self, forKey: .downloadURL)) ?? ""
    let canDismiss = (try? container.decode(Bool.self, forKey: .canDismiss)) ?? true

    self.init(
      id: id,
      active: active,
      severity: severity,
      maximumBuildNumber: maximumBuildNumber,
      latestBuildNumber: latestBuildNumber,
      title: title,
      message: message,
      ctaText: ctaText,
      downloadURL: downloadURL,
      canDismiss: canDismiss
    )
  }

  static func resolvedDownloadURL(from candidate: String?) -> URL {
    guard let candidate = nonEmptyString(candidate),
      let url = URL(string: candidate),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    else {
      return stableManualDownloadURL
    }
    return url
  }

  private static func nonEmptyString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var isRequired: Bool {
    active && severity == .required
  }
}
