import XCTest

@testable import Omi_Computer

@MainActor
final class ConversationRepositoryTests: XCTestCase {
  func testLoadProjectsOneLocalSourceAndCount() async {
    let rows = [conversation(id: "one"), conversation(id: "two")]
    let source = RepositoryLocalSource(rows: rows)
    let repository = ConversationRepository(dataSource: source)

    await repository.load(query: .all)

    XCTAssertEqual(repository.conversations.map(\.id), ["one", "two"])
    XCTAssertEqual(repository.count, 2)
    XCTAssertNil(repository.error)
  }

  func testInitialLoadFailureSurfacesErrorWithNoRows() async {
    let source = RepositoryLocalSource(rows: [])
    await source.setFailReads(true)
    let repository = ConversationRepository(dataSource: source)

    await repository.load(query: .all)

    XCTAssertTrue(repository.conversations.isEmpty)
    XCTAssertNotNil(repository.error)
  }

  func testRefreshFailurePreservesAlreadyVisibleRows() async {
    let source = RepositoryLocalSource(rows: [conversation(id: "visible")])
    let repository = ConversationRepository(dataSource: source)
    await repository.load(query: .all)
    await source.setFailReads(true)

    await repository.refresh(query: .all)

    XCTAssertEqual(repository.conversations.map(\.id), ["visible"])
    XCTAssertNotNil(repository.error)
  }

  func testLoadMoreUsesStableFiftyRowPaging() async {
    let rows = (0..<51).map { conversation(id: String(format: "%02d", $0)) }
    let repository = ConversationRepository(dataSource: RepositoryLocalSource(rows: rows))

    await repository.load(query: .all)
    XCTAssertEqual(repository.conversations.count, 50)
    XCTAssertTrue(repository.hasMore)

    await repository.loadMore()
    XCTAssertEqual(repository.conversations.count, 51)
    XCTAssertFalse(repository.hasMore)
  }

  func testDetailReturnsTheLocalRecordAndPublishesIt() async throws {
    let seed = conversation(id: "detail", title: "Seed", transcriptIncluded: false)
    let detail = conversation(id: "detail", title: "Local detail", transcriptIncluded: true)
    let source = RepositoryLocalSource(rows: [seed], detail: detail)
    let repository = ConversationRepository(dataSource: source)
    await repository.load(query: .all)
    let loaded = try await repository.detail(id: seed.id)

    XCTAssertEqual(loaded.structured.title, "Local detail")
    XCTAssertEqual(repository.conversations.first, loaded)
  }

  func testDetailLoadsAConversationOutsideTheFirstPageByID() async throws {
    let rows = (0..<51).map { conversation(id: String(format: "%02d", $0)) }
    let repository = ConversationRepository(dataSource: RepositoryLocalSource(rows: rows))
    await repository.load(query: .all)

    let loaded = try await repository.detail(id: "50")

    XCTAssertEqual(loaded.id, "50")
  }

  func testTranscriptForCopyLoadsLocalDetailOnDemand() async throws {
    let seed = conversation(id: "copy", title: "Seed", transcriptIncluded: false)
    let detail = conversation(id: "copy", title: "Detail", transcriptIncluded: true)
    let repository = ConversationRepository(
      dataSource: RepositoryLocalSource(rows: [seed], detail: detail))
    await repository.load(query: .all)

    let transcript = try await repository.transcriptForCopy(id: seed.id)

    XCTAssertEqual(transcript, "You: Transcript")
  }

  func testSearchDelegatesOnlyToTheLocalSource() async throws {
    let match = conversation(id: "match", title: "Launch notes")
    let source = RepositoryLocalSource(rows: [match])
    let repository = ConversationRepository(dataSource: source)

    let results = try await repository.search(text: "launch")
    let lastSearch = await source.lastSearch()

    XCTAssertEqual(results, [match])
    XCTAssertEqual(lastSearch, "launch")
  }

  func testMutationSettlesFromLocalReceiptAndReloads() async throws {
    let initial = conversation(id: "star")
    let source = RepositoryLocalSource(rows: [initial])
    let repository = ConversationRepository(dataSource: source)
    await repository.load(query: .all)

    try await repository.setStarred(id: initial.id, starred: true)
    let starredValue = await source.starredValue(id: initial.id)

    XCTAssertEqual(repository.conversations.first?.starred, true)
    XCTAssertEqual(starredValue, true)
  }

  func testRejectedTitleAndFolderMutationsDoNotPublishUncommittedValues() async throws {
    let initial = conversation(id: "visible", title: "Committed")
    let repository = ConversationRepository(dataSource: RepositoryLocalSource(rows: [initial]))
    await repository.load(query: .all)

    do {
      _ = try await repository.updateTitle(id: "missing", title: "Uncommitted")
      XCTFail("expected missing title mutation to fail")
    } catch {}
    do {
      try await repository.moveToFolder(id: "missing", folderId: "uncommitted-folder")
      XCTFail("expected missing folder mutation to fail")
    } catch {}

    XCTAssertEqual(repository.conversations.first?.title, "Committed")
    XCTAssertNil(repository.conversations.first?.folderId)
  }

  func testDeleteRemovesOnlyAcknowledgedLocalRow() async throws {
    let first = conversation(id: "delete")
    let second = conversation(id: "keep")
    let source = RepositoryLocalSource(rows: [first, second])
    let repository = ConversationRepository(dataSource: source)
    await repository.load(query: .all)

    try await repository.delete(id: first.id)
    let rowIds = await source.rowIds()

    XCTAssertEqual(repository.conversations.map(\.id), [second.id])
    XCTAssertEqual(repository.count, 1)
    XCTAssertEqual(rowIds, [second.id])
  }

  private func conversation(
    id: String,
    title: String = "Conversation",
    transcriptIncluded: Bool = false
  ) -> LocalConversation {
    conversationFixture(id: id, title: title, transcriptIncluded: transcriptIncluded)
  }
}

private actor RepositoryLocalSource: ConversationDataSource {
  private var rows: [LocalConversation]
  private let detailValue: LocalConversation?
  private var searchText: String?
  private var failReads = false

  init(rows: [LocalConversation], detail: LocalConversation? = nil) {
    self.rows = rows
    detailValue = detail
  }

  func list(query: ConversationListQuery, offset: Int, limit: Int) async throws -> [LocalConversation] {
    if failReads { throw TranscriptionStorageError.invalidState("injected read failure") }
    let filtered = rows.filter { row in
      (!query.starredOnly || row.starred)
        && (query.folderId == nil || row.folderId == query.folderId)
    }
    guard offset < filtered.count else { return [] }
    return Array(filtered[offset..<min(filtered.count, offset + limit)])
  }

  func count(query: ConversationListQuery) async throws -> Int {
    if failReads { throw TranscriptionStorageError.invalidState("injected read failure") }
    let values = try await list(query: query, offset: 0, limit: Int.max)
    return values.count
  }

  func detail(id: String) async throws -> LocalConversation {
    if let detailValue, detailValue.id == id { return detailValue }
    guard let value = rows.first(where: { $0.id == id }) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    return value
  }

  func search(text: String) async throws -> [LocalConversation] {
    searchText = text
    return rows.filter {
      $0.structured.title.localizedCaseInsensitiveContains(text)
        || $0.structured.overview.localizedCaseInsensitiveContains(text)
    }
  }

  func setStarred(id: String, starred: Bool) async throws -> LocalConversation {
    guard let index = rows.firstIndex(where: { $0.id == id }) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    rows[index].starred = starred
    return rows[index]
  }

  func updateTitle(id: String, title: String) async throws -> LocalConversation {
    guard let index = rows.firstIndex(where: { $0.id == id }) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    rows[index].structured.title = title
    return rows[index]
  }

  func moveToFolder(id: String, folderId: String?) async throws -> LocalConversation {
    guard let row = rows.first(where: { $0.id == id }) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    return conversationFixture(
      id: row.id,
      title: row.structured.title,
      transcriptIncluded: row.transcriptSegmentsIncluded,
      starred: row.starred,
      folderId: folderId)
  }

  func retryEnrichment(id: String) async throws -> LocalConversation {
    guard let value = rows.first(where: { $0.id == id }) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    return value
  }

  func delete(id: String) async throws {
    guard rows.contains(where: { $0.id == id }) else {
      throw TranscriptionStorageError.sessionNotFound
    }
    rows.removeAll { $0.id == id }
  }

  func lastSearch() -> String? { searchText }
  func starredValue(id: String) -> Bool? { rows.first(where: { $0.id == id })?.starred }
  func rowIds() -> [String] { rows.map(\.id) }
  func setFailReads(_ value: Bool) { failReads = value }
}

private func conversationFixture(
  id: String,
  title: String,
  transcriptIncluded: Bool,
  starred: Bool = false,
  folderId: String? = nil
) -> LocalConversation {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  return LocalConversation(
    id: id,
    createdAt: date,
    updatedAt: date,
    startedAt: date,
    finishedAt: date.addingTimeInterval(60),
    structured: Structured(
      title: title,
      overview: "Overview for \(title)",
      emoji: "",
      actionItems: [],
      events: []),
    transcriptSegments: transcriptIncluded
      ? [
        TranscriptSegment(
          id: "\(id)-segment",
          text: "Transcript",
          speaker: "You",
          speakerId: 0,
          isUser: true,
          start: 0,
          end: 1)
      ] : [],
    transcriptSegmentsIncluded: transcriptIncluded,
    location: nil,
    language: "en",
    status: .completed,
    starred: starred,
    folderId: folderId,
    inputDeviceName: "Test microphone")
}
