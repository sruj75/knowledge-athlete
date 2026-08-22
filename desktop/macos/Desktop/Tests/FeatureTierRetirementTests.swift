import XCTest

@testable import Omi_Computer

final class FeatureTierRetirementTests: XCTestCase {
  private var desktopRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  }

  /// Source-inspection tripwire for an intentional deletion boundary. Navigation behavior is
  /// exercised separately by DesktopNavigationPolicyTests; this test prevents the retired shell
  /// and tier owner from returning as a second source of truth.
  func testRetiredShellAndFeatureTierSourcesAreDeleted() throws {
    for path in [
      "Sources/TierManager.swift",
      "Sources/MainWindow/SidebarView.swift",
      "Sources/MainWindow/ClickThroughView.swift",
    ] {
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: desktopRoot.appendingPathComponent(path).path),
        "\(path) is retired and must not remain in the desktop target"
      )
    }
  }

  func testSurvivingShellDoesNotReadLegacyTierOrSidebarState() throws {
    for path in [
      "Sources/OmiApp.swift",
      "Sources/MainWindow/DesktopHomeView.swift",
      "Sources/MainWindow/Pages/SettingsPage.swift",
      "Sources/MainWindow/Pages/Settings/Sections/SettingsContentView+Advanced.swift",
      "Sources/MainWindow/Pages/Settings/Components/SettingsContentView+Controls.swift",
    ] {
      // omi-test-quality: source-inspection -- static contract: the retained shell must not regain a second tier or sidebar state owner; route behavior is covered by DesktopNavigationPolicyTests and DesktopShellVisibilityTests.
      let source = try String(
        contentsOf: desktopRoot.appendingPathComponent(path), encoding: .utf8)
      for retiredSymbol in [
        "TierManager", "currentTierLevel", "lastSeenTierLevel", "userShowAllFeatures",
        "showsPrimarySidebar", "isSidebarCollapsed",
      ] {
        XCTAssertFalse(
          source.contains(retiredSymbol),
          "\(path) still depends on retired shell state: \(retiredSymbol)"
        )
      }
    }
  }
}
