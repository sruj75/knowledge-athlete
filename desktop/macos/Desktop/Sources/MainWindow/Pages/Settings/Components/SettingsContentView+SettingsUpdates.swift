import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  func openURLInDefaultBrowser(_ url: URL) {
    if let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) {
        _, error in
        if let error {
          NSLog(
            "INTENTIVE SETTINGS: Failed to open browser URL %@: %@", url.absoluteString,
            error.localizedDescription)
          NSWorkspace.shared.open(url)
        }
      }
      return
    }

    NSWorkspace.shared.open(url)
  }

  func updateNotificationSettings(enabled: Bool? = nil, frequency: Int? = nil) {
    let saved = LocalNotificationSettings().update(enabled: enabled, frequency: frequency)
    notificationsEnabled = saved.enabled
    notificationFrequency = saved.frequency
  }

  func updateLanguage(_ language: String) {
    AnalyticsManager.shared.languageChanged(language: language)
  }

  func deleteAccountAndData() {
    guard !isDeletingAccount else { return }

    deleteAccountError = nil
    isDeletingAccount = true
    AnalyticsManager.shared.deleteAccountConfirmed()

    Task {
      do {
        try await APIClient.shared.deleteAccount()
        await MainActor.run {
          appState.stopTranscription()
          ProactiveAssistantsPlugin.shared.stopMonitoring()
        }
        do {
          try await AuthService.shared.signOut()
          isDeletingAccount = false
        } catch {
          deleteAccountError = DesktopLifecycleIdentityCopy.accountDeletedSignOutFailed
          isDeletingAccount = false
        }
      } catch {
        await MainActor.run {
          deleteAccountError = UserFacingErrorPresentation.message(for: error, while: .accountDeletion)
          isDeletingAccount = false
        }
      }
    }
  }

}
