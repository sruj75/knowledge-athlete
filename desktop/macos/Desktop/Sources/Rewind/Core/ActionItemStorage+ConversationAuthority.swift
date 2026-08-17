@preconcurrency import GRDB

extension ActionItemStorage {
  /// Transaction-scoped seam used by conversation authority for exact-source cleanup.
  static func deleteExactConversationSource(
    in database: Database,
    conversationId: String
  ) throws {
    try database.execute(
      sql: "DELETE FROM action_items WHERE conversationId = ?",
      arguments: [conversationId])
  }

  /// Transaction-scoped seam used by a local conversation merge.
  static func reassignExactConversationSource(
    in database: Database,
    from sourceConversationId: String,
    to replacementConversationId: String
  ) throws {
    try database.execute(
      sql: "UPDATE action_items SET conversationId = ? WHERE conversationId = ?",
      arguments: [replacementConversationId, sourceConversationId])
  }
}
