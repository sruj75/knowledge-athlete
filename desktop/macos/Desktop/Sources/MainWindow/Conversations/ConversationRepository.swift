import Foundation
@preconcurrency import ObjectiveC

struct ConversationListQuery: Equatable, Sendable {
  let starredOnly: Bool
  let date: Date?
  let folderId: String?

  var hasFilters: Bool { starredOnly || date != nil || folderId != nil }

  static let all = ConversationListQuery(starredOnly: false, date: nil, folderId: nil)

  var localQuery: ConversationLocalQuery {
    let range = dateRange
    return ConversationLocalQuery(
      starredOnly: starredOnly,
      startDate: range.start,
      endDate: range.end,
      folderId: folderId)
  }

  private var dateRange: (start: Date?, end: Date?) {
    guard let date else { return (nil, nil) }
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: date)
    return (start, calendar.date(byAdding: .day, value: 1, to: start))
  }
}

struct ConversationRepositorySnapshot: Equatable, Sendable {
  let conversations: [LocalConversation]
  let count: Int?
  let isLoading: Bool
  let error: String?
}

protocol ConversationDataSource: Sendable {
  func list(query: ConversationListQuery, offset: Int, limit: Int) async throws -> [LocalConversation]
  func count(query: ConversationListQuery) async throws -> Int
  func detail(id: String) async throws -> LocalConversation
  func search(text: String) async throws -> [LocalConversation]
  func setStarred(id: String, starred: Bool) async throws -> LocalConversation
  func updateTitle(id: String, title: String) async throws -> LocalConversation
  func moveToFolder(id: String, folderId: String?) async throws -> LocalConversation
  func retryEnrichment(id: String) async throws -> LocalConversation
  func delete(id: String) async throws
}

struct LocalAuthorityConversationDataSource: ConversationDataSource {
  let storage: TranscriptionStorage

  init(storage: TranscriptionStorage = .shared) {
    self.storage = storage
  }

  func list(query: ConversationListQuery, offset: Int, limit: Int) async throws -> [LocalConversation] {
    try await storage.conversationPage(query: query.localQuery, offset: offset, limit: limit)
      .map(LocalConversationPresentationAdapter.summary)
  }

  func count(query: ConversationListQuery) async throws -> Int {
    try await storage.conversationCount(query: query.localQuery)
  }

  func detail(id: String) async throws -> LocalConversation {
    guard let detail = try await storage.conversationDetail(id: id) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    async let actionItems = storage.conversationActionItems(conversationId: id)
    async let enrichmentWork = storage.enrichmentWork(conversationId: id)
    return LocalConversationPresentationAdapter.detail(
      detail,
      actionItems: try await actionItems,
      enrichmentWork: try await enrichmentWork)
  }

  func search(text: String) async throws -> [LocalConversation] {
    try await storage.searchConversations(text: text).map(LocalConversationPresentationAdapter.summary)
  }

  func setStarred(id: String, starred: Bool) async throws -> LocalConversation {
    let detail = try await storage.setConversationStarred(
      id: id,
      starred: starred,
      authorization: try ownerAuthorization())
    return LocalConversationPresentationAdapter.detail(
      detail,
      actionItems: try await storage.conversationActionItems(conversationId: id),
      enrichmentWork: try await storage.enrichmentWork(conversationId: id))
  }

  func updateTitle(id: String, title: String) async throws -> LocalConversation {
    let detail = try await storage.setConversationTitle(
      id: id,
      title: title,
      authorization: try ownerAuthorization())
    return LocalConversationPresentationAdapter.detail(
      detail,
      actionItems: try await storage.conversationActionItems(conversationId: id),
      enrichmentWork: try await storage.enrichmentWork(conversationId: id))
  }

  func moveToFolder(id: String, folderId: String?) async throws -> LocalConversation {
    let detail = try await storage.moveConversation(
      id: id,
      toFolder: folderId,
      authorization: try ownerAuthorization())
    return LocalConversationPresentationAdapter.detail(
      detail,
      actionItems: try await storage.conversationActionItems(conversationId: id),
      enrichmentWork: try await storage.enrichmentWork(conversationId: id))
  }

  func retryEnrichment(id: String) async throws -> LocalConversation {
    let detail = try await storage.retryConversationEnrichment(
      id: id, authorization: try ownerAuthorization())
    return LocalConversationPresentationAdapter.detail(
      detail,
      actionItems: try await storage.conversationActionItems(conversationId: id),
      enrichmentWork: try await storage.enrichmentWork(conversationId: id))
  }

  func delete(id: String) async throws {
    try await storage.deleteConversationCascade(
      id: id,
      authorization: try ownerAuthorization())
  }

  private func ownerAuthorization() throws -> LocalMutationAuthorization {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      throw LocalMutationAuthorizationError.revoked
    }
    return LocalMutationAuthorization { RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot) }
  }
}

private enum LocalConversationPresentationAdapter {
  static func summary(_ value: LocalConversationSummary) -> LocalConversation {
    LocalConversation(
      id: value.conversationId,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      startedAt: value.startedAt,
      finishedAt: value.finishedAt,
      structured: Structured(
        title: value.title ?? "",
        overview: value.overview ?? "",
        emoji: value.emoji ?? "",
        actionItems: [],
        events: []),
      transcriptSegments: [],
      transcriptSegmentsIncluded: false,
      location: nil,
      language: "",
      status: presentationStatus(value.status),
      starred: value.starred,
      folderId: value.folderId,
      inputDeviceName: nil)
  }

  static func detail(
    _ value: LocalConversationDetail,
    actionItems: [LocalConversationActionItem],
    enrichmentWork: [ConversationEnrichmentWork]
  ) -> LocalConversation {
    let commitments =
      value.commitmentsJson
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONDecoder().decode([ConversationCommitmentComputeCandidate].self, from: $0) }
      ?? []
    return LocalConversation(
      id: value.conversationId,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      startedAt: value.startedAt,
      finishedAt: value.finishedAt,
      structured: Structured(
        title: value.title ?? "",
        overview: value.overview ?? "",
        emoji: value.emoji ?? "",
        actionItems: actionItems.map {
          ActionItem(
            description: $0.description,
            completed: $0.completed,
            deleted: $0.deleted,
            localRowId: $0.localRowId)
        },
        events: commitments.map {
          Event(
            title: $0.title,
            startsAt: $0.start,
            duration: $0.durationMinutes,
            description: $0.description,
            created: false)
        }),
      transcriptSegments: value.segments.map { segment in
        TranscriptSegment(
          id: segment.segmentId,
          text: segment.text,
          speaker: value.speakerLabels[segment.speakerId]?.name
            ?? "SPEAKER_\(String(format: "%02d", segment.speakerId))",
          speakerId: segment.speakerId,
          isUser: segment.isUser,
          start: segment.startTime,
          end: segment.endTime,
          translations: segment.translations.map {
            TranscriptTranslation(lang: $0.language, text: $0.text)
          })
      },
      transcriptSegmentsIncluded: true,
      location: value.location,
      language: value.language,
      status: presentationStatus(value.status),
      starred: value.starred,
      folderId: value.folderId,
      inputDeviceName: value.inputDeviceName,
      enrichmentFailures: enrichmentWork.compactMap { work in
        guard work.contentGeneration == value.contentGeneration, work.state == .failed else { return nil }
        switch work.kind {
        case .structure: return .summary
        case .actionItems: return .actionItems
        case .discard: return nil
        }
      })
  }

  private static func presentationStatus(_ value: ConversationLifecycleState) -> ConversationStatus {
    switch value {
    case .recording: return .inProgress
    case .finalizing, .processing: return .processing
    case .completed: return .completed
    case .merging: return .merging
    case .failed: return .failed
    }
  }
}

/// Main-actor projection of the authoritative owner-scoped GRDB store.
@MainActor
final class ConversationRepository {
  private static let pageSize = 50

  private let dataSource: ConversationDataSource
  private var requestGeneration = 0
  private var searchGeneration = 0
  private var currentQuery: ConversationListQuery?
  private var nextPageOffset = 0
  private var isLoadingMore = false
  private nonisolated(unsafe) var ownerChangeObserver: NSObjectProtocol?

  private(set) var conversations: [LocalConversation] = []
  private(set) var count: Int?
  private(set) var hasMore = false
  private(set) var isLoading = false
  private(set) var error: String?
  var onSnapshot: ((ConversationRepositorySnapshot) -> Void)?

  init(dataSource: ConversationDataSource = LocalAuthorityConversationDataSource()) {
    self.dataSource = dataSource
    ownerChangeObserver = NotificationCenter.default.addObserver(
      forName: .runtimeOwnerDidChange,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.reset() }
    }
  }

  deinit {
    if let ownerChangeObserver {
      NotificationCenter.default.removeObserver(ownerChangeObserver)
    }
  }

  func load(query: ConversationListQuery) async {
    requestGeneration += 1
    let generation = requestGeneration
    currentQuery = query
    isLoading = true
    error = nil
    emit()

    do {
      async let pageRequest = dataSource.list(query: query, offset: 0, limit: Self.pageSize)
      async let countRequest = dataSource.count(query: query)
      let (page, total) = try await (pageRequest, countRequest)
      guard generation == requestGeneration else { return }
      conversations = page
      count = total
      nextPageOffset = page.count
      hasMore = page.count == Self.pageSize && page.count < total
      isLoading = false
      emit()
    } catch {
      guard generation == requestGeneration else { return }
      if conversations.isEmpty {
        count = nil
        hasMore = false
      }
      isLoading = false
      self.error = UserFacingErrorPresentation.message(for: error, while: .conversations)
      emit()
    }
  }

  func refresh(query: ConversationListQuery) async {
    await load(query: query)
  }

  func loadMore() async {
    guard let query = currentQuery, hasMore, !isLoading, !isLoadingMore else { return }
    requestGeneration += 1
    let generation = requestGeneration
    let offset = nextPageOffset
    isLoadingMore = true
    defer { isLoadingMore = false }

    do {
      let page = try await dataSource.list(query: query, offset: offset, limit: Self.pageSize)
      guard generation == requestGeneration, currentQuery == query else { return }
      let known = Set(conversations.map(\.id))
      conversations.append(contentsOf: page.filter { !known.contains($0.id) })
      nextPageOffset = offset + page.count
      hasMore = page.count == Self.pageSize && count.map { nextPageOffset < $0 } ?? true
      emit()
    } catch {
      guard generation == requestGeneration else { return }
      self.error = UserFacingErrorPresentation.message(for: error, while: .conversations)
      emit()
    }
  }

  func search(text: String) async throws -> [LocalConversation] {
    searchGeneration += 1
    let generation = searchGeneration
    let result = try await dataSource.search(text: text)
    guard generation == searchGeneration else { throw CancellationError() }
    return result
  }

  func cancelSearch() {
    searchGeneration += 1
  }

  func detail(id: String) async throws -> LocalConversation {
    let generation = requestGeneration
    let detail = try await dataSource.detail(id: id)
    guard generation == requestGeneration else { throw CancellationError() }
    replaceVisible(detail)
    emit()
    return detail
  }

  func transcriptForCopy(id: String) async throws -> String {
    let value = try await detail(id: id)
    return value.transcript
  }

  func setStarred(id: String, starred: Bool) async throws {
    try await settleMutation(try await dataSource.setStarred(id: id, starred: starred))
  }

  func updateTitle(id: String, title: String) async throws -> LocalConversation {
    let conversation = try await dataSource.updateTitle(id: id, title: title)
    try await settleMutation(conversation)
    return conversation
  }

  func moveToFolder(id: String, folderId: String?) async throws {
    try await settleMutation(try await dataSource.moveToFolder(id: id, folderId: folderId))
  }

  func retryEnrichment(id: String) async throws -> LocalConversation {
    let conversation = try await dataSource.retryEnrichment(id: id)
    replaceVisible(conversation)
    emit()
    return conversation
  }

  func delete(id: String) async throws {
    try await dataSource.delete(id: id)
    conversations.removeAll { $0.id == id }
    if let count { self.count = max(0, count - 1) }
    emit()
  }

  func remove(id: String) {
    conversations.removeAll { $0.id == id }
    if let count { self.count = max(0, count - 1) }
    emit()
  }

  func reset() {
    requestGeneration += 1
    searchGeneration += 1
    currentQuery = nil
    nextPageOffset = 0
    isLoadingMore = false
    conversations = []
    count = nil
    hasMore = false
    isLoading = false
    error = nil
    emit()
  }

  private func settleMutation(_ conversation: LocalConversation) async throws {
    replaceVisible(conversation)
    emit()
    if let query = currentQuery {
      await load(query: query)
    }
  }

  private func replaceVisible(_ conversation: LocalConversation) {
    if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
      conversations[index] = conversation
    }
  }

  private func emit() {
    onSnapshot?(
      ConversationRepositorySnapshot(
        conversations: conversations,
        count: count,
        isLoading: isLoading,
        error: error))
  }
}
