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
            "OMI SETTINGS: Failed to open browser URL %@: %@", url.absoluteString,
            error.localizedDescription)
          NSWorkspace.shared.open(url)
        }
      }
      return
    }

    NSWorkspace.shared.open(url)
  }

  func updateDailySummarySettings(enabled: Bool? = nil, hour: Int? = nil) {
    Task {
      do {
        let _ = try await APIClient.shared.updateDailySummarySettings(enabled: enabled, hour: hour)
      } catch {
        logError("Failed to update daily summary settings", error: error)
      }
    }
  }

  func updateNotificationSettings(enabled: Bool? = nil, frequency: Int? = nil) {
    if let enabled {
      // Mirror locally so NotificationService suppresses/resumes proactive notifications
      // immediately when the master toggle flips, even before the backend round-trip completes.
      UserDefaults.standard.set(enabled, forKey: NotificationService.masterEnabledDefaultsKey)
    }
    if let frequency {
      // Mirror locally so NotificationService picks up the new throttle level immediately,
      // even before the backend round-trip completes.
      UserDefaults.standard.set(frequency, forKey: NotificationService.frequencyDefaultsKey)
    }
    Task {
      do {
        let _ = try await APIClient.shared.updateNotificationSettings(
          enabled: enabled, frequency: frequency)
      } catch {
        logError("Failed to update notification settings", error: error)
      }
    }
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
          deleteAccountError = "Your account was deleted, but Omi couldn't sign you out. Quit and reopen Omi."
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
