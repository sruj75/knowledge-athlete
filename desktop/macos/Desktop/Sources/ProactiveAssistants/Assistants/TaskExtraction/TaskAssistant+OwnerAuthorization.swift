import Foundation

extension TaskAssistant {
  func requireCurrentAuthorization(
    _ authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) throws {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw LocalMutationAuthorizationError.revoked
    }
  }
}
