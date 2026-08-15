import Foundation

@MainActor
struct ExplicitSignOutAction {
  enum EntryPoint {
    case menuBar
    case settings
  }

  private let stopTranscription: () -> Void
  private let stopMonitoring: () -> Void
  private let signOut: () async throws -> Void

  init(
    stopTranscription: @escaping () -> Void = { AppState.current?.stopTranscription() },
    stopMonitoring: @escaping () -> Void = { ProactiveAssistantsPlugin.shared.stopMonitoring() },
    signOut: @escaping () async throws -> Void = { try await AuthService.shared.signOut() }
  ) {
    self.stopTranscription = stopTranscription
    self.stopMonitoring = stopMonitoring
    self.signOut = signOut
  }

  @discardableResult
  func perform(from entryPoint: EntryPoint) -> Task<Void, Never> {
    if entryPoint == .settings {
      stopTranscription()
    }
    stopMonitoring()
    return Task { @MainActor in
      try? await signOut()
    }
  }
}
