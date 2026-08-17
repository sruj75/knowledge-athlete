import XCTest

@testable import Omi_Computer

private final class PermissionGrantFlag: @unchecked Sendable {
  var value = false
}

@MainActor
final class OnboardingPermissionBehaviorTests: XCTestCase {
  func testEveryInjectedNativePermissionBoundaryAdvancesWithoutStartingCapture() {
    let permissionCases: [(key: String, step: SBOnboardingModel.Step, next: SBOnboardingModel.Step)] = [
      ("microphone", .mic, .systemAudio),
      ("system_audio", .systemAudio, .screen),
      ("screen_recording", .screen, .accessibility),
      ("accessibility", .accessibility, .shortcutOpen),
    ]
    let transcriptionIntent = AssistantSettings.shared.transcriptionEnabled
    let screenIntent = AssistantSettings.shared.screenAnalysisEnabled
    let monitoring = ProactiveAssistantsPlugin.shared.isMonitoring

    for permissionCase in permissionCases {
      let appState = AppState()
      let granted = PermissionGrantFlag()
      var checks: [String] = []
      var requests: [String] = []
      var primeCount = 0
      var effects: [SBOnboardingModel.PermissionEffect] = []
      let model = SBOnboardingModel(
        appState: appState,
        chatProvider: ChatProvider(),
        stepResolver: { $0 },
        permissionRefresher: { checks.append($0) },
        permissionRequester: { requests.append($0) },
        permissionGranted: { _ in granted.value },
        screenCapturePrimer: { primeCount += 1 },
        permissionEffectRecorder: { effects.append($0) },
        onComplete: nil)
      model.step = permissionCase.step

      model.requestPerm(permissionCase.key)
      granted.value = true
      model.requestPerm(permissionCase.key)

      XCTAssertEqual(checks, [permissionCase.key, permissionCase.key])
      XCTAssertEqual(requests, [permissionCase.key])
      XCTAssertEqual(model.permState(permissionCase.key), .on)
      XCTAssertEqual(model.step, permissionCase.next)
      XCTAssertFalse(appState.isTranscribing)
      XCTAssertEqual(AssistantSettings.shared.transcriptionEnabled, transcriptionIntent)
      XCTAssertEqual(AssistantSettings.shared.screenAnalysisEnabled, screenIntent)
      XCTAssertEqual(ProactiveAssistantsPlugin.shared.isMonitoring, monitoring)
      let primesScreen = ["system_audio", "screen_recording"].contains(permissionCase.key)
      XCTAssertEqual(primeCount, primesScreen ? 1 : 0)
      var expectedEffects: [SBOnboardingModel.PermissionEffect] = [
        .checked(permissionCase.key), .requested(permissionCase.key),
        .checked(permissionCase.key), .granted(permissionCase.key),
      ]
      if primesScreen { expectedEffects.append(.primedScreenCapture) }
      expectedEffects.append(.advanced(from: permissionCase.step, to: permissionCase.next))
      XCTAssertEqual(effects, expectedEffects)
    }
  }

  func testSystemAudioConsentUsesTheRealTapResult() async {
    let appState = AppState()
    let deniedModel = SBOnboardingModel(
      appState: appState,
      chatProvider: ChatProvider(),
      systemAudioPrimer: { _ in false },
      onComplete: nil)

    let denied = await deniedModel.resolveSystemAudioConsent()
    XCTAssertFalse(denied)
    let grantedModel = SBOnboardingModel(
      appState: appState,
      chatProvider: ChatProvider(),
      systemAudioPrimer: { _ in true },
      onComplete: nil)
    let granted = await grantedModel.resolveSystemAudioConsent()
    XCTAssertTrue(granted)
  }

  func testScreenRecordingPrimeRunsOnceAndDoesNotRetainCapture() {
    let appState = AppState()
    var primeCount = 0
    let model = SBOnboardingModel(
      appState: appState,
      chatProvider: ChatProvider(),
      screenCapturePrimer: { primeCount += 1 },
      onComplete: nil)

    model.setPermOn("screen_recording")
    model.setPermOn("screen_recording")

    XCTAssertEqual(primeCount, 1)
  }

  func testLeavingPermissionStepCancelsLateGrantPollBeforeItCanPrimeCapture() async {
    let appState = AppState()
    let permissionGranted = PermissionGrantFlag()
    var primeCount = 0
    let model = SBOnboardingModel(
      appState: appState,
      chatProvider: ChatProvider(),
      stepResolver: { $0 },
      permissionRefresher: { _ in },
      permissionGranted: { _ in permissionGranted.value },
      screenCapturePrimer: { primeCount += 1 },
      onComplete: nil)
    model.step = .screen

    model.pollPermission("screen_recording")
    XCTAssertNotNil(model.pollTasks["screen_recording"])

    model.advance(userAnswer: "Skip", to: .accessibility)
    permissionGranted.value = true
    await Task.yield()

    XCTAssertNil(model.pollTasks["screen_recording"])
    XCTAssertEqual(primeCount, 0)
    XCTAssertEqual(model.scrState, .ask)
  }

  func testAccessibilityCopyNamesGlobalPTTAndPreciseRewindFocusTargeting() throws {
    let model = SBOnboardingModel(appState: AppState(), chatProvider: ChatProvider(), onComplete: nil)
    let copy = model.message(for: .accessibility)

    XCTAssertTrue(copy.contains("global push-to-talk"))
    XCTAssertTrue(copy.contains("Rewind and Focus"))
    XCTAssertTrue(copy.contains("exact window"))
    XCTAssertFalse(copy.contains("click and type"))

    let viewSource = try desktopSourceFile("Onboarding/SecondBrain/SBOnboardingView.swift")
    XCTAssertFalse(viewSource.contains("click/type"))
  }

  /// Static absence tripwire: the retired live Automation/FDA consent surface
  /// must not regain an opener, entitlement, usage string, or flow stage.
  func testRetiredAutomationAndFullDiskConsentSurfacesStayAbsent() throws {
    let permissionSource = try desktopSourceFile("AppState/AppState+Permissions.swift")
    let plist = try desktopFile("Info.plist")
    let entitlements = try desktopFile("Omi.entitlements")

    XCTAssertFalse(permissionSource.contains("Privacy_Automation"))
    XCTAssertFalse(plist.contains("NSAppleEventsUsageDescription"))
    XCTAssertFalse(entitlements.contains("com.apple.security.automation.apple-events"))
    XCTAssertFalse(SBOnboardingModel.Step.allCases.map(String.init(describing:)).contains("automation"))
    XCTAssertFalse(SBOnboardingModel.Step.allCases.map(String.init(describing:)).contains("fullDisk"))
  }

  private func desktopSourceFile(_ relativePath: String) throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")
      .appendingPathComponent(relativePath)
    // omi-test-quality: source-inspection -- static contract: retired Automation and false permission copy must remain absent from shipping source
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }

  private func desktopFile(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }
}
