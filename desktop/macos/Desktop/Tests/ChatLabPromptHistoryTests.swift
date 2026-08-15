import XCTest

@testable import Omi_Computer

@MainActor
final class ChatLabPromptHistoryTests: XCTestCase {
  func testPromptHistoryLoadsOnlyFromInjectedGitHistoryBoundary() async {
    var loadCount = 0
    let viewModel = ChatLabViewModel(
      chatProvider: ChatProvider(),
      promptHistoryLoader: {
        loadCount += 1
        return [
          PromptHistoryEntry(
            version: 7,
            date: "2026-08-15",
            commitMsg: "Tune prompt",
            commitHash: "deadbeef",
            promptSnippet: "Be useful",
            fullPrompt: "Be useful and concise"
          )
        ]
      },
      automaticallyLoadPromptHistory: false
    )

    await viewModel.loadPromptHistory()

    XCTAssertEqual(loadCount, 1)
    XCTAssertFalse(viewModel.isLoadingHistory)
    XCTAssertEqual(viewModel.promptHistory.count, 1)
    XCTAssertEqual(viewModel.promptHistory.first?.version, 7)
    XCTAssertEqual(viewModel.promptHistory.first?.commitHash, "deadbeef")
    XCTAssertEqual(viewModel.promptHistory.first?.fullPrompt, "Be useful and concise")
  }
}
