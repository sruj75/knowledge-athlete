import Foundation

@MainActor
struct ExplicitSignOutAction {
  private let signOut: () async throws -> Void

  init(
    signOut: @escaping () async throws -> Void = { try await AuthService.shared.signOut() }
  ) {
    self.signOut = signOut
  }

  @discardableResult
  func perform() -> Task<Void, Never> {
    return Task { @MainActor in
      try? await signOut()
    }
  }
}
