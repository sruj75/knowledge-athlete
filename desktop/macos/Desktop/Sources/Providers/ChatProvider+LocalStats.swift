extension ChatProvider {
  func localChatMessageCount(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> Int {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw BridgeError.authMissing
    }
    let catalog = try await listLocalChatCatalog()
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else {
      throw BridgeError.authMissing
    }
    return catalog.chats.reduce(0) { $0 + $1.messageCount }
  }
}
