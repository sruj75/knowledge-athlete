import XCTest

@testable import Omi_Computer

final class ModelQoSTests: XCTestCase {
  private let tierKey = "modelQoS_activeTier"

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: tierKey)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: tierKey)
    super.tearDown()
  }

  // MARK: - Default tier

  func testDefaultTierIsPremium() {
    XCTAssertEqual(ModelQoS.activeTier, .premium)
  }

  // MARK: - Tier persistence

  func testSetTierPersistsToUserDefaults() {
    ModelQoS.activeTier = .max
    XCTAssertEqual(UserDefaults.standard.string(forKey: tierKey), "max")

    ModelQoS.activeTier = .premium
    XCTAssertEqual(UserDefaults.standard.string(forKey: tierKey), "premium")
  }

  func testInvalidUserDefaultsFallsBackToPremium() {
    UserDefaults.standard.set("invalid_tier", forKey: tierKey)
    XCTAssertEqual(ModelQoS.activeTier, .premium)
  }

  // MARK: - Claude models are tier-independent

  func testClaudeModelsIdenticalAcrossTiers() {
    for tier in ModelTier.allCases {
      ModelQoS.activeTier = tier
      XCTAssertEqual(ModelQoS.Claude.chat, "claude-sonnet-4-6")
      XCTAssertEqual(ModelQoS.Claude.floatingBar, "claude-sonnet-4-6")
    }
  }

  // MARK: - Chat uses Sonnet (user-facing)

  func testChatUsesSonnet() {
    XCTAssertEqual(ModelQoS.Claude.chat, "claude-sonnet-4-6")
  }

  // MARK: - Gemini models are tier-dependent (except embedding)

  func testGeminiPremiumUsesFlash() {
    ModelQoS.activeTier = .premium
    XCTAssertEqual(ModelQoS.Gemini.proactive, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.taskExtraction, "gemini-2.5-flash")
    XCTAssertEqual(ModelQoS.Gemini.insight, "gemini-2.5-flash")
  }

  func testGeminiMaxUsesPro() {
    ModelQoS.activeTier = .max
    XCTAssertEqual(ModelQoS.Gemini.proactive, "gemini-2.5-pro")
    XCTAssertEqual(ModelQoS.Gemini.taskExtraction, "gemini-2.5-pro")
    XCTAssertEqual(ModelQoS.Gemini.insight, "gemini-2.5-pro")
  }

  func testGeminiEmbeddingTierIndependent() {
    for tier in ModelTier.allCases {
      ModelQoS.activeTier = tier
      XCTAssertEqual(ModelQoS.Gemini.embedding, "gemini-embedding-001")
    }
  }

  // MARK: - Tier description

  func testTierDescription() {
    ModelQoS.activeTier = .premium
    XCTAssertEqual(ModelQoS.tierDescription, "Premium (cost-optimized)")

    ModelQoS.activeTier = .max
    XCTAssertEqual(ModelQoS.tierDescription, "Max (quality-optimized)")
  }

  // MARK: - Tier change notification

  func testTierChangePostsNotification() {
    let expectation = expectation(forNotification: .modelTierDidChange, object: nil)
    ModelQoS.activeTier = .max
    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Model count (4 unique model IDs across both tiers)

  func testFourUniqueModelIDs() {
    // Chat and floating use one Sonnet ID. Gemini contributes flash, pro, and
    // embedding across the two tiers.
    var allModels: Set<String> = []
    for tier in ModelTier.allCases {
      ModelQoS.activeTier = tier
      allModels.formUnion([
        ModelQoS.Claude.chat,
        ModelQoS.Claude.floatingBar,
        ModelQoS.Gemini.proactive,
        ModelQoS.Gemini.taskExtraction,
        ModelQoS.Gemini.insight,
        ModelQoS.Gemini.embedding,
      ])
    }
    XCTAssertEqual(allModels.count, 4, "Expected 4 unique model IDs across tiers: \(allModels)")
  }
}
