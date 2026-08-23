import XCTest

@testable import Omi_Computer

@MainActor
final class RealtimeManagedAuthenticationTests: XCTestCase {
  private let legacyKeyNames = ["dev_openai_api_key", "dev_gemini_api_key"]

  func testLegacyCustomerKeyCannotStartSignedOutRealtimeSession() {
    let defaults = UserDefaults.standard
    let previousSignedIn = AuthService.shared.isSignedIn
    let previousOwner = defaults.object(forKey: .authUserId)
    let previousOverride = defaults.object(forKey: .automationOwnerOverride)
    defer {
      AuthService.shared.isSignedIn = previousSignedIn
      for keyName in legacyKeyNames { defaults.removeObject(forKey: keyName) }
      if let previousOwner {
        defaults.set(previousOwner, forKey: .authUserId)
      } else {
        defaults.removeObject(forKey: .authUserId)
      }
      if let previousOverride {
        defaults.set(previousOverride, forKey: .automationOwnerOverride)
      } else {
        defaults.removeObject(forKey: .automationOwnerOverride)
      }
    }

    for keyName in legacyKeyNames {
      defaults.set("legacy-customer-secret", forKey: keyName)
    }
    defaults.removeObject(forKey: .authUserId)
    defaults.removeObject(forKey: .automationOwnerOverride)
    AuthService.shared.isSignedIn = false

    let controller = RealtimeHubController()
    controller.prefetchedVoiceContextSessionID = "managed-auth-test-session"
    controller.prefetchedVoiceContextFreshnessIdentity = "managed-auth-test-freshness"
    controller.prefetchedVoiceContextOwnerScope = .signedOut
    controller.prefetchedVoiceContextSurface = .realtimeVoice()
    var startedDirectSession = false
    controller.testingSessionStartAfterDrain = { _, _, _ in
      startedDirectSession = true
      return true
    }

    controller.ensureWarm()

    XCTAssertFalse(startedDirectSession)
    XCTAssertNil(controller.session)
    XCTAssertFalse(controller.minting)
  }

  func testSignedInOwnerUsesManagedMintEvenWhenLegacyCustomerKeyExists() {
    let defaults = UserDefaults.standard
    let previousSignedIn = AuthService.shared.isSignedIn
    let previousOwner = defaults.object(forKey: .authUserId)
    let previousOverride = defaults.object(forKey: .automationOwnerOverride)
    defer {
      AuthService.shared.isSignedIn = previousSignedIn
      for keyName in legacyKeyNames { defaults.removeObject(forKey: keyName) }
      if let previousOwner {
        defaults.set(previousOwner, forKey: .authUserId)
      } else {
        defaults.removeObject(forKey: .authUserId)
      }
      if let previousOverride {
        defaults.set(previousOverride, forKey: .automationOwnerOverride)
      } else {
        defaults.removeObject(forKey: .automationOwnerOverride)
      }
    }

    for keyName in legacyKeyNames {
      defaults.set("legacy-customer-secret", forKey: keyName)
    }
    let ownerID = "managed-realtime-owner"
    defaults.set(ownerID, forKey: .authUserId)
    defaults.removeObject(forKey: .automationOwnerOverride)
    AuthService.shared.isSignedIn = true

    let controller = RealtimeHubController()
    let ownerScope = RealtimeHubOwnerScope.authenticated(ownerID)
    controller.prefetchedVoiceContextSessionID = "managed-auth-test-session"
    controller.prefetchedVoiceContextFreshnessIdentity = "managed-auth-test-freshness"
    controller.prefetchedVoiceContextOwnerScope = ownerScope
    controller.prefetchedVoiceContextSurface = .realtimeVoice()
    var startedDirectSession = false
    controller.testingSessionStartAfterDrain = { _, _, _ in
      startedDirectSession = true
      return true
    }

    controller.ensureWarm()

    XCTAssertFalse(startedDirectSession)
    XCTAssertNil(controller.session)
    XCTAssertTrue(controller.minting)
    XCTAssertTrue(HubAuth.managedEphemeral("fixture-token").reportsUsage)
    XCTAssertFalse(HubAuth.hermeticStub.reportsUsage)

    // Invalidate the unstructured mint before this hermetic test releases the
    // MainActor; the task will then fail its owner fence before any request.
    controller.mintGeneration &+= 1
    controller.minting = false
    controller.mintOwnerScope = nil
  }

  func testLocalProfileTransportPreparationRevokesAnEarlierManagedMint() {
    let controller = RealtimeHubController()
    controller.mintGeneration = 41
    controller.minting = true
    controller.mintOwnerScope = .authenticated("earlier-owner")

    controller.revokeManagedMintForLocalProfileTransportPreparation()

    XCTAssertEqual(controller.mintGeneration, 42)
    XCTAssertFalse(controller.minting)
    XCTAssertNil(controller.mintOwnerScope)
  }
}
