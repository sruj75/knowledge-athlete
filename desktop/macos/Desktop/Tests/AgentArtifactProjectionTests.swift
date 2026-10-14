import XCTest

@testable import Omi_Computer

@MainActor final class AgentArtifactProjectionTests: XCTestCase {
  func testParsesArtifactMetadataProjection() throws {
    let result = """
      {
        "ok": true,
        "artifacts": [
          {
            "artifactId": "artifact-1",
            "sessionId": "session-1",
            "runId": "run-1",
            "attemptId": "attempt-1",
            "kind": "json",
            "role": "result",
            "uri": "omi-artifact://artifact-1",
            "displayName": "summary.json",
            "mimeType": "application/json",
            "contentHash": "sha256:abc",
            "sizeBytes": 42,
            "lifecycleState": "opened",
            "lifecycleUpdatedAtMs": 1234,
            "metadata": {
              "adapter": "pi-mono",
              "nested": { "index": 2 }
            },
            "createdAtMs": 99
          }
        ]
      }
      """

    let artifacts = try AgentArtifactProjection.parseList(fromToolResult: result)

    XCTAssertEqual(artifacts.count, 1)
    XCTAssertEqual(artifacts[0].artifactId, "artifact-1")
    XCTAssertEqual(artifacts[0].sessionId, "session-1")
    XCTAssertEqual(artifacts[0].runId, "run-1")
    XCTAssertEqual(artifacts[0].attemptId, "attempt-1")
    XCTAssertEqual(artifacts[0].title, "summary.json")
    XCTAssertEqual(artifacts[0].mimeType, "application/json")
    XCTAssertEqual(artifacts[0].sizeBytes, 42)
    XCTAssertEqual(artifacts[0].lifecycleState, "opened")
    XCTAssertEqual(artifacts[0].lifecycleUpdatedAtMs, 1234)
    XCTAssertEqual(artifacts[0].createdAtMs, 99)
    XCTAssertEqual(artifacts[0].metadataRows, ["adapter: pi-mono", #"nested: {"index":2}"#])
  }

}
