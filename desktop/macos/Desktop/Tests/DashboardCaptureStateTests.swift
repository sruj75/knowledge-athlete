import XCTest

final class DashboardCaptureStateTests: XCTestCase {
  func testDashboardCaptureStatusUsesLiveMonitoringState() throws {
    let source = try dashboardSource()
    let logic = try captureLogicSource()

    XCTAssertTrue(
      source.contains(
        "CaptureListeningLogic.captureStatus(appState: appState, isCaptureMonitoring: isCaptureMonitoring)"))
    XCTAssertTrue(
      logic.contains("return isCaptureLive(isCaptureMonitoring: isCaptureMonitoring) ? .active : .inactive"))
    XCTAssertTrue(logic.contains("isCaptureMonitoring || ProactiveAssistantsPlugin.shared.isMonitoring"))
  }

  func testDashboardCaptureToggleDerivesFromLiveState() throws {
    let source = try dashboardSource()
    let logic = try captureLogicSource()

    XCTAssertTrue(source.contains("CaptureListeningLogic.toggleCapture("))
    XCTAssertTrue(
      logic.contains(
        "syncCaptureState(screenAnalysisEnabled: screenAnalysisEnabled, isCaptureMonitoring: isCaptureMonitoring)"))
    XCTAssertTrue(
      logic.contains("let enabled = !isCaptureLive(isCaptureMonitoring: isCaptureMonitoring.wrappedValue)"))
  }

  func testListeningPillShowsAndTogglesCaptureMode() throws {
    let source = try dashboardSource()
    let logic = try captureLogicSource()

    XCTAssertTrue(source.contains("@AppStorage(\"systemAudioCaptureMode\")"))
    XCTAssertTrue(source.contains("HomeListeningStatusButton("))
    XCTAssertTrue(source.contains("modeAction: toggleListeningMode"))
    XCTAssertTrue(logic.contains("AssistantSettings.shared.systemAudioCaptureMode = nextMode"))
    XCTAssertFalse(source.contains("OmiColors.purplePrimary"))
  }

  func testRedesignedHomeUsesResponsiveStageSizing() throws {
    let source = try dashboardSource()

    XCTAssertTrue(source.contains("private static let homeStageMaxWidth: CGFloat = 1360"))
    XCTAssertTrue(source.contains("private func homeStageSideInset(for stageWidth: CGFloat) -> CGFloat"))
    XCTAssertTrue(source.contains("private func homeAskBarWidth(for stageWidth: CGFloat) -> CGFloat"))
    XCTAssertTrue(source.contains("private func homeHubStage(stageWidth: CGFloat, askBarWidth: CGFloat) -> some View"))
  }

  func testHomeAskBarRefocusesAfterOpeningChatStage() throws {
    let source = try dashboardSource()
    let openChat = try methodBody(named: "openHomeChat", in: source)

    XCTAssertTrue(source.contains("private func openHomeChat(focusInput: Bool = true)"))
    XCTAssertTrue(source.contains("focusHomeAskFieldAfterStageTransition()"))
    XCTAssertTrue(source.contains("await Task.yield()"))
    XCTAssertTrue(openChat.contains("if homeMode != .chat {"))
    XCTAssertFalse(openChat.contains("guard homeMode != .chat else { return }"))
  }

  func testSecondaryHomePagesReturnHomeOnEscape() throws {
    let source = try desktopHomeSource()

    XCTAssertTrue(
      source.range(
        of: #"\.onExitCommand\s*\{\s*navigateHomeOnEscapeIfNeeded\(\)\s*\}"#,
        options: .regularExpression) != nil)
    XCTAssertTrue(source.contains("[.conversations, .memories, .tasks, .rewind].contains(item)"))
  }

  private func dashboardSource() throws -> String {
    try source(named: "DashboardPage.swift")
  }

  private func desktopHomeSource() throws -> String {
    let path = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/MainWindow/DesktopHomeView.swift")
    return try String(contentsOf: path, encoding: .utf8)
  }

  private func captureLogicSource() throws -> String {
    let path = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/MainWindow/CaptureListeningLogic.swift")
    return try String(contentsOf: path, encoding: .utf8)
  }

  private func source(named name: String) throws -> String {
    let path = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/MainWindow/Pages")
      .appendingPathComponent(name)
    return try String(contentsOf: path, encoding: .utf8)
  }

  private func methodBody(named name: String, in source: String) throws -> String {
    let marker = "func \(name)"
    let start = try XCTUnwrap(source.range(of: marker))
    let opening = try XCTUnwrap(source.range(of: "{", range: start.lowerBound..<source.endIndex))
    var depth = 0
    for index in source.indices[opening.lowerBound...] {
      switch source[index] {
      case "{": depth += 1
      case "}":
        depth -= 1
        if depth == 0 { return String(source[opening.lowerBound...index]) }
      default: break
      }
    }
    throw NSError(domain: "DashboardCaptureStateTests", code: 1)
  }
}
