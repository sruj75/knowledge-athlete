extension RewindIndexer {
  func getCurrentOwnerStats() async -> (total: Int, indexed: Int, storageSize: Int64)? {
    guard let authorizationSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      return nil
    }
    return await getStats(authorizationSnapshot: authorizationSnapshot)
  }
}
