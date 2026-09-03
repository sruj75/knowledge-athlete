import XCTest

@testable import Omi_Computer

@MainActor
final class OnboardingFlowTests: XCTestCase {
  func testActiveFlowContainsOnlyRetainedStages() {
    XCTAssertEqual(
      SBOnboardingModel.Step.allCases,
      [
        .promise, .name, .howHeard, .language, .mic, .systemAudio, .screen,
        .accessibility, .shortcutOpen, .shortcutTalk, .screenDemo, .capture,
      ]
    )
  }

  func testRetiredStagesHaveNoPersistedProgressKeys() {
    let normalized = OnboardingFlow.persistedStateKeys.map { $0.lowercased() }
    for retiredTerm in ["automation", "fulldisk", "filescan", "datasource", "export", "connector", "graph"] {
      XCTAssertFalse(
        normalized.contains(where: { $0.contains(retiredTerm) }),
        "retired onboarding state must not persist: \(retiredTerm)"
      )
    }
  }

  func testPersistedStateClearingIncludesActiveSecondBrainResumeState() {
    XCTAssertTrue(OnboardingFlow.persistedStateKeys.contains("sbOnboardingResumeStep"))
    XCTAssertFalse(OnboardingFlow.persistedStateKeys.contains("onboardingRole"))
  }

  func testRetainedStepGraphDoesNotDependOnAdjacentRawValues() {
    XCTAssertEqual(SBOnboardingModel.Step.language.next, .mic)
    XCTAssertEqual(SBOnboardingModel.Step.mic.previous, .language)
    XCTAssertEqual(SBOnboardingModel.Step.capture.next, nil)
    XCTAssertEqual(SBOnboardingModel.Step.promise.previous, nil)
  }

  func testLegacyRoleResumeMarkerMigratesToMicrophone() {
    XCTAssertEqual(SBOnboardingModel.Step.resumeTarget(forPersistedRawValue: 4), .mic)
  }

  func testBeginResumesFromEveryRetainedStageMarker() {
    let defaults = UserDefaults.standard
    let previous = defaults.object(forKey: SBOnboardingModel.resumeStepKey)
    var retainedAppStates: [AppState] = []
    var retainedModels: [SBOnboardingModel] = []
    defer {
      retainedModels.removeAll()
      retainedAppStates.removeAll()
      if let previous {
        defaults.set(previous, forKey: SBOnboardingModel.resumeStepKey)
      } else {
        defaults.removeObject(forKey: SBOnboardingModel.resumeStepKey)
      }
    }

    for expected in SBOnboardingModel.Step.allCases {
      defaults.set(expected.rawValue, forKey: SBOnboardingModel.resumeStepKey)
      let appState = AppState()
      let model = SBOnboardingModel(
        appState: appState,
        chatProvider: ChatProvider(),
        stepResolver: { $0 },
        onComplete: nil)

      model.begin()

      XCTAssertEqual(model.step, expected, "resume marker \(expected.rawValue)")
      retainedAppStates.append(appState)
      retainedModels.append(model)
    }
  }

  func testSecondBrainProceedActionsUseDefaultActionKeyboardShortcut() throws {
    let source = try desktopSourceFile("Onboarding/SecondBrain/SBOnboardingView.swift")
    XCTAssertTrue(source.contains("SBInkButton(title: SBOnboardingIdentityCopy.setupAction, isDefaultAction: true)"))
    XCTAssertTrue(source.contains("Text(\"Continue →\")"))
    XCTAssertTrue(source.contains(".keyboardShortcut(.defaultAction)"))
  }

  func testSecondBrainCaptureDefaultsToMeetings() throws {
    let source = try desktopSourceFile("Onboarding/SecondBrain/SBOnboardingView.swift")
    let defaultChoice = try XCTUnwrap(
      source.range(of: "model.capture(SBOnboardingModel.defaultCaptureSelection)"))
    let continuousChoice = try XCTUnwrap(source.range(of: "model.capture(.continuous)"))
    XCTAssertLessThan(defaultChoice.lowerBound, continuousChoice.lowerBound)
  }

  private func desktopSourceFile(_ relativePath: String) throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")
      .appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
