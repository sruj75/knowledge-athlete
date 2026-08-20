import XCTest

@testable import Omi_Computer

final class MemoryProvenanceTests: XCTestCase {
  func testCapturingAppIsReadFromTheAppTag() {
    let memory = makeMemory(tags: ["focus", "app:Codex"])
    XCTAssertEqual(MemoryProvenance.facts(for: memory).map(\.label), ["Desktop", "Codex"])
  }

  func testUnknownAppTagIsNotPresentedAsAnAnswer() {
    for value in ["app:Unknown", "app:Unknown Application/Browser", "app:   "] {
      let facts = MemoryProvenance.facts(for: makeMemory(tags: [value], source: nil))
      XCTAssertTrue(facts.isEmpty, "\(value) should not be presented as the capturing app")
    }
  }

  func testLocallyKnownFieldsDescribeManualProvenance() {
    let memory = makeMemory(
      manuallyAdded: true, source: .manual, confidence: 0.82,
      inputDeviceName: "MacBook Pro Mic")

    XCTAssertEqual(
      MemoryProvenance.facts(for: memory).map(\.label),
      ["Added by you", "MacBook Pro Mic", "82% confidence"])
  }

  private func makeMemory(
    tags: [String] = [],
    manuallyAdded: Bool = false,
    source: MemorySource? = .desktop,
    confidence: Double? = nil,
    inputDeviceName: String? = nil
  ) -> MemoryItem {
    MemoryItem(
      id: "1", content: "content", category: .system, layer: .longTerm,
      expiresAt: nil, revision: 1,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2), correctedAt: nil,
      conversationId: nil, sourceSegmentId: nil,
      manuallyAdded: manuallyAdded, source: source,
      confidence: confidence, sourceApp: nil, contextSummary: nil,
      isRead: false, isDismissed: false, tags: tags, reasoning: nil,
      currentActivity: nil, inputDeviceName: inputDeviceName,
      windowTitle: nil, screenshotId: nil)
  }
}
