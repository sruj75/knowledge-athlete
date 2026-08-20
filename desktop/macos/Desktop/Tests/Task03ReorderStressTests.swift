import XCTest

@testable import Omi_Computer

final class Task03ReorderStressTests: XCTestCase {
  private var fixture: RewindStorageTestIsolation.Fixture?

  override func setUp() async throws {
    try await super.setUp()
    fixture = try await RewindStorageTestIsolation.setUp(userIdPrefix: "local-reorder-stress")
  }

  override func tearDown() async throws {
    await RewindStorageTestIsolation.tearDown(userDir: fixture?.userDir)
    fixture = nil
    try await super.tearDown()
  }

  func test150RandomReordersPersistOneCollisionFreeOrder() async throws {
    var ids: [String] = []
    for index in 1...30 {
      let record = try await ActionItemStorage.shared.insertLocalActionItem(
        ActionItemRecord(description: "Task \(index)", source: "manual"),
        authorization: .unrestricted
      )
      ids.append(record.toTaskActionItem().id)
    }
    var expected = ids
    var rng = SplitMix64(seed: 19)

    for _ in 1...150 {
      let moved = ids[Int(rng.next() % UInt64(ids.count))]
      let target = Int(rng.next() % UInt64(ids.count + 1))
      expected.removeAll { $0 == moved }
      expected.insert(moved, at: min(target, expected.count))
      try await ActionItemStorage.shared.reorderTask(
        surfacedId: moved,
        dueAt: nil,
        orderedIds: expected,
        categoryIndex: 3,
        authorization: .unrestricted
      )
    }

    let records = try await ids.asyncMap { id -> ActionItemRecord in
      guard let rowID = ActionItemStorage.localRowID(surfacedId: id),
        let record = try await ActionItemStorage.shared.getActionItem(id: rowID)
      else { throw ActionItemStorageError.recordNotFound }
      return record
    }
    let persisted = records.sorted { ($0.sortOrder ?? .max) < ($1.sortOrder ?? .max) }
    XCTAssertEqual(persisted.compactMap { $0.id.map { "local_\($0)" } }, expected)
    XCTAssertEqual(Set(persisted.compactMap(\.sortOrder)).count, ids.count)
  }
}

private struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

extension Array {
  fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var results: [T] = []
    results.reserveCapacity(count)
    for element in self { results.append(try await transform(element)) }
    return results
  }
}
