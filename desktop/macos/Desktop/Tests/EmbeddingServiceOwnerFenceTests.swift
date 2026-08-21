import XCTest

@testable import Omi_Computer

@MainActor
final class EmbeddingServiceOwnerFenceTests: XCTestCase {
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    let ownerFixture = RuntimeOwnerAuthorityTestFixture()
    self.ownerFixture = ownerFixture
    await ownerFixture.establish(authOwnerID: "embedding-owner")
    await EmbeddingService.shared.resetForOwnerChange()
  }

  override func tearDown() async throws {
    await EmbeddingService.shared.resetForOwnerChange()
    if let ownerFixture { await ownerFixture.restore() }
    ownerFixture = nil
  }

  func testSameUIDReauthenticationCannotReadPreviousGenerationTaskIndex() async throws {
    let ownerFixture = try XCTUnwrap(ownerFixture)
    let original = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())
    let vector = [Float](repeating: 0, count: EmbeddingService.embeddingDimension)
    await EmbeddingService.shared.addToIndex(
      id: 41,
      embedding: vector,
      authorizationSnapshot: original)
    let before = await EmbeddingService.shared.searchSimilar(
      query: vector,
      authorizationSnapshot: original)
    XCTAssertEqual(before.map(\.id), [41])

    await ownerFixture.establish(authOwnerID: nil)
    await ownerFixture.establish(authOwnerID: "embedding-owner")
    let replacement = try XCTUnwrap(RuntimeOwnerIdentity.captureAuthorizationSnapshot())

    let staleRead = await EmbeddingService.shared.searchSimilar(
      query: vector,
      authorizationSnapshot: original)
    let replacementRead = await EmbeddingService.shared.searchSimilar(
      query: vector,
      authorizationSnapshot: replacement)
    XCTAssertTrue(staleRead.isEmpty)
    XCTAssertTrue(replacementRead.isEmpty)
  }
}
