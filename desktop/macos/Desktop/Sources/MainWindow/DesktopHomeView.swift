import AppKit
import OmiTheme
import SwiftUI

private struct AnySendableBox: @unchecked Sendable { let value: Any? }

/// Decides whether a persisted capture intent needs its runtime service restored.
///
/// Intent is stored independently from the running services. A fresh launch and a
/// settings sync therefore both need to reconcile the two states instead of using
/// a one-time readiness check as the source of truth.
enum PersistedCaptureLaunchPolicy {
  static func transcriptionModeToRestore(
    intentEnabled: Bool,
    isTranscribing: Bool,
    persistedMode: AssistantSettings.SystemAudioCaptureMode,
    onboardingExitOutcome: OnboardingPersistedExitOutcome?
  ) -> AssistantSettings.SystemAudioCaptureMode? {
    guard onboardingExitOutcome != .skipped, intentEnabled, !isTranscribing else { return nil }
    return persistedMode
  }

  static func shouldStartScreenAnalysis(
    intentEnabled: Bool,
    isMonitoring: Bool,
    onboardingExitOutcome: OnboardingPersistedExitOutcome?
  ) -> Bool {
    onboardingExitOutcome != .skipped && intentEnabled && !isMonitoring
  }
}

// MARK: - NSHostingView sizingOptions access

/// Protocol to access sizingOptions on any NSHostingView<Content> regardless of the generic parameter.
/// NSHostingView is generic so we can't cast to it without knowing Content.
/// This protocol + extension lets us access sizingOptions through existential dispatch.
@MainActor
private protocol HostingSizingConfigurable: AnyObject {
  var sizingOptions: NSHostingSizingOptions { get set }
}
extension NSHostingView: HostingSizingConfigurable {}

struct DesktopHomeView: View {
  private static let pageNavigationAnimation = Animation.easeOut(duration: 0.08)

  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModelContainer = ViewModelContainer()
  @ObservedObject private var authState = AuthState.shared
  @ObservedObject private var apiKeyService = APIKeyService.shared
  @ObservedObject private var updatePolicyManager = DesktopUpdatePolicyManager.shared
  @State private var selectedIndex: Int = {
    if OMIApp.launchMode == .rewind { return DesktopDestination.rewind.rawValue }
    return DesktopDestination.home.rawValue
  }()
  @AppStorage(MemoryHubDestination.storageKey) private var memoryDestinationRawValue =
    MemoryHubDestination.memories.rawValue

  // Settings sidebar state
  @State private var selectedSettingsSection: SettingsContentView.SettingsSection = .general
  @State private var highlightedSettingId: String? = nil
  @State private var previousIndexBeforeSettings: Int = 0
  @State private var logoPulse = false
  @State private var lastActivationRefresh = Date.distantPast
  @State private var proactiveMonitoringStartGate = RetryableDelayedStartGate()
  @State private var isWaitingForScreenAnalysisKeys = false
  // Anchor for the proactive-monitoring warmup budget. Captured at view
  // creation (≈ launch) so the delay is spent once per session, not once per
  // trigger — see StartupWarmupPolicy.remainingProactiveAssistantsStartDelay.
  @State private var proactiveMonitoringWarmupAnchor = Date()
  @State private var didScheduleMemoryHubWarmup = false

  // Pre-loaded hero logo to avoid NSImage init crashes during SwiftUI body evaluation
  private static let heroLogoImage: NSImage? = {
    guard let url = Bundle.resourceBundle.url(forResource: "herologo", withExtension: "png"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return NSImage(data: data)
  }()

  /// Whether we're currently viewing the settings page
  private var isInSettings: Bool {
    selectedIndex == DesktopDestination.settings.rawValue
  }

  var body: some View {
    Group {
      if authState.isRestoringAuth {
        // State 0: Restoring auth session - show loading
        VStack(spacing: OmiSpacing.lg) {
          if let nsImage = Self.heroLogoImage {
            Image(nsImage: nsImage)
              .resizable()
              .scaledToFit()
              .frame(width: 64, height: 64)
          }
          ProgressView()
            .scaleEffect(0.8)
            .tint(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
          log("DesktopHomeView: Showing auth loading splash")
        }
      } else if authState.sessionPhase == .recoveryRequired {
        SessionRecoveryView()
          .onAppear {
            log("DesktopHomeView: Showing recoverable auth state")
          }
      } else if !authState.isSignedIn {
        // State 1: Not signed in - show sign in
        SignInView(authState: authState)
          .onAppear {
            log("DesktopHomeView: Showing SignInView (not signed in)")
          }
      } else if !hasCompletedOnboardingAtAuthorityRead {
        // State 2: Signed in but onboarding not complete
        if shouldSkipOnboarding() {
          Color.clear.onAppear {
            log("DesktopHomeView: --skip-onboarding flag detected, skipping onboarding")
            appState.hasCompletedOnboarding = true
          }
        } else {
          SBOnboardingView(
            appState: appState,
            chatProvider: viewModelContainer.chatProvider,
            onComplete: nil
          )
          .onAppear {
            log("DesktopHomeView: Showing SBOnboardingView (signed in, not onboarded)")
          }
        }
      } else {
        // State 3: Signed in and onboarded - show main content
        ZStack {
          // After onboarding completes, navigate to Tasks page
          Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
              if UserDefaults.standard.bool(forKey: .onboardingJustCompleted) {
                UserDefaults.standard.removeObject(forKey: .onboardingJustCompleted)
                log("DesktopHomeView: Onboarding just completed — landing on Home")
                // Land on Home in the chat-first layout.
                selectedIndex = DesktopDestination.home.rawValue
              }
            }
          mainContent
            .opacity(viewModelContainer.isInitialLoadComplete ? 1 : 0)
            .overlay {
              if appState.showUsageLimitPopup {
                UsageLimitPopupView(
                  reason: appState.usageLimitReason,
                  billingAvailability: appState.billingAvailability,
                  onCheckout: {
                    appState.showUsageLimitPopup = false
                    selectedSettingsSection = .planUsage
                    // Plan and Usage now lives below Account on the merged
                    // "Account & Plan" page — scroll straight to the plan card.
                    highlightedSettingId = "planusage.current"
                    OmiMotion.withGated(Self.pageNavigationAnimation) {
                      selectedIndex = DesktopDestination.settings.rawValue
                    }
                  },
                  onDismiss: {
                    appState.dismissUsageLimitPopup()
                  }
                )
              }
            }
            .overlay(alignment: .top) {
              if let policy = updatePolicyManager.visiblePolicy, !policy.isRequired {
                DesktopUpdatePolicyBanner(
                  policy: policy,
                  onDownload: { updatePolicyManager.openDownload(policy) },
                  onDismiss: { updatePolicyManager.dismiss(policy) }
                )
                .padding(.top, OmiSpacing.md)
                .padding(.horizontal, OmiSpacing.xl)
                .transition(.move(edge: .top).combined(with: .opacity))
              }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showUsageLimitPopup)) { notification in
              let reason = notification.userInfo?["reason"] as? String ?? ""
              appState.triggerUsageLimitPopup(reason: reason)
            }
            .onAppear {
              log("DesktopHomeView: Showing mainContent (signed in and onboarded)")
              updatePolicyManager.refresh(force: true)
              // Check all permissions on launch
              appState.checkAllPermissions()

              restorePersistedCaptureServices(reason: "launch")

              // Set up floating control bar. Product invariant: normal signed-in
              // launches must show the enabled bar immediately; hide-until-PTT is
              // only for explicit onboarding/demo/minimal-mode contexts.
              FloatingControlBarManager.shared.setup(
                appState: appState, chatProvider: viewModelContainer.chatProvider)
              FloatingControlBarManager.shared.presentForLaunch(context: .normalSignedInDesktop)

              // Set up push-to-talk voice input
              if let barState = FloatingControlBarManager.shared.barState {
                PushToTalkManager.shared.setup(barState: barState)
              }
            }
            .task {
              // Trigger eager data loading when main content appears
              await viewModelContainer.loadAllData()
              scheduleMemoryHubWarmup()
            }
            // Refresh conversations when app becomes active (e.g. switching back from another app)
            .onReceive(
              NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
              // Cooldown: only refresh conversations if last activation was 60+ seconds ago
              let now = Date()
              if PollingConfig.shouldAllowActivationRefresh(now: now, lastRefresh: lastActivationRefresh) {
                lastActivationRefresh = now
                Task { await appState.refreshConversations() }
              }
              updatePolicyManager.refresh()
              // Reconcile persisted intent after returning from System Settings or
              // after a runtime service stopped while the app was inactive.
              restorePersistedCaptureServices(reason: "app active")
            }
            .onChange(of: apiKeyService.isLoaded) { _, loaded in
              guard loaded else { return }
              log("DesktopHomeView: API keys loaded — retrying deferred services")
              restorePersistedCaptureServices(reason: "key load")
            }
            .onReceive(NotificationCenter.default.publisher(for: .assistantSettingsDidChange)) { _ in
              reconcileCaptureServicesAfterLocalSettingsChange()
            }
            // Cmd+R: refresh all data (conversations, chat, tasks, memories)
            .onReceive(NotificationCenter.default.publisher(for: .refreshAllData)) { _ in
              Task { await appState.refreshConversations() }
            }
            // The shared sign-out boundary has already stopped capture and reset
            // setup. This observer releases the remaining account-scoped UI state.
            .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
              log("DesktopHomeView: userDidSignOut — releasing account-scoped UI state")
              resetSessionScopedStartupWarmups()
              appState.conversationRepository.reset()
              appState.folders = []
              appState.selectedFolderId = nil
              appState.selectedDateFilter = nil
              appState.showStarredOnly = false
              appState.totalConversationsCount = nil
              appState.conversationsError = nil
              appState.isLoadingConversations = false
              appState.isLoadingFolders = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetOnboardingRequested)) { _ in
              log(
                "DesktopHomeView: resetOnboardingRequested — clearing live onboarding state for current app"
              )
              resetSessionScopedStartupWarmups()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
              log("DesktopHomeView: app terminating — cancelling startup warmups")
              resetSessionScopedStartupWarmups()
            }
            // Handle transcription toggle from menu bar
            .onReceive(NotificationCenter.default.publisher(for: .toggleTranscriptionRequested)) {
              notification in
              if let enabled = notification.userInfo?["enabled"] as? Bool {
                log("DesktopHomeView: Menu bar toggled transcription: \(enabled)")
                if enabled {
                  appState.startTranscription()
                } else {
                  appState.stopTranscription()
                }
              }
            }
          if !viewModelContainer.isInitialLoadComplete {
            VStack(spacing: OmiSpacing.xxl) {
              if let nsImage = Self.heroLogoImage {
                Image(nsImage: nsImage)
                  .resizable()
                  .scaledToFit()
                  .frame(width: 72, height: 72)
                  .scaleEffect(logoPulse ? 1.08 : 1.0)
                  .opacity(logoPulse ? 1.0 : 0.7)
                  .omiAnimation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: logoPulse
                  )
                  .onAppear { logoPulse = true }
              }

              Text(viewModelContainer.initStatusMessage)
                .scaledFont(size: OmiType.body, weight: .medium)
                .foregroundColor(OmiColors.textTertiary)

              ProgressView()
                .scaleEffect(0.8)
                .tint(OmiColors.accent.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OmiColors.backgroundPrimary)
            .transition(.opacity.animation(OmiMotion.gated(.easeOut(duration: 0.3))))
          }

          if let policy = updatePolicyManager.visiblePolicy, policy.isRequired {
            Color.black.opacity(0.62)
              .ignoresSafeArea()
              .zIndex(20)
            DesktopRequiredUpdatePrompt(
              policy: policy,
              onDownload: { updatePolicyManager.openDownload(policy) }
            )
            .zIndex(21)
          }
        }
      }
    }
    .background(OmiColors.backgroundPrimary)
    .frame(minWidth: DesktopWindowLayoutPolicy.width, minHeight: DesktopWindowLayoutPolicy.height)
    .preferredColorScheme(.dark)
    .tint(OmiColors.accent)
    .onAppear {
      log(
        "DesktopHomeView: View appeared - isSignedIn=\(authState.isSignedIn), hasCompletedOnboarding=\(appState.hasCompletedOnboarding)"
      )
      // Register Geist/Geist Mono for the sign-in + conversational onboarding surfaces.
      // (Kept out of OmiApp to respect the product-file line-count ratchet.)
      OmiFontRegistration.registerAll()
      // Drive the notch "moments" (live receipts + conversation-end) off real state.
      NotchMomentsCoordinator.shared.start(appState: appState)
      // Force dark appearance and disable minSize computation on NSHostingView.
      // By default, every @Published change triggers
      // updateWindowContentSizeExtremaIfNecessary() → minSize() → sizeThatFits()
      // which traverses the ENTIRE view tree (~200 samples per window per trigger).
      // Removing .minSize from sizingOptions prevents this full-tree traversal.
      // The window's min size is enforced at the AppKit level instead.
      enforceMainWindowMinimumSize()
      // SwiftUI's automatic resizability later re-derives the window min from content
      // extrema and resets our pin, after which the window can be dragged small enough
      // to hide content. Re-pin on every live resize so AppKit keeps clamping the drag.
      installMinimumSizeGuardIfNeeded()
      reportAutomationState()
    }
    .onChange(of: selectedIndex) { _, _ in
      // Page nav recreates the content hosting view with default sizingOptions, which
      // resets the window min — re-pin + re-disable to hold the minimum.
      enforceMainWindowMinimumSize()
      reportAutomationState()
    }
    .onChange(of: selectedSettingsSection) { _, _ in reportAutomationState() }
    .onChange(of: highlightedSettingId) { _, _ in reportAutomationState() }
    .onChange(of: authState.isSignedIn) { _, _ in reportAutomationState() }
    .onChange(of: authState.isRestoringAuth) { _, _ in reportAutomationState() }
    .onChange(of: appState.hasCompletedOnboarding) { _, _ in reportAutomationState() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      enforceMainWindowMinimumSize()
      reportAutomationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
      reportAutomationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .desktopAutomationNavigateRequested)) {
      notification in
      handleAutomationNavigation(notification)
    }
    .onReceive(NotificationCenter.default.publisher(for: .navigateToChat)) { _ in
      // The global shortcut / notch "Ask Intentive" opens the continuous chat, which
      // lives on the chat-first home. DashboardPage focuses the input when it's
      // already mounted; if we're on another tab, switch home first and re-emit
      // so the now-mounted page catches it. Guard on the tab to avoid a loop.
      if selectedIndex != DesktopDestination.home.rawValue {
        selectedIndex = DesktopDestination.home.rawValue
        DispatchQueue.main.async {
          NotificationCenter.default.post(name: .navigateToChat, object: nil)
        }
      }
    }
    // "Continue in Intentive" from the floating bar: switch to the Home tab; the
    // dashboard consumes the pending request and opens the chat panel.
    .onReceive(NotificationCenter.default.publisher(for: .openMainChatRequested)) { _ in
      selectedIndex = DesktopDestination.home.rawValue
    }
  }

  private func enforceMainWindowMinimumSize() {
    let minimumContentSize = DesktopWindowLayoutPolicy.minimumContentSize
    DispatchQueue.main.async {
      for window in NSApp.windows where window.title.lowercased().hasPrefix("intentive") {
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentMinSize = minimumContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size

        let currentContentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let widthDelta = max(0, minimumContentSize.width - currentContentSize.width)
        let heightDelta = max(0, minimumContentSize.height - currentContentSize.height)
        if widthDelta > 0 || heightDelta > 0 {
          var frame = window.frame
          frame.size.width += widthDelta
          frame.size.height += heightDelta
          frame.origin.y -= heightDelta
          window.setFrame(frame, display: true, animate: false)
        }

        // Remove .minSize from hosting view's sizingOptions.
        // Search contentView itself + all descendants.
        Self.disableMinSizeComputation(in: window)
      }
    }
  }

  /// Re-pin the window minimum on every live resize. SwiftUI's `.automatic` window
  /// resizability periodically recomputes content-size extrema and overwrites the
  /// one-shot pin from `enforceMainWindowMinimumSize()`, after which the window can be
  /// dragged small enough to hide content. Observing `didResize` and re-pinning keeps
  /// AppKit clamping the live drag at the minimum. Installed once for the app's lifetime.
  private static var minimumSizeGuardInstalled = false
  private func installMinimumSizeGuardIfNeeded() {
    guard !Self.minimumSizeGuardInstalled else { return }
    Self.minimumSizeGuardInstalled = true
    let minimumContentSize = DesktopWindowLayoutPolicy.minimumContentSize
    NotificationCenter.default.addObserver(
      forName: NSWindow.didResizeNotification, object: nil, queue: .main
    ) { notification in
      let objectBox = AnySendableBox(value: notification.object)
      MainActor.assumeIsolated {
        guard let window = objectBox.value as? NSWindow,
          window.title.lowercased().hasPrefix("intentive")
        else { return }
        let frameMin = window.frameRect(
          forContentRect: NSRect(origin: .zero, size: minimumContentSize)
        ).size
        if window.contentMinSize != minimumContentSize { window.contentMinSize = minimumContentSize }
        if window.minSize != frameMin { window.minSize = frameMin }
      }
    }
  }

  /// Recursively find all NSHostingViews in a window and set sizingOptions to [],
  /// disabling ALL size computations to prevent full-tree sizeThatFits() traversals.
  /// Window min/max sizes are enforced at the AppKit level via NSWindow.minSize instead.
  private static func disableMinSizeComputation(in window: NSWindow) {
    func visit(_ view: NSView) {
      if let hosting = view as? any HostingSizingConfigurable {
        let before = hosting.sizingOptions
        if before != [] {
          hosting.sizingOptions = []
        }
      }
      for subview in view.subviews {
        visit(subview)
      }
    }
    if let contentView = window.contentView {
      visit(contentView)
    }
  }

  /// The constant floating top bar (navigation + Capture/Listening)
  /// replaces the old left nav rail. It shows on every main content page —
  /// including Settings and permission recovery, whose pages have no separate
  /// exit chrome, so the bar's nav pills remain the way out.
  private var showsTopBar: Bool {
    DesktopNavigationPolicy.showsTopBar(forRawValue: selectedIndex)
  }

  private var currentAppStateLabel: String {
    if authState.isRestoringAuth { return "restoring_auth" }
    if authState.sessionPhase == .recoveryRequired { return "auth_recovery" }
    if !authState.isSignedIn { return "signed_out" }
    if !appState.hasCompletedOnboarding { return "onboarding" }
    return "main"
  }

  /// Preserve the existing AppStorage winner while observing disagreement at
  /// the actual product/onboarding gate. This read still runs when the completed
  /// flag prevents SBOnboardingModel from mounting.
  private var hasCompletedOnboardingAtAuthorityRead: Bool {
    let completed = appState.hasCompletedOnboarding
    let savedRaw = UserDefaults.standard.integer(forKey: SBOnboardingModel.resumeStepKey)
    let resolution = OnboardingSetupAuthorityPolicy.resolve(
      hasCompletedOnboarding: completed,
      hasActiveStage: false,
      hasPersistedResume: savedRaw > SBOnboardingModel.Step.promise.rawValue
        && SBOnboardingModel.Step.resumeTarget(forPersistedRawValue: savedRaw) != nil,
      hasActiveJournal: viewModelContainer.chatProvider.isOnboarding)
    for disagreement in resolution.disagreements {
      DesktopDiagnosticsManager.shared.recordStateAuthoritySignal(
        seam: .onboardingSetupState,
        from: disagreement.source.rawValue,
        to: disagreement.target.rawValue,
        direction: disagreement.direction)
    }
    return resolution.hasCompletedOnboarding
  }

  private func reportAutomationState() {
    guard DesktopAutomationLaunchOptions.isEnabled else { return }

    let currentWindow = NSApp.windows.first(where: {
      $0.title.lowercased().hasPrefix("intentive") && $0.isVisible
    })
    let onDashboard = selectedIndex == DesktopDestination.home.rawValue
    let priorHomeMode = DesktopAutomationStateStore.shared.current().homeMode
    let snapshot = DesktopAutomationSnapshot(
      bridgeEnabled: true,
      bridgePort: DesktopAutomationLaunchOptions.port,
      bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
      appState: currentAppStateLabel,
      selectedTab: DesktopNavigationPolicy.destination(forRawValue: selectedIndex)?.title,
      selectedTabIndex: selectedIndex,
      selectedSettingsSection: isInSettings ? selectedSettingsSection.rawValue : nil,
      highlightedSettingId: highlightedSettingId,
      homeMode: onDashboard ? (priorHomeMode ?? "hub") : nil,
      hasCompletedOnboarding: appState.hasCompletedOnboarding,
      isSignedIn: authState.isSignedIn,
      isRestoringAuth: authState.isRestoringAuth,
      isAppActive: NSApp.isActive,
      mainWindowTitle: currentWindow?.title,
      floatingBarVisible: FloatingControlBarManager.shared.automationState.isVisible,
      askIntentiveOpen: FloatingControlBarManager.shared.automationState.isAskOmiOpen,
      askIntentiveFocused: FloatingControlBarManager.shared.automationState.isAskOmiFocused,
      floatingBarFrame: FloatingControlBarManager.shared.automationState.frame,
      floatingBarVoiceListening: FloatingControlBarManager.shared.automationState.isVoiceListening,
      floatingBarVoiceResponseActive: FloatingControlBarManager.shared.automationState.isVoiceResponseActive,
      floatingBarUsesNotchIsland: FloatingControlBarManager.shared.automationState.usesNotchIsland,
      updatedAt: ISO8601DateFormatter().string(from: Date())
    )

    DesktopAutomationStateStore.shared.update(snapshot)
  }

  private func handleAutomationNavigation(_ notification: Notification) {
    guard DesktopAutomationLaunchOptions.isEnabled else { return }
    guard let resolution = notification.userInfo?["route"] as? DesktopNavigationResolution else {
      return
    }
    if let section = notification.userInfo?["settingsSection"]
      as? SettingsContentView.SettingsSection
    {
      selectedSettingsSection = section
    }
    highlightedSettingId =
      (notification.userInfo?["highlightedSetting"] as? SettingsDestination)?.rawValue

    switch resolution.effect {
    case .none:
      break
    case .openHomeChat:
      MainChatNavigationRequestStore.shared.request()
    case .selectMemory(let destination):
      memoryDestinationRawValue = destination.rawValue
    case .selectInsights(let segment):
      InsightsHubNavigationStore.shared.request(segment: segment)
    }
    selectedIndex = resolution.destination.rawValue

    reportAutomationState()
  }

  /// Update store auto-refresh based on which page is visible

  private func resetSessionScopedStartupWarmups() {
    viewModelContainer.resetStartupState()
    didScheduleMemoryHubWarmup = false
    proactiveMonitoringStartGate.finishAttempt()
  }

  private func scheduleMemoryHubWarmup() {
    guard !didScheduleMemoryHubWarmup else { return }
    didScheduleMemoryHubWarmup = true

    let scheduled = viewModelContainer.scheduleSessionWarmup(
      id: .conversationWarmup,
      delay: StartupWarmupPolicy.conversationWarmupDelay,
      onCancel: { didScheduleMemoryHubWarmup = false }
    ) {
      async let conversations: Void = loadConversationsIfNeeded()
      async let folders: Void = loadFoldersIfNeeded()
      _ = await (conversations, folders)
    }
    if !scheduled { didScheduleMemoryHubWarmup = false }
  }

  private func loadConversationsIfNeeded() async {
    guard appState.conversations.isEmpty else { return }
    await appState.loadConversations()
  }

  private func loadFoldersIfNeeded() async {
    guard appState.folders.isEmpty else { return }
    await appState.loadFolders()
  }

  private func scheduleProactiveMonitoringStart(reason: String) {
    guard proactiveMonitoringStartGate.reserve() else { return }

    let delay = StartupWarmupPolicy.remainingProactiveAssistantsStartDelay(
      elapsedSinceLaunch: Date().timeIntervalSince(proactiveMonitoringWarmupAnchor))
    log(
      "DesktopHomeView: Scheduling screen analysis start in \(String(format: "%.1f", delay))s (\(reason))"
    )
    let scheduled = viewModelContainer.scheduleSessionWarmup(
      id: .proactiveAssistantsStart,
      delay: delay,
      onCancel: { proactiveMonitoringStartGate.finishAttempt() }
    ) {
      let plugin = ProactiveAssistantsPlugin.shared
      guard AssistantSettings.shared.screenAnalysisEnabled, !plugin.isMonitoring else {
        proactiveMonitoringStartGate.finishAttempt()
        return
      }
      guard APIKeyService.keysAvailable else {
        proactiveMonitoringStartGate.finishAttempt()
        log("DesktopHomeView: Screen analysis still deferred after \(reason) — API keys not yet loaded")
        return
      }

      plugin.startMonitoring { success, error in
        Task { @MainActor in
          proactiveMonitoringStartGate.finishAttempt()
          if success {
            log("DesktopHomeView: Screen analysis started (\(reason), delayed)")
          } else {
            log(
              "DesktopHomeView: Screen analysis failed to start (\(reason)): \(error ?? "unknown") — setting remains enabled for next launch"
            )
          }
        }
      }
    }
    if !scheduled { proactiveMonitoringStartGate.finishAttempt() }
  }

  private func restorePersistedCaptureServices(reason: String) {
    let settings = AssistantSettings.shared
    let onboardingExitOutcome = OnboardingExitPersistence.outcome()
    if let mode = PersistedCaptureLaunchPolicy.transcriptionModeToRestore(
      intentEnabled: settings.transcriptionEnabled,
      isTranscribing: appState.isTranscribing,
      persistedMode: settings.systemAudioCaptureMode,
      onboardingExitOutcome: onboardingExitOutcome
    ) {
      log("DesktopHomeView: Restoring transcription in \(mode.rawValue) mode from persisted intent (\(reason))")
      // Local transcription does not require remote API keys. AppState owns the
      // permission and provider checks, so it remains the single start boundary.
      appState.startTranscription()
    }

    let plugin = ProactiveAssistantsPlugin.shared
    guard
      PersistedCaptureLaunchPolicy.shouldStartScreenAnalysis(
        intentEnabled: settings.screenAnalysisEnabled,
        isMonitoring: plugin.isMonitoring,
        onboardingExitOutcome: onboardingExitOutcome
      )
    else { return }

    guard APIKeyService.keysAvailable else {
      waitForScreenAnalysisKeys(reason: reason)
      return
    }

    plugin.refreshScreenRecordingPermission()
    guard plugin.hasScreenRecordingPermission else {
      log("DesktopHomeView: Screen recording permission unavailable; retaining capture intent (\(reason))")
      return
    }
    scheduleProactiveMonitoringStart(reason: reason)
  }

  private func waitForScreenAnalysisKeys(reason: String) {
    guard !isWaitingForScreenAnalysisKeys else { return }
    isWaitingForScreenAnalysisKeys = true
    log("DesktopHomeView: Deferring screen analysis until API keys load (\(reason))")
    Task { @MainActor in
      await APIKeyService.shared.waitForKeys()
      isWaitingForScreenAnalysisKeys = false
      guard APIKeyService.keysAvailable else {
        log("DesktopHomeView: API keys remain unavailable; retaining capture intent")
        return
      }
      restorePersistedCaptureServices(reason: "key wait completed")
    }
  }

  private func reconcileCaptureServicesAfterLocalSettingsChange() {
    let plugin = ProactiveAssistantsPlugin.shared
    if !AssistantSettings.shared.screenAnalysisEnabled, plugin.isMonitoring {
      log("DesktopHomeView: Stopping screen analysis after local settings change")
      plugin.stopMonitoring()
    }
    restorePersistedCaptureServices(reason: "local settings change")
  }

  private func updateStoreActivity(for index: Int) {
    viewModelContainer.tasksStore.isActive =
      index == DesktopDestination.home.rawValue || index == DesktopDestination.tasks.rawValue
    viewModelContainer.memoriesViewModel.isActive =
      index == DesktopDestination.memory.rawValue || index == DesktopDestination.memories.rawValue
  }

  private var settingsSidebar: some View {
    SettingsSidebar(
      selectedSection: $selectedSettingsSection,
      highlightedSettingId: $highlightedSettingId,
      onBack: {
        OmiMotion.withGated(Self.pageNavigationAnimation) {
          selectedIndex =
            previousIndexBeforeSettings == DesktopDestination.settings.rawValue
            ? DesktopDestination.home.rawValue
            : previousIndexBeforeSettings
        }
      }
    )
    .fixedSize(horizontal: true, vertical: false)
    .clipped()
  }

  // Main content area with rounded container.
  private var mainContentContainer: some View {
    ZStack {
      // Content container background — clean flat neutral dark (no gradient).
      RoundedRectangle(cornerRadius: OmiChrome.windowRadius, style: .continuous)
        .fill(Color(red: 0.050, green: 0.052, blue: 0.059))
        .overlay(
          RoundedRectangle(cornerRadius: OmiChrome.windowRadius, style: .continuous)
            .stroke(OmiColors.border.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 14)

      // Page content - switch recreates views on tab change
      // Extracted into a separate struct so that pages like TasksPage
      // are not re-rendered when AppState publishes unrelated changes.
      VStack(spacing: 0) {
        // Constant floating top bar — primary nav and the
        // Capture/Listening controls. Replaces the old left nav rail. Some
        // full-screen destinations hide it through showsTopBar.
        if showsTopBar {
          DesktopTopBar(
            selectedIndex: $selectedIndex,
            memoryDestinationRawValue: $memoryDestinationRawValue,
            appState: appState,
            onRewind: {
              OmiMotion.withGated(Self.pageNavigationAnimation) {
                selectedIndex = DesktopDestination.rewind.rawValue
              }
            }
          )
          .zIndex(1)
        }

        PageContentView(
          selectedIndex: selectedIndex,
          appState: appState,
          viewModelContainer: viewModelContainer,
          memoryDestinationRawValue: $memoryDestinationRawValue,
          selectedSettingsSection: $selectedSettingsSection,
          highlightedSettingId: $highlightedSettingId,
          selectedTabIndex: $selectedIndex
        )
      }
      .onExitCommand {
        navigateHomeOnEscapeIfNeeded()
      }
      .clipShape(RoundedRectangle(cornerRadius: OmiChrome.windowRadius, style: .continuous))
    }
    .padding(OmiSpacing.md)
  }

  private var mainContentWithOverlays: some View {
    HStack(spacing: 0) {
      if isInSettings {
        settingsSidebar
      }
      mainContentContainer
    }
  }

  // The full `.onReceive`/`.onChange`/`.onAppear` chain below is, together with
  // `mainContentWithOverlays`, one enormous SwiftUI expression for the `some
  // View` type checker. Splitting it across several intermediate `some View`
  // properties (rather than one long chain) keeps each link small enough to
  // type-check in reasonable time — see "unable to type-check this expression"
  // in Swift's SwiftUI diagnostics for this well-known compiler limitation.
  private var mainContentWithNavigationNotifications: some View {
    mainContentWithOverlays
      .onReceive(NotificationCenter.default.publisher(for: .navigateToRewindSettings)) { _ in
        // Set the section directly and navigate to settings
        selectedSettingsSection = .rewind
        selectedIndex = DesktopDestination.settings.rawValue
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToTaskSettings)) { _ in
        // Navigate to settings > advanced > task assistant subsection
        selectedSettingsSection = .advanced
        selectedIndex = DesktopDestination.settings.rawValue
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToFloatingBarSettings)) { _ in
        selectedSettingsSection = .floatingBar
        selectedIndex = DesktopDestination.settings.rawValue
      }
  }

  private var mainContentWithRewindAndMemoryNotifications: some View {
    mainContentWithNavigationNotifications
      .onReceive(NotificationCenter.default.publisher(for: .navigateToAdvancedAISettings)) { _ in
        selectedSettingsSection = .advanced
        selectedIndex = DesktopDestination.settings.rawValue
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToRewind)) { _ in
        // Navigate to Rewind through its retained raw destination (7).
        log(
          "DesktopHomeView: Received navigateToRewind notification, navigating to Rewind (index \(DesktopDestination.rewind.rawValue))"
        )
        selectedIndex = DesktopDestination.rewind.rawValue
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToRewindNotes)) { _ in
        selectedIndex = DesktopDestination.rewind.rawValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          NotificationCenter.default.post(name: .expandRewindTranscript, object: nil)
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToChat)) { _ in
        // Chat now lives on the Dashboard page.
        selectedIndex = DesktopDestination.home.rawValue
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToTasks)) { _ in
        selectedIndex = DesktopDestination.tasks.rawValue
      }
  }

  private var mainContentWithSidebarItemNotifications: some View {
    mainContentWithRewindAndMemoryNotifications
      .onReceive(NotificationCenter.default.publisher(for: .navigateToSidebarItem)) { notification in
        if let rawValue = notification.userInfo?["rawValue"] as? Int,
          let item = DesktopNavigationPolicy.destination(forRawValue: rawValue)
        {
          if let destination = MemoryHubDestination.destination(for: item) {
            memoryDestinationRawValue = destination.rawValue
            selectedIndex = DesktopDestination.memory.rawValue
          } else {
            if item == .insights {
              InsightsHubNavigationStore.shared.request(segment: .insights)
            }
            selectedIndex = item.rawValue
          }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .desktopAutomationOpenConversationRequested)) { _ in
        // Conversations now live behind the Memory menu. Route at
        // the owning shell before the detail page mounts; its retained request is
        // then consumed by ConversationsPage on appearance.
        memoryDestinationRawValue = MemoryHubDestination.conversations.rawValue
        selectedIndex = DesktopDestination.memory.rawValue
      }
  }

  private var mainContent: some View {
    mainContentWithSidebarItemNotifications
      .onChange(of: selectedIndex) { oldValue, newValue in
        // Track the previous index when navigating to settings
        if newValue == DesktopDestination.settings.rawValue
          && oldValue != DesktopDestination.settings.rawValue
        {
          previousIndexBeforeSettings = oldValue
        }
        // Only auto-refresh stores when their pages are visible
        updateStoreActivity(for: newValue)
      }
      .onAppear {
        updateStoreActivity(for: selectedIndex)
      }
  }

  private func navigateHomeOnEscapeIfNeeded() {
    guard let item = DesktopNavigationPolicy.destination(forRawValue: selectedIndex) else { return }
    guard DesktopNavigationPolicy.returnsHomeOnUnhandledEscape(from: item) else { return }
    OmiMotion.withGated(Self.pageNavigationAnimation) {
      selectedIndex = DesktopDestination.home.rawValue
    }
  }
}

/// Isolated page content switch — does NOT observe AppState or ViewModelContainer
/// as @ObservedObject, so pages like TasksPage won't re-render when unrelated
/// AppState properties (conversations, permissions, etc.) change.
/// A minimal SB-styled segmented toggle used to fold two related surfaces into
/// one tab (Conversations/Memories, Focus/Insights).
private struct HubSegmentedControl: View {
  @Environment(\.sbTheme) private var sb
  @Binding var selection: InsightsHubSegment

  var body: some View {
    HStack(spacing: 4) {
      ForEach(InsightsHubSegment.allCases, id: \.rawValue) { segment in
        Button {
          withAnimation(.easeOut(duration: 0.15)) { selection = segment }
        } label: {
          Text(segment == .insights ? "Insights" : "Focus")
            .geist(size: 13, weight: selection == segment ? .semibold : .medium)
            .foregroundStyle(selection == segment ? sb.ink : sb.ink(.w45))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == segment ? sb.ink(.w1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sb.ink(.w04))
    )
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct MemoryHubPage: View {
  let appState: AppState
  let viewModelContainer: ViewModelContainer
  @ObservedObject var memoriesViewModel: MemoriesViewModel
  @ObservedObject private var conversationDetailState = ConversationDetailAutomationState.shared
  @Binding var destinationRawValue: Int

  private var destination: MemoryHubDestination {
    MemoryHubDestination(rawValue: destinationRawValue) ?? .memories
  }

  var body: some View {
    switch destination {
    case .memories:
      adaptiveContent(
        MemoriesPage(viewModel: viewModelContainer.memoriesViewModel),
        conversationID: viewModelContainer.memoriesViewModel.linkedConversation?.id
      )
    case .conversations:
      ConversationsPageHost(appState: appState)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func adaptiveContent<Content: View>(
    _ content: Content,
    conversationID: String?
  ) -> some View {
    let usesAvailableWidth = MemoryHubLayoutPolicy.usesAvailableWidth(
      conversationID: conversationID,
      presentedConversationID: conversationDetailState.openConversationId,
      transcriptDrawerOpen: conversationDetailState.transcriptDrawerOpen,
      memoryDetailOpen: memoriesViewModel.selectedMemory != nil
    )

    return
      content
      .frame(
        maxWidth: usesAvailableWidth ? .infinity : MemoryHubLayoutPolicy.readableContentWidth,
        maxHeight: .infinity
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.easeInOut(duration: 0.22), value: usesAvailableWidth)
  }
}

/// Canonical Insights tab — Insight history and Focus history share one surface.
private struct InsightsHubPage: View {
  @ObservedObject private var navigation = InsightsHubNavigationStore.shared
  @State private var segment: InsightsHubSegment = .insights
  @State private var requestedInsightID: String?

  var body: some View {
    VStack(spacing: 0) {
      HubSegmentedControl(selection: $segment)
        .padding(.top, 22)
        .padding(.horizontal, 28)
        .padding(.bottom, 4)

      if segment == .insights {
        InsightPage(
          requestedInsightID: requestedInsightID,
          onRequestConsumed: { requestedInsightID = nil }
        )
      } else {
        FocusPage()
      }
    }
    .onAppear(perform: consumePendingRequest)
    .onReceive(navigation.$pendingRequest) { request in
      guard request != nil else { return }
      consumePendingRequest()
    }
    .alert(
      "Insight unavailable",
      isPresented: Binding(
        get: { navigation.unavailableMessage != nil },
        set: { if !$0 { navigation.dismissUnavailableMessage() } }
      )
    ) {
      Button("OK") { navigation.dismissUnavailableMessage() }
    } message: {
      Text("This Insight is no longer available for the current account.")
    }
  }

  private func consumePendingRequest() {
    guard let request = navigation.consume() else { return }
    segment = request.segment
    requestedInsightID = request.insightID
  }
}

private struct PageContentView: View {
  let selectedIndex: Int
  let appState: AppState
  let viewModelContainer: ViewModelContainer
  @Binding var memoryDestinationRawValue: Int
  @Binding var selectedSettingsSection: SettingsContentView.SettingsSection
  @Binding var highlightedSettingId: String?
  @Binding var selectedTabIndex: Int

  /// The list/detail pages (Conversations, Memories, Tasks) render their
  /// content in a centered, width-capped column so wide monitors get calm
  /// gutters instead of a full-bleed stretch — matching the Focus/Insights
  /// pages, which already self-constrain. Pages paint a clear background, so the
  /// gutters show the shell surface seamlessly.
  @ViewBuilder
  private func constrainedListPage<V: View>(_ page: V) -> some View {
    page
      .frame(maxWidth: MemoryHubLayoutPolicy.readableContentWidth, maxHeight: .infinity)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var body: some View {
    pages
  }

  @ViewBuilder
  private var pages: some View {
    Group {
      if let destination = DesktopNavigationPolicy.destination(forRawValue: selectedIndex) {
        switch destination {
        case .home:
          DashboardPage(
            tasksStore: viewModelContainer.tasksStore,
            appState: appState,
            chatProvider: viewModelContainer.chatProvider,
            memoriesViewModel: viewModelContainer.memoriesViewModel,
            selectedIndex: $selectedTabIndex)
        case .memory:
          MemoryHubPage(
            appState: appState,
            viewModelContainer: viewModelContainer,
            memoriesViewModel: viewModelContainer.memoriesViewModel,
            destinationRawValue: $memoryDestinationRawValue
          )
        case .memories:
          MemoriesPage(viewModel: viewModelContainer.memoriesViewModel)
            .frame(
              maxWidth: viewModelContainer.memoriesViewModel.selectedMemory == nil
                ? MemoryHubLayoutPolicy.readableContentWidth : .infinity,
              maxHeight: .infinity
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tasks:
          constrainedListPage(
            TasksPage(
              viewModel: viewModelContainer.tasksViewModel,
              chatProvider: viewModelContainer.chatProvider))
        case .insights:
          InsightsHubPage()
        case .rewind:
          RewindPage(appState: appState)
        case .settings:
          SettingsPage(
            appState: appState,
            selectedSection: $selectedSettingsSection,
            highlightedSettingId: $highlightedSettingId
          )
        case .permissions:
          PermissionsPage(appState: appState)
        }
      } else {
        EmptyView()
      }
    }
  }
}

/// Hosts the standalone Conversations page with its own selection state
/// so tapping a row navigates to the detail view.
private struct ConversationsPageHost: View {
  let appState: AppState
  @State private var selectedConversation: LocalConversation? = nil
  @ObservedObject private var conversationDetailState = ConversationDetailAutomationState.shared

  private var usesAvailableWidth: Bool {
    MemoryHubLayoutPolicy.usesAvailableWidth(
      conversationID: selectedConversation?.id,
      presentedConversationID: conversationDetailState.openConversationId,
      transcriptDrawerOpen: conversationDetailState.transcriptDrawerOpen
    )
  }

  var body: some View {
    ConversationsPage(appState: appState, selectedConversation: $selectedConversation)
      .frame(
        maxWidth: usesAvailableWidth ? .infinity : MemoryHubLayoutPolicy.readableContentWidth,
        maxHeight: .infinity
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.easeInOut(duration: 0.22), value: usesAvailableWidth)
      // Owner fencing: an open detail view must not keep showing the previous
      // account's conversation after an in-place account switch.
      .onReceive(NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)) { _ in
        selectedConversation = nil
      }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    DesktopHomeView()
      .environmentObject(AppState())
  }
#endif
