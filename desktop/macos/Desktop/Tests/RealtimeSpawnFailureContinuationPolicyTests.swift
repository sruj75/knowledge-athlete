import XCTest

@testable import Omi_Computer

final class RealtimeSpawnFailureContinuationPolicyTests: XCTestCase {
  func testFirstSpawnFailureContinuesTheTurnAndSecondTerminates() {
    var policy = RealtimeSpawnFailureContinuationPolicy()
    let turn = UUID()

    XCTAssertTrue(policy.beginContinuationIfAllowed(turnID: turn))
    XCTAssertFalse(
      policy.beginContinuationIfAllowed(turnID: turn),
      "the second spawn failure in the same turn must terminate it — no retry loops")
  }

  func testDistinctTurnsEachGetOneContinuation() {
    var policy = RealtimeSpawnFailureContinuationPolicy()

    XCTAssertTrue(policy.beginContinuationIfAllowed(turnID: UUID()))
    XCTAssertTrue(policy.beginContinuationIfAllowed(turnID: UUID()))
  }

  func testDefaultAgentFailureStillGetsOneContinuation() {
    var policy = RealtimeSpawnFailureContinuationPolicy()
    let turn = UUID()

    XCTAssertTrue(policy.beginContinuationIfAllowed(turnID: turn))
    XCTAssertFalse(policy.beginContinuationIfAllowed(turnID: turn))
  }
}
