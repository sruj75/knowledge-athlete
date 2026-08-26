import XCTest

@testable import Omi_Computer

final class TasksSortOrderBandingTests: XCTestCase {
  @MainActor
  func testNeutralInlineCreateAndSameSectionReorderPreserveDeadline() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(calendar.date(from: .init(year: 2025, month: 1, day: 6, hour: 10)))
    let due = try XCTUnwrap(calendar.date(from: .init(year: 2025, month: 1, day: 6, hour: 15, minute: 37)))
    let task = TaskActionItem(
      id: "local_1",
      description: "Preserve my exact time",
      completed: false,
      createdAt: now,
      dueAt: due
    )

    XCTAssertNil(TasksViewModel.inlineCreationDueDate(after: nil, now: now, calendar: calendar))
    XCTAssertEqual(
      TasksViewModel.reorderedDueDate(for: task, in: .today, now: now, calendar: calendar),
      due
    )
  }

  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "local-sort-bands")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func testLargeCategoryOrderStaysInsideItsLocalBandAcrossReload() async throws {
    var ids: [String] = []
    for index in 0..<150 {
      let inserted = try await ActionItemStorage.shared.insertLocalActionItem(
        ActionItemRecord(description: "Band task \(index)", source: "manual"),
        authorization: .unrestricted
      )
      ids.append(inserted.toTaskActionItem().id)
    }
    let expected = Array(ids.reversed())
    try await ActionItemStorage.shared.reorderTask(
      surfacedId: expected[0],
      dueAt: nil,
      orderedIds: expected,
      categoryIndex: 3,
      authorization: .unrestricted
    )

    await ActionItemStorage.shared.invalidateCache()
    let page = try await ActionItemStorage.shared.getLocalActionItems(limit: 200, completed: false)
    XCTAssertEqual(page.map(\.id), expected)
    let orders = page.compactMap(\.sortOrder)
    XCTAssertEqual(Set(orders).count, 150)
    XCTAssertTrue(orders.allSatisfy { (300_000..<400_000).contains($0) })
  }

  func testCrossSectionReorderCommitsDeadlineWithOrder() async throws {
    let first = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(description: "Move me", source: "manual"),
      authorization: .unrestricted
    ).toTaskActionItem()
    let second = try await ActionItemStorage.shared.insertLocalActionItem(
      ActionItemRecord(description: "Target", source: "manual"),
      authorization: .unrestricted
    ).toTaskActionItem()
    let tomorrow = Date(timeIntervalSince1970: 1_735_086_400)

    try await ActionItemStorage.shared.reorderTask(
      surfacedId: first.id,
      dueAt: tomorrow,
      orderedIds: [first.id, second.id],
      categoryIndex: 1,
      authorization: .unrestricted
    )

    let fetched = try await ActionItemStorage.shared.getLocalActionItem(surfacedId: first.id)
    let moved = try XCTUnwrap(fetched)
    XCTAssertEqual(moved.dueAt, tomorrow)
    XCTAssertTrue((100_000..<200_000).contains(try XCTUnwrap(moved.sortOrder)))
  }
}
