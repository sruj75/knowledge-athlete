import XCTest

#if canImport(Omi_Computer)
  @testable import Omi_Computer
#else
  @testable import SupervisorDiagnosticLeaf
#endif

final class SupervisorDiagnosticMetricsTests: XCTestCase {
  func testSnapshotExportsAggregatesWithoutInternalRequestReceiptsOrContentFields() throws {
    var metrics = SupervisorObservationMetrics()
    _ = metrics.admit(queuedAt: 10, at: 11)
    let snapshot = SupervisorDiagnosticSnapshot(metrics: metrics)
    let data = try JSONEncoder().encode(snapshot)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let exported = try XCTUnwrap(object["metrics"] as? [String: Any])
    XCTAssertEqual(exported["admitted"] as? Int, 1)
    XCTAssertNil(exported["active"])
    XCTAssertNil(exported["evaluatorStartedAt"])
    XCTAssertNil(object["ownerID"])
    XCTAssertNil(object["contentRevision"], "process-wide activity cannot cross diagnostic owner/session boundaries")
    XCTAssertNil(object["applicationName"])
    XCTAssertNil(object["transcripts"])
    XCTAssertNil(object["guidance"])
    XCTAssertNil(object["profile"])
    XCTAssertEqual(object["schemaVersion"] as? Int, 1)
  }

  func testSkipCountersAreBoundedByReasonAndResetRejectsOldSessionCompletions() {
    var metrics = SupervisorObservationMetrics()
    metrics.skip(.inFlight)
    metrics.skip(.inFlight)
    metrics.skip(.budget)
    XCTAssertEqual(metrics.skipped["in_flight"], 2)
    XCTAssertEqual(metrics.skipped["budget"], 1)
    let old = metrics.admit(queuedAt: 10, at: 11)
    metrics.startEvaluator(old, at: 12)
    metrics = SupervisorObservationMetrics()
    let current = metrics.admit(queuedAt: 20, at: 21)
    metrics.finish(old, at: 30, outcome: .returned)
    XCTAssertEqual(metrics.admitted, 1)
    XCTAssertEqual(metrics.evaluatorReturns, 0)
    XCTAssertEqual(metrics.currentWork, .preparing)
    XCTAssertTrue(metrics.skipped.isEmpty)
    metrics.startEvaluator(current, at: 31)
    metrics.startEvaluator(current, at: 32)
    XCTAssertEqual(metrics.evaluatorStarts, 1)
  }

  func testThrowAndCancellationAreCountedOnceWithoutInventingSuccessfulReturns() {
    var metrics = SupervisorObservationMetrics()
    let failed = metrics.admit(queuedAt: 10, at: 11)
    metrics.startEvaluator(failed, at: 12)
    metrics.finish(failed, at: 14, outcome: .failed)
    metrics.finish(failed, at: 15, outcome: .discardedBeforeEvaluation)
    let cancelled = metrics.admit(queuedAt: 20, at: 21)
    metrics.startEvaluator(cancelled, at: 22)
    metrics.finish(cancelled, at: 23, outcome: .cancelled)
    XCTAssertEqual(metrics.evaluatorFailures, 1)
    XCTAssertEqual(metrics.evaluatorCancellations, 1)
    XCTAssertEqual(metrics.evaluatorReturns, 0)
    XCTAssertEqual(metrics.evaluatorRoundTrip.count, 2)
    XCTAssertEqual(metrics.evaluatorRoundTrip.totalMs, 3_000)
    XCTAssertEqual(metrics.evaluatorRoundTrip.minimumMs, 1_000)
    XCTAssertEqual(metrics.evaluatorRoundTrip.maximumMs, 2_000)
  }

  func testDiscardedPreparationDoesNotInventAnEvaluatorReturn() {
    var metrics = SupervisorObservationMetrics()
    let receipt = metrics.admit(queuedAt: 20, at: 21)
    metrics.finish(receipt, at: 22, outcome: .discardedBeforeEvaluation)
    XCTAssertEqual(metrics.discardedBeforeEvaluation, 1)
    XCTAssertEqual(metrics.evaluatorStarts, 0)
    XCTAssertEqual(metrics.evaluatorReturns, 0)
    XCTAssertEqual(metrics.evaluatorRoundTrip.count, 0)
    XCTAssertEqual(metrics.admissionToCompletion.lastMs, 1_000)
    metrics.finish(receipt, at: 24, outcome: .discardedBeforeEvaluation)
    XCTAssertEqual(metrics.discardedBeforeEvaluation, 1, "defer cleanup cannot count a second completion")
  }

  func testAdmissionDoesNotCountAsAnEvaluatorCallAndTimingsKeepTheirBoundaries() {
    var metrics = SupervisorObservationMetrics()
    let receipt = metrics.admit(queuedAt: 10, at: 11)
    XCTAssertEqual(metrics.admitted, 1)
    XCTAssertEqual(metrics.evaluatorStarts, 0)
    XCTAssertEqual(metrics.queue.lastMs, 1_000)
    metrics.startEvaluator(receipt, at: 13)
    XCTAssertEqual(metrics.evaluatorStarts, 1)
    metrics.finish(receipt, at: 17, outcome: .returned)
    XCTAssertEqual(metrics.evaluatorReturns, 1)
    XCTAssertEqual(metrics.evaluatorRoundTrip.lastMs, 4_000)
    XCTAssertEqual(metrics.admissionToCompletion.lastMs, 6_000)
    XCTAssertEqual(metrics.observationToCompletion.lastMs, 7_000)
    XCTAssertEqual(metrics.currentWork, .none)
  }
}
