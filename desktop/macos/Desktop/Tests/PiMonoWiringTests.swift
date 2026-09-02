import XCTest

@testable import Omi_Computer

final class PiMonoWiringTests: XCTestCase {
  func testHarnessMappingAcceptsOnlyManagedPi() {
    XCTAssertEqual(AgentRuntimeRouting.adapterId(for: .piMono), .piMono)
    XCTAssertEqual(AgentRuntimeRouting.harnessMode(from: "piMono"), .piMono)
    XCTAssertEqual(AgentRuntimeRouting.harnessMode(from: "pi-mono"), .piMono)
    XCTAssertNil(AgentRuntimeRouting.harnessMode(from: "unknown"))
  }

  func testApiKeysResponseIgnoresRetiredProviderFields() throws {
    let json = """
      {
        "firebase_api_key": "AIza-test",
        "anthropic_api_key": "sk-ant-retired",
        "google_calendar_api_key": "cal-key",
        "deepgram_api_key": "dg-retired"
      }
      """.data(using: .utf8)!
    let response = try JSONDecoder().decode(APIClient.ApiKeysResponse.self, from: json)
    let propertyNames = Mirror(reflecting: response).children.map { $0.label ?? "" }

    XCTAssertEqual(response.firebaseApiKey, "AIza-test")
    XCTAssertFalse(propertyNames.contains("anthropicApiKey"))
    XCTAssertFalse(propertyNames.contains("googleCalendarApiKey"))
    XCTAssertFalse(propertyNames.contains("deepgramApiKey"))
  }

  func testRemovedBridgeAndCredentialSurfacesStayAbsent() throws {
    let sourcesDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")
    guard FileManager.default.fileExists(atPath: sourcesDirectory.path) else {
      throw XCTSkip("Sources directory not found at \(sourcesDirectory.path)")
    }

    let forbidden = ["ACPBridge", "acp-bridge", "acpBridge", "AgentBridge(passApiKey:"]
    var violations: [String] = []
    let enumerator = FileManager.default.enumerator(
      at: sourcesDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )!
    while let url = enumerator.nextObject() as? URL {
      guard url.pathExtension == "swift" else { continue }
      let content = try String(contentsOf: url, encoding: .utf8)
      for pattern in forbidden where content.contains(pattern) {
        violations.append("\(url.lastPathComponent): \(pattern)")
      }
    }

    XCTAssertEqual(violations, [])
  }
}
