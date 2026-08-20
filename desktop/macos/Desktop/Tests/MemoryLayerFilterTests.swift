import XCTest

@testable import Omi_Computer

final class MemoryLayerFilterTests: XCTestCase {
  func testDefaultFilterIsDefaultAccessOnly() {
    XCTAssertEqual(MemoryLayerFilter.defaultAccess.allowedLayers, [.shortTerm, .longTerm])
    XCTAssertFalse(MemoryLayerFilter.defaultAccess.allowedLayers.contains(.archive))
  }

  func testExplicitArchiveFilterOnlyAllowsArchive() {
    XCTAssertEqual(MemoryLayerFilter.archive.allowedLayers, [.archive])
  }

  func testDefaultLayerScopeExcludesArchive() {
    XCTAssertEqual(MemoryLayerScope.defaultAccess.layers, [.shortTerm, .longTerm])
    XCTAssertFalse(MemoryLayerScope.defaultAccess.includesArchive)
  }

  func testArchiveScopeRequiresAcknowledgement() {
    XCTAssertEqual(MemoryLayerScope.archiveOnly.layers, [.archive])
    XCTAssertTrue(MemoryLayerScope.archiveOnly.requiresArchiveAcknowledgement)
  }

  func testUnknownPersistedLayerIsExcludedInsteadOfPromoted() {
    let record = MemoryRecord(content: "Future record", layer: "unexpected_future_layer")
    XCTAssertNil(record.toMemoryItem())
  }
}
