import XCTest

@testable import Omi_Computer

@MainActor
final class OnboardingAnswerAuthorityTests: XCTestCase {
  private var previousGivenName: String?
  private var previousFamilyName: String?
  private var previousOwnerID: String?
  private var previousImpersonation = false
  private var previousHooks = AuthService.NameAuthorityHooks.live

  override func setUp() async throws {
    let defaults = UserDefaults.standard
    previousGivenName = defaults.string(forKey: .authGivenName)
    previousFamilyName = defaults.string(forKey: .authFamilyName)
    previousOwnerID = defaults.string(forKey: .authUserId)
    previousImpersonation = defaults.bool(forKey: .authIsImpersonating)
    previousHooks = AuthService.shared.nameAuthorityHooks
    defaults.removeObject(forKey: .authGivenName)
    defaults.removeObject(forKey: .authFamilyName)
    defaults.set(false, forKey: .authIsImpersonating)
  }

  override func tearDown() async throws {
    let defaults = UserDefaults.standard
    restore(previousGivenName, key: .authGivenName, in: defaults)
    restore(previousFamilyName, key: .authFamilyName, in: defaults)
    restore(previousOwnerID, key: .authUserId, in: defaults)
    defaults.set(previousImpersonation, forKey: .authIsImpersonating)
    AuthService.shared.nameAuthorityHooks = previousHooks
  }

  func testNameRevisionWritesThroughOwnerBoundFirebaseAndLocalAuthorityOnly() async {
    let ownerID = "onboarding-owner-\(UUID().uuidString)"
    UserDefaults.standard.set(ownerID, forKey: .authUserId)
    var firebaseWrites: [(String, String?)] = []
    AuthService.shared.nameAuthorityHooks = .init(
      updateFirebaseDisplayName: { name, expectedOwnerID in
        firebaseWrites.append((name, expectedOwnerID))
      },
      firebaseDisplayName: nil)

    let model = SBOnboardingModel(
      appState: AppState(),
      chatProvider: ChatProvider(),
      nameWriter: { name, expectedOwnerID, authorizationSnapshot in
        await AuthService.shared.updateGivenName(
          name,
          expectedOwnerID: expectedOwnerID,
          authorizationSnapshot: authorizationSnapshot)
      },
      onComplete: nil)
    model.step = .name
    model.nameDraft = "First Draft"
    model.answerName()
    model.step = .name
    model.nameDraft = "Final Name"
    model.answerName()
    await model.waitForPendingNameWrite()

    XCTAssertEqual(firebaseWrites.map(\.0), ["First Draft", "Final Name"])
    XCTAssertEqual(firebaseWrites.map(\.1), [ownerID, ownerID])
    XCTAssertEqual(AuthService.shared.givenName, "Final")
    XCTAssertEqual(AuthService.shared.familyName, "Name")
  }

  func testOwnerSwitchRejectsAStaleNameProjection() async {
    let firstOwner = "first-owner-\(UUID().uuidString)"
    let secondOwner = "second-owner-\(UUID().uuidString)"
    UserDefaults.standard.set(firstOwner, forKey: .authUserId)
    AuthService.shared.nameAuthorityHooks = .init(
      updateFirebaseDisplayName: { _, _ in
        UserDefaults.standard.set(secondOwner, forKey: .authUserId)
      },
      firebaseDisplayName: nil)

    await AuthService.shared.updateGivenName("Stale Owner", expectedOwnerID: firstOwner)

    XCTAssertTrue(AuthService.shared.givenName.isEmpty)
    XCTAssertTrue(AuthService.shared.familyName.isEmpty)
  }

  func testLanguageSelectionIsLocalAndAdvancesDirectlyToMicrophone() {
    var localWrites: [[String]] = []
    let appState = AppState()
    let model = SBOnboardingModel(
      appState: appState,
      chatProvider: ChatProvider(),
      languageWriter: { localWrites.append($0) },
      stepResolver: { $0 },
      onComplete: nil)
    model.step = .language

    model.pickLanguage(code: "es", name: "Spanish")

    XCTAssertEqual(localWrites, [["es"]])
    XCTAssertEqual(model.languageName, "Spanish")
    XCTAssertEqual(model.step, .mic)
  }

  private func restore(_ value: String?, key: DefaultsKey, in defaults: UserDefaults) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }
}
