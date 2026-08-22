import XCTest

@testable import Omi_Computer

final class DesktopNavigationPolicyTests: XCTestCase {
  func testPrimaryRoutesAndRetainedRawValuesAreExact() {
    XCTAssertEqual(
      DesktopNavigationPolicy.primaryDestinations,
      [.home, .memory, .tasks, .insights]
    )
    XCTAssertEqual(DesktopDestination.home.rawValue, 0)
    XCTAssertEqual(DesktopDestination.memory.rawValue, 1)
    XCTAssertEqual(DesktopDestination.memories.rawValue, 3)
    XCTAssertEqual(DesktopDestination.tasks.rawValue, 4)
    XCTAssertEqual(DesktopDestination.insights.rawValue, 5)
    XCTAssertEqual(DesktopDestination.rewind.rawValue, 7)
    XCTAssertEqual(DesktopDestination.settings.rawValue, 9)
    XCTAssertEqual(DesktopDestination.permissions.rawValue, 10)

    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 2))
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 6))
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 8))
    XCTAssertNil(DesktopNavigationPolicy.destination(forRawValue: 999))
  }

  func testPrimaryShortcutsResolveThroughTheSurvivingGraph() {
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "1"), .home)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "2"), .memories)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "3"), .tasks)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "4"), .insights)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: ","), .settings)
    XCTAssertEqual(DesktopNavigationPolicy.destination(forShortcut: "memory"), .memories)
    XCTAssertNil(DesktopNavigationPolicy.destination(forShortcut: "5"))
    XCTAssertNil(DesktopNavigationPolicy.destination(forShortcut: "rewind"))
  }

  func testSemanticTargetsDescribeTheProductionNavigationEffects() throws {
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("chat"),
      DesktopNavigationResolution(destination: .home, effect: .openHomeChat)
    )
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("conversations"),
      DesktopNavigationResolution(destination: .memory, effect: .selectMemory(.conversations))
    )
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("memories"),
      DesktopNavigationResolution(destination: .memory, effect: .selectMemory(.memories))
    )
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("focus"),
      DesktopNavigationResolution(destination: .insights, effect: .selectInsights(.focus))
    )
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("insights"),
      DesktopNavigationResolution(destination: .insights, effect: .selectInsights(.insights))
    )
    XCTAssertEqual(
      DesktopNavigationPolicy.resolveAutomationTarget("permissions")?.destination,
      .permissions
    )
    XCTAssertNil(DesktopNavigationPolicy.resolveAutomationTarget("apps"))
    XCTAssertNil(DesktopNavigationPolicy.resolveAutomationTarget("brain-map"))
    XCTAssertNil(DesktopNavigationPolicy.resolveAutomationTarget("unknown"))
  }

  func testEscapeReturnsHomeOnlyFromTheDecidedDestinations() {
    XCTAssertTrue(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .memory))
    XCTAssertTrue(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .memories))
    XCTAssertTrue(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .tasks))
    XCTAssertTrue(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .rewind))

    XCTAssertFalse(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .home))
    XCTAssertFalse(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .insights))
    XCTAssertFalse(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .settings))
    XCTAssertFalse(DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: .permissions))
  }

  func testRewindKeepsExactCommandOptionRShortcut() {
    XCTAssertTrue(
      DesktopNavigationPolicy.isRewindShortcut(
        keyCode: 15,
        modifiers: [.command, .option]
      ))
    XCTAssertFalse(
      DesktopNavigationPolicy.isRewindShortcut(
        keyCode: 15,
        modifiers: [.control, .option]
      ))
    XCTAssertFalse(
      DesktopNavigationPolicy.isRewindShortcut(
        keyCode: 15,
        modifiers: [.command, .option, .shift]
      ))
    XCTAssertFalse(
      DesktopNavigationPolicy.isRewindShortcut(
        keyCode: 14,
        modifiers: [.command, .option]
      ))
  }
}
