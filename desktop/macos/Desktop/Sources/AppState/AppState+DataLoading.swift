@preconcurrency import AVFoundation
import Combine
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
extension AppState {
  private var currentConversationQuery: ConversationListQuery {
    ConversationListQuery(
      starredOnly: showStarredOnly,
      date: selectedDateFilter,
      folderId: selectedFolderId
    )
  }

  /// Load owner-scoped local conversations through the single repository projection.
  func loadConversations() async {
    await conversationRepository.load(query: currentConversationQuery)
    NotificationCenter.default.post(name: .conversationsPageDidLoad, object: nil)
  }

  /// Refresh local authority for activation and Cmd+R.
  func refreshConversations() async {
    guard AuthState.shared.isSignedIn else { return }
    await conversationRepository.refresh(query: currentConversationQuery)
    NotificationCenter.default.post(name: .conversationsPageDidLoad, object: nil)
  }

  var canLoadMoreConversations: Bool {
    conversationRepository.hasMore
  }

  func loadMoreConversations() async {
    await conversationRepository.loadMore()
  }

  /// Optimistically update star state, then settle from the canonical mutation response.
  func setConversationStarred(_ conversationId: String, starred: Bool) async {
    do {
      try await conversationRepository.setStarred(id: conversationId, starred: starred)
    } catch {
      logError("Conversations: Failed to update starred state", error: error)
    }
  }

  /// Toggle starred filter and reload conversations
  func toggleStarredFilter() async {
    showStarredOnly.toggle()
    await loadConversations()
  }

  /// Set date filter and reload conversations
  func setDateFilter(_ date: Date?) async {
    selectedDateFilter = date
    await loadConversations()
  }

  /// Clear all filters and reload conversations
  func clearFilters() async {
    showStarredOnly = false
    selectedDateFilter = nil
    selectedFolderId = nil
    await loadConversations()
  }

  /// Set folder filter and reload conversations
  func setFolderFilter(_ folderId: String?) async {
    selectedFolderId = folderId
    await loadConversations()
  }

  // MARK: - Folder Management

  /// Load owner-scoped local folders. `fetch` remains a test seam.
  func loadFolders(fetch: (() async throws -> [Folder])? = nil) async {
    guard !isLoadingFolders else { return }

    isLoadingFolders = true
    let generation = ownerScopeGeneration

    do {
      let fetchedFolders: [Folder]
      if let fetch {
        fetchedFolders = try await fetch()
      } else {
        fetchedFolders = try await TranscriptionStorage.shared.conversationFolders().map {
          Folder(local: $0)
        }
      }
      // Owner fence: a previous account's in-flight response must not
      // repopulate folders after an account switch reset them.
      guard generation == ownerScopeGeneration else { return }
      folders = fetchedFolders
      log("Folders: Loaded \(fetchedFolders.count) folders")
    } catch {
      guard generation == ownerScopeGeneration else { return }
      logError("Folders: Failed to load", error: error)
    }

    isLoadingFolders = false
  }

  /// Create a new folder
  func createFolder(name: String, color: String? = nil) async -> Folder? {
    let generation = ownerScopeGeneration
    do {
      let record = try await TranscriptionStorage.shared.createConversationFolder(
        name: name,
        color: color ?? "#6B7280",
        authorization: try localConversationAuthorization())
      let folder = Folder(local: record)
      // Fence like loadFolders: an in-flight mutation must not repopulate the
      // next account's folders after an in-place account switch reset them.
      guard generation == ownerScopeGeneration else { return nil }
      folders.append(folder)
      log("Folders: Created folder '\(name)'")
      return folder
    } catch {
      logError("Folders: Failed to create folder", error: error)
      return nil
    }
  }

  /// Delete a folder
  func deleteFolder(_ folderId: String, moveToFolderId: String? = nil) async {
    let generation = ownerScopeGeneration
    do {
      try await TranscriptionStorage.shared.deleteConversationFolder(
        id: folderId,
        moveConversationsTo: moveToFolderId,
        authorization: try localConversationAuthorization())
      guard generation == ownerScopeGeneration else { return }
      folders.removeAll { $0.id == folderId }
      if selectedFolderId == folderId {
        selectedFolderId = nil
      }
      await loadConversations()
      await loadFolders()
      log("Folders: Deleted folder \(folderId)")
    } catch {
      logError("Folders: Failed to delete folder", error: error)
    }
  }

  /// Update a folder
  func updateFolder(_ folderId: String, name: String?, color: String?) async {
    let generation = ownerScopeGeneration
    do {
      guard let existing = folders.first(where: { $0.id == folderId }) else { return }
      let record = try await TranscriptionStorage.shared.updateConversationFolder(
        id: folderId,
        name: name ?? existing.name,
        color: color ?? existing.color,
        authorization: try localConversationAuthorization())
      let updated = Folder(local: record, conversationCount: existing.conversationCount)
      guard generation == ownerScopeGeneration else { return }
      if let index = folders.firstIndex(where: { $0.id == folderId }) {
        folders[index] = updated
      }
      log("Folders: Updated folder \(folderId)")
    } catch {
      logError("Folders: Failed to update folder", error: error)
    }
  }

  /// Move a conversation through the single conversation repository.
  func moveConversationToFolder(_ conversationId: String, folderId: String?) async -> Bool {
    do {
      try await conversationRepository.moveToFolder(id: conversationId, folderId: folderId)
      await loadFolders()
      log("Folders: Moved conversation \(conversationId) to folder \(folderId ?? "none")")
      return true
    } catch {
      logError("Folders: Failed to move conversation to folder", error: error)
      return false
    }
  }

  /// Optimistically update title, then settle from the canonical mutation response.
  func updateConversationTitle(_ conversationId: String, title: String) async -> Bool {
    do {
      let updated = try await conversationRepository.updateTitle(id: conversationId, title: title)
      _ = updated
      await loadConversations()
      ConversationDeferredPostProcessFlow.launch(
        conversationId: conversationId,
        postProcess: { id in
          await ConversationFinalizationService.shared.processCurrentWork(conversationId: id)
        },
        refresh: { await self.loadConversations() })
      return true
    } catch {
      logError("Conversations: Failed to update title", error: error)
      return false
    }
  }

  func loadConversationDetail(_ conversation: LocalConversation) async -> LocalConversation {
    (try? await conversationRepository.detail(id: conversation.id)) ?? conversation
  }

  func loadConversationDetail(id: String) async -> LocalConversation? {
    try? await conversationRepository.detail(id: id)
  }

  func retryConversationEnrichment(id: String) async -> LocalConversation? {
    do {
      _ = try await conversationRepository.retryEnrichment(id: id)
      await ConversationFinalizationService.shared.processEnrichmentWithoutDiscard(
        conversationId: id)
      return try await conversationRepository.detail(id: id)
    } catch {
      logError("Conversations: Failed to retry local enrichment", error: error)
      return nil
    }
  }

  func searchConversations(_ query: String) async throws -> [LocalConversation] {
    try await conversationRepository.search(text: query)
  }

  func cancelConversationSearch() {
    conversationRepository.cancelSearch()
  }

  func deleteConversation(_ conversationId: String) async -> Bool {
    do {
      try await conversationRepository.delete(id: conversationId)
      await loadFolders()
      return true
    } catch {
      logError("Conversations: Failed to delete conversation", error: error)
      return false
    }
  }

  private func localConversationAuthorization() throws -> LocalMutationAuthorization {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    return LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
  }

  /// Applies a conversation-scoped speaker label to one segment or all matching segments.
  func assignSpeakerToSegments(
    conversationId: String,
    segmentIds: [String],
    speakerName: String?,
    isUser: Bool
  ) async -> Bool {
    do {
      guard let detail = try await TranscriptionStorage.shared.conversationDetail(id: conversationId) else {
        return false
      }
      let resolvedIds = segmentIds.compactMap { target -> String? in
        if target.hasPrefix("#index:"), let index = Int(target.dropFirst(7)), detail.segments.indices.contains(index) {
          return detail.segments[index].segmentId
        }
        return target
      }
      guard
        let firstId = resolvedIds.first,
        let first = detail.segments.first(where: { $0.segmentId == firstId })
      else { return false }
      let sameSpeakerCount = detail.segments.filter { $0.speakerId == first.speakerId }.count
      let applyAll = Set(resolvedIds).count >= sameSpeakerCount
      let name = isUser ? "You" : speakerName ?? "Speaker"
      try await TranscriptionStorage.shared.setConversationSpeakerLabel(
        conversationId: conversationId,
        speakerId: first.speakerId,
        name: name,
        isUser: isUser,
        applyToExisting: applyAll,
        segmentIds: resolvedIds,
        authorization: try localConversationAuthorization())
      if detail.status != .recording {
        await refreshConversations()
        ConversationDeferredPostProcessFlow.launch(
          conversationId: conversationId,
          postProcess: { id in
            await ConversationFinalizationService.shared.processCurrentWork(conversationId: id)
          },
          refresh: { await self.refreshConversations() })
      } else {
        await refreshConversations()
      }
      return true
    } catch {
      logError("Conversations: Failed to assign a local speaker label", error: error)
      return false
    }
  }

  /// Save a custom name while recording and apply it to future segments with the same diarization ID.
  func nameLiveSpeaker(speakerId: Int, name: String) async -> Bool {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let conversationId = currentConversationId, !normalized.isEmpty else { return false }
    do {
      try await TranscriptionStorage.shared.setConversationSpeakerLabel(
        conversationId: conversationId,
        speakerId: speakerId,
        name: normalized,
        isUser: false,
        authorization: currentSessionAuthorization ?? localConversationAuthorization())
      liveSpeakerNames[speakerId] = normalized
      return true
    } catch {
      logError("Conversations: Failed to name live speaker", error: error)
      return false
    }
  }

  // MARK: - Backend Segment Handling

  /// Handle incoming transcript segments from Python backend `/v4/listen`.
  /// The backend is a transient segment producer; the local store normalizes and owns the durable transcript.
}
