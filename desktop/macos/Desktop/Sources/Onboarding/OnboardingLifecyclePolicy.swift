import Foundation

enum DirectOnboardingBypassAction: Equatable {
  case none
  case markCompletionOnly
}

enum DirectOnboardingBypassPolicy {
  static func action(arguments: [String]) -> DirectOnboardingBypassAction {
    arguments.contains("--skip-onboarding") ? .markCompletionOnly : .none
  }
}

/// The published `--skip-onboarding` launch argument remains a direct completion
/// bypass. It deliberately does not execute the visible Skip exit policy.
func shouldSkipOnboarding(arguments: [String] = CommandLine.arguments) -> Bool {
  DirectOnboardingBypassPolicy.action(arguments: arguments) == .markCompletionOnly
}

enum OnboardingWindowLifecyclePolicy {
  static func shouldTerminateAfterLastWindowClosed(hasCompletedOnboarding: Bool) -> Bool {
    !hasCompletedOnboarding
  }
}

enum AppKitRelaunchAtLogoutDecision: Equatable {
  case disable
  case enable
}

enum AppKitRelaunchAtLogoutPolicy {
  static func decision(
    isProductionBundle: Bool,
    hasCompletedOnboarding: Bool
  ) -> AppKitRelaunchAtLogoutDecision {
    isProductionBundle && hasCompletedOnboarding ? .enable : .disable
  }
}

enum OnboardingSetupAuthorityNode: String, Hashable {
  case completedFlag = "completed_flag"
  case stage = "sb_stage"
  case persistedResume = "persisted_resume"
  case setupJournal = "setup_journal"
}

struct OnboardingSetupStateDisagreement: Equatable, Hashable {
  let source: OnboardingSetupAuthorityNode
  let target: OnboardingSetupAuthorityNode
  let direction: String
}

struct OnboardingSetupAuthorityResolution: Equatable {
  let hasCompletedOnboarding: Bool
  let disagreements: [OnboardingSetupStateDisagreement]
}

enum OnboardingSetupAuthorityPolicy {
  static func resolve(
    hasCompletedOnboarding: Bool,
    hasActiveStage: Bool,
    hasPersistedResume: Bool,
    hasActiveJournal: Bool
  ) -> OnboardingSetupAuthorityResolution {
    guard hasCompletedOnboarding else {
      return OnboardingSetupAuthorityResolution(
        hasCompletedOnboarding: false,
        disagreements: [])
    }

    var disagreements: [OnboardingSetupStateDisagreement] = []
    if hasActiveStage {
      disagreements.append(
        .init(
          source: .completedFlag,
          target: .stage,
          direction: "completed_flag_with_active_stage"))
    }
    if hasPersistedResume {
      disagreements.append(
        .init(
          source: .completedFlag,
          target: .persistedResume,
          direction: "completed_flag_with_resume_state"))
    }
    if hasActiveJournal {
      disagreements.append(
        .init(
          source: .completedFlag,
          target: .setupJournal,
          direction: "completed_flag_with_active_journal"))
    }
    return OnboardingSetupAuthorityResolution(
      hasCompletedOnboarding: true,
      disagreements: disagreements)
  }
}
