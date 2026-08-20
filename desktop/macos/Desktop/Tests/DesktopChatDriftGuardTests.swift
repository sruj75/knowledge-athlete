import XCTest

@testable import Omi_Computer

final class DesktopChatDriftGuardTests: XCTestCase {
  func testChatComposerUsesAThinUniformShellAndTranscriptFade() {
    XCTAssertEqual(ChatComposerLayout.shellInset, 8)
    XCTAssertEqual(ChatComposerLayout.pageMargin, 16)
    XCTAssertEqual(ChatComposerLayout.transcriptEdgeInset, ChatComposerLayout.pageMargin)
    XCTAssertGreaterThan(ChatComposerLayout.fadeHeight, ChatComposerLayout.shellInset)
    XCTAssertLessThanOrEqual(ChatComposerLayout.fadeHeight, 12)
  }

  func testOnlyConsecutiveUserRowsUseCompactSpacing() {
    let messages = [
      ChatMessage(id: "a0", text: "Answer", sender: .ai),
      ChatMessage(id: "u0", text: "First", sender: .user),
      ChatMessage(id: "u1", text: "Second", sender: .user),
      ChatMessage(id: "a1", text: "Answer", sender: .ai),
    ]

    XCTAssertEqual(ChatTranscriptLayout.topAdjustment(at: 0, in: messages), 0)
    XCTAssertEqual(ChatTranscriptLayout.topAdjustment(at: 1, in: messages), 0)
    XCTAssertEqual(
      ChatTranscriptLayout.regularRowSpacing
        + ChatTranscriptLayout.topAdjustment(at: 2, in: messages),
      ChatTranscriptLayout.consecutiveUserRowSpacing
    )
    XCTAssertEqual(ChatTranscriptLayout.topAdjustment(at: 3, in: messages), 0)
  }

  func testMainAndNotchChatShareTheTranscriptFade() throws {
    let mainChat = try sourceFile("MainWindow/Pages/DashboardPage.swift")
    let notchChat = try sourceFile("FloatingControlBar/AIResponseView.swift")

    XCTAssertTrue(mainChat.contains(".overlay(alignment: .bottom) {\n      ChatComposerFade()"))
    XCTAssertTrue(notchChat.contains(".overlay(alignment: .bottom) {\n        ChatComposerFade()"))
    XCTAssertTrue(mainChat.contains(".padding(.vertical, OmiSpacing.sm)"))
  }

  func testChatTranscriptLoaderIgnoresSessionListRefreshes() throws {
    let dashboardPage = try sourceFile("MainWindow/Pages/DashboardPage.swift")

    for source in [dashboardPage] {
      XCTAssertFalse(
        source.contains("isLoadingInitial: (chatProvider.isLoading || chatProvider.isLoadingSessions)"),
        "Session-list refreshes must not hide a non-empty transcript behind the initial message-history loader."
      )
      XCTAssertFalse(
        source.contains("isLoadingInitial: chatProvider.isLoadingSessions"),
        "Session-list refreshes must not drive the transcript's initial loader."
      )
    }

    XCTAssertEqual(
      dashboardPage.components(separatedBy: "isLoadingInitial: chatProvider.isLoading && !chatProvider.isClearing")
        .count - 1,
      2
    )
  }

  private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: sourcesRoot().appendingPathComponent(relativePath), encoding: .utf8)
  }

  private func sourcesRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")
  }
}
