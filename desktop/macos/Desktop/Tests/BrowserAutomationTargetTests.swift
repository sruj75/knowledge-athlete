import XCTest

@testable import Omi_Computer

@MainActor
final class BrowserAutomationTargetTests: XCTestCase {
  func testDetectsExtensionInConfiguredProfileRoot() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("omi-browser-target-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = BrowserAutomationTarget(
      name: "Test Chromium",
      bundleIdentifier: "test.chromium",
      appPath: "/Applications/Test Chromium.app",
      profileDirectoryRelativePath: "Profiles/TestChromium",
      installURL: nil,
      supportsChromeWebStore: true
    )
    let directory = root.appendingPathComponent(
      "Profiles/TestChromium/Default/Extensions/\(BrowserAutomationTarget.extensionId)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    XCTAssertTrue(BrowserAutomationTargetResolver.isExtensionInstalled(in: target, homeDirectory: root))
  }

  func testChatGPTAtlasIsSupportedBrowserTarget() throws {
    let atlas = try XCTUnwrap(
      BrowserAutomationTargetResolver.knownTargets.first { $0.bundleIdentifier == "com.openai.atlas" })
    XCTAssertEqual(atlas.name, "ChatGPT Atlas")
    XCTAssertEqual(atlas.appPath, "/Applications/ChatGPT Atlas.app")
    XCTAssertEqual(
      atlas.profileDirectoryRelativePath,
      "Library/Application Support/com.openai.atlas/browser-data/host"
    )
  }

  func testOldAutoSelectedBrowserDoesNotOverrideDefaultBrowser() {
    let defaults = UserDefaults.standard
    defaults.set("com.google.Chrome", forKey: "playwrightBrowserBundleIdentifier")
    defaults.removeObject(forKey: "playwrightBrowserBundleIdentifierUserSelected")
    defer {
      defaults.removeObject(forKey: "playwrightBrowserBundleIdentifier")
      defaults.removeObject(forKey: "playwrightBrowserBundleIdentifierUserSelected")
    }
    XCTAssertNil(BrowserAutomationTargetStore.selectedBundleIdentifier)
  }

  func testSelectingDifferentBrowserClearsPersistedExtensionToken() {
    let defaults = UserDefaults.standard
    defaults.set("com.google.Chrome", forKey: "playwrightBrowserBundleIdentifier")
    defaults.set(true, forKey: "playwrightBrowserBundleIdentifierUserSelected")
    defaults.set("old-token", forKey: "playwrightExtensionToken")
    defer {
      defaults.removeObject(forKey: "playwrightBrowserBundleIdentifier")
      defaults.removeObject(forKey: "playwrightBrowserBundleIdentifierUserSelected")
      defaults.removeObject(forKey: "playwrightExtensionToken")
    }
    let atlas = BrowserAutomationTarget(
      name: "ChatGPT Atlas",
      bundleIdentifier: "com.openai.atlas",
      appPath: "/Applications/ChatGPT Atlas.app",
      profileDirectoryRelativePath: "Library/Application Support/com.openai.atlas/browser-data/host",
      installURL: nil,
      supportsChromeWebStore: true
    )

    BrowserAutomationTargetStore.select(atlas)

    XCTAssertEqual(BrowserAutomationTargetStore.selectedBundleIdentifier, "com.openai.atlas")
    XCTAssertNil(defaults.string(forKey: "playwrightExtensionToken"))
  }

  func testAgentRuntimeOnlyEnablesPlaywrightWhenBridgeIsConfigured() {
    XCTAssertTrue(
      AgentRuntimeProcess.shouldEnablePlaywrightExtension(
        useExtension: true, token: "token", targetHasExtension: true))
    XCTAssertFalse(
      AgentRuntimeProcess.shouldEnablePlaywrightExtension(
        useExtension: false, token: "token", targetHasExtension: true))
    XCTAssertFalse(
      AgentRuntimeProcess.shouldEnablePlaywrightExtension(
        useExtension: true, token: "", targetHasExtension: true))
    XCTAssertFalse(
      AgentRuntimeProcess.shouldEnablePlaywrightExtension(
        useExtension: true, token: "token", targetHasExtension: false))
  }
}
