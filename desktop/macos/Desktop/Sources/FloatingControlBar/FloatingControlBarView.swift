import AppKit
import Combine
import OmiSupport
import OmiTheme
import SwiftUI
import UniformTypeIdentifiers

enum ShortcutHintLayout {
  static func visibleTokens(for keys: [String]) -> [String] {
    keys
  }
}

/// A chat surface replaces the compact notch waveform, so recording must keep
/// its own visible projection while the conversation is open. This is derived
/// entirely from reducer-owned presentation state; it does not create another
/// PTT lifecycle owner.
enum FloatingChatPTTOverlayPolicy {
  static func shouldShow(
    showingAIConversation: Bool,
    isVoiceListening: Bool
  ) -> Bool {
    showingAIConversation && isVoiceListening
  }
}

/// Routes an idle notch click through the main chat's sole window authority.
/// Voice and an already-presented floating conversation own their respective
/// surfaces and must not be displaced by a late notch click.
enum NotchIdleTapRoute {
  static func perform(
    isVoicePresentationActive: Bool,
    isShowingConversation: Bool,
    openMainChat: () -> Void
  ) {
    guard !isVoicePresentationActive, !isShowingConversation else { return }
    openMainChat()
  }
}

/// Main floating control bar SwiftUI view composing all sub-views.
struct FloatingControlBarView: View {
  @EnvironmentObject var state: FloatingControlBarState
  @ObservedObject private var shortcutSettings = ShortcutSettings.shared
  weak var window: NSWindow?
  var onPlayPause: () -> Void
  var onAskAI: () -> Void
  var onHide: () -> Void
  var onSendQuery: (String) -> Void
  var onCloseAI: () -> Void
  var onEscape: () -> Void
  var onClearVisibleConversation: () -> Void

  @State private var isHovering = false
  @State private var onboardingGlowOn = false
  @State private var notchLogoHovering = false
  @State private var hoverCollapseWorkItem: DispatchWorkItem?
  /// 0 = hover rows hidden, 1 = hover rows revealed below the fixed header.
  @State private var notchSwitcherProgress: CGFloat = 0
  /// Last reported text-editor height so inputViewHeight can be recomputed
  /// when the pill list changes while the input is open. (Cubic P2.)
  @State private var lastInputEditorHeight: CGFloat = 0
  private var isChatChromePinned: Bool {
    NotchChromeLayout.isChatPinned(
      showingAIConversation: state.showingAIConversation,
      hasVisibleConversation: state.hasVisibleConversation
    )
  }
  private var notchHiddenCenterWidth: CGFloat {
    // Without a physical notch there is no dead zone to straddle — keep a
    // small deliberate gap between the lobes instead of the phantom one.
    state.usesNotchIsland
      ? FloatingControlBarWindow.notchHiddenCenterWidth(for: window?.screen ?? NSScreen.main)
      : FloatingControlBarWindow.pillSurfaceCenterGapWidth
  }
  private var notchSideWidth: CGFloat {
    if isChatChromePinned {
      return FloatingControlBarWindow.notchCompactSideWidth
    }
    if showingNotchThinking {
      return FloatingControlBarWindow.notchThinkingSideWidth
    }
    if !state.isVoiceListening {
      return FloatingControlBarWindow.notchCompactSideWidth
    }
    return FloatingControlBarWindow.notchActiveSideWidth
  }
  private var notchChromeWidth: CGFloat {
    notchHiddenCenterWidth + notchSideWidth * 2
  }
  private var notchChromeLayoutWidth: CGFloat {
    isChatChromePinned || shouldShowNotchHoverMenu
      ? max(notchChromeWidth, FloatingControlBarWindow.notchExpandedWidth)
      : notchChromeWidth
  }
  /// The surface can morph below it, but chrome always keeps the compact
  /// notch-width header so its controls do not drift.
  private var notchChromeMorphWidth: CGFloat {
    NotchChromeLayout.width(
      chromeWidth: notchChromeWidth,
      expandedWidth: FloatingControlBarWindow.notchExpandedWidth,
      switcherProgress: notchSwitcherProgress,
      isChatPresented: isChatChromePinned
    )
  }
  private var notchSurfaceHorizontalInset: CGFloat {
    state.usesNotchIsland ? FloatingControlBarWindow.notchGlowOutsetX : 0
  }
  private var notchSurfaceBottomInset: CGFloat {
    state.usesNotchIsland ? FloatingControlBarWindow.notchGlowOutsetBottom : 0
  }
  private var notchHoverMenuHeight: CGFloat {
    FloatingControlBarWindow.notchHoverMenuHeight(agentCount: 0)
  }

  var body: some View {
    Group {
      if state.usesNotchIsland || state.showingAIConversation || state.isNotchHoverMenuVisible {
        unifiedFloatingSurface
      } else {
        VStack(spacing: state.isShowingNotification && !state.showingAIConversation ? 8 : 0) {
          barChrome

          if let notification = state.currentNotification, !state.showingAIConversation {
            barNotification(notification)
              .padding(.horizontal, OmiSpacing.sm)
              .padding(.bottom, OmiSpacing.sm)
              .transition(.move(edge: .top).combined(with: .opacity))
          }
        }
      }
    }
    .frame(
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: state.usesNotchIsland || state.showingAIConversation || state.isNotchHoverMenuVisible
        ? .top : .center
    )
    .background(Color.clear)
    .omiAnimation(.spring(response: 0.35, dampingFraction: 0.82), value: state.currentNotification?.id)
    // Placed on the always-mounted root (not inside unifiedFloatingSurface) so
    // the pill→island morph still fires when transitioning out of the idle pill.
    .onChange(of: activeLifecycleKey) { _, _ in
      (window as? FloatingControlBarWindow)?.syncActiveIsland()
    }
  }

  /// Composite key for the active PTT lifecycle — any change drives the
  /// pill ↔ notch-island morph (see FloatingControlBarWindow.syncActiveIsland).
  private var activeLifecycleKey: String {
    "\(state.isVoiceListening)-\(state.isThinking)-\(state.isVoiceResponseGlowActive)"
  }

  /// Whether the bar chrome should stretch to fill the window width
  private var barNeedsFullWidth: Bool {
    isHovering || state.isVoiceListening
  }

  private var shouldShowNotchHoverMenu: Bool {
    state.isNotchHoverMenuVisible
  }

  private var showingNotchWaveform: Bool {
    state.isVoiceListening && state.pttHintText.isEmpty
  }

  /// Keep the original thinking mark visible throughout an open conversation,
  /// including connection setup and reply preparation.
  private var showingNotchThinking: Bool {
    NotchChromeLayout.showsThinking(
      isThinking: state.isThinking, isResponseWaiting: state.isVoiceResponseWaiting,
      isListening: state.isVoiceListening, showingAIConversation: state.showingAIConversation,
      conversationOpen: state.conversationPresentation.isOpen)
  }

  private var showingPTTStatusBanner: Bool {
    !state.pttHintText.isEmpty
  }

  /// The notch "speaking" state: response audio is playing (or draining), so
  /// the resting ring pulses like a speaker instead of sitting static.
  private var showingNotchSpeaking: Bool {
    state.isVoiceResponseActive && !state.isVoiceListening
  }

  private var unifiedFloatingSurface: some View {
    VStack(spacing: 0) {
      if state.usesNotchIsland || state.showingAIConversation {
        notchChrome
      } else {
        // No camera housing to blend into — the pill surface starts
        // with a slim top inset instead of the notch chrome band.
        Color.clear
          .frame(height: FloatingControlBarWindow.pillSurfaceTopPadding)
      }

      if showingPTTStatusBanner {
        pttStatusBanner
          .frame(height: FloatingControlBarWindow.pttHintRowHeight)
          .padding(.horizontal, OmiSpacing.md)
          .padding(.bottom, OmiSpacing.xs)
          .transition(.opacity)
      }

      if shouldShowNotchHoverMenu {
        if state.usesNotchIsland {
          Color.clear
            .frame(width: notchChromeLayoutWidth, height: notchHoverMenuHeight, alignment: .top)
            .onHover { setControlsHovering($0) }
            .transition(.identity)
        } else {
          NotchSystemControlsView(progress: 1)
            .padding(OmiSpacing.md)
        }
      }

      if state.showingAIConversation {
        conversationView
          .padding(.horizontal, OmiSpacing.md)
          .padding(.top, 0)
          .padding(.bottom, FloatingControlBarWindow.notchConversationBottomPadding)
          .transition(.opacity)
      }

      if let notification = state.currentNotification, !state.showingAIConversation {
        barNotification(notification)
          .padding(.horizontal, 10)
          .padding(.bottom, 10)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .overlay(alignment: .top) {
      if state.usesNotchIsland && shouldShowNotchHoverMenu {
        ZStack(alignment: .top) {
          // Shortcut legend + capture controls, hugging the trailing edge of the
          // expanded surface — the notch's right side, revealed on hover.
          VStack {
            NotchSystemControlsView(progress: notchSwitcherProgress)
              .padding(
                .top,
                notchChromeHeight
                  + FloatingControlBarWindow.notchControlPanelTopOffset(agentCount: 0)
                  + OmiSpacing.xs
              )
              .padding(.trailing, OmiSpacing.md)
            Spacer(minLength: 0)
          }
          .frame(
            width: notchChromeLayoutWidth,
            height: notchChromeHeight + notchHoverMenuHeight,
            alignment: .topTrailing
          )

        }
        .frame(width: notchChromeLayoutWidth, height: notchChromeHeight + notchHoverMenuHeight)
        .onHover { setControlsHovering($0) }
      }
    }
    .onAppear { notchSwitcherProgress = shouldShowNotchHoverMenu ? 1 : 0 }
    .padding(.horizontal, notchSurfaceHorizontalInset)
    .padding(.bottom, notchSurfaceBottomInset)
    .background(alignment: .top) {
      GeometryReader { geometry in
        let bottomRadius: CGFloat = state.showingAIConversation || state.currentNotification != nil ? 22 : 18
        let surfaceSize = floatingSurfaceSize(geometry: geometry)
        let surfaceWidth = surfaceSize.width
        let surfaceHeight = surfaceSize.height

        ZStack(alignment: .top) {
          NotchDockShape(
            bottomRadius: bottomRadius,
            topRadius: state.usesNotchIsland ? 0 : 14
          )
          .fill(Color.black)
          .frame(width: surfaceWidth, height: surfaceHeight)

          if state.isVoiceResponseGlowActive {
            NotchResponseGlowView(
              bottomRadius: bottomRadius,
              topRadius: state.usesNotchIsland ? 0 : 14,
              edgeInset: state.usesNotchIsland ? 0 : 3
            )
            .frame(width: surfaceWidth, height: surfaceHeight)
          }

          // Onboarding: a plain white glow on the bar edge so first-run
          // users notice it — no animated sweep. Reuses the voice glow's
          // shape and ramps in 1s after the bar appears. Clears the
          // moment they start typing.
          if state.onboardingBarGlow && state.aiInputText.isEmpty {
            NotchLowerEdgeShape(
              bottomRadius: bottomRadius,
              topRadius: state.usesNotchIsland ? 0 : 14,
              edgeInset: state.usesNotchIsland ? 0 : 3
            )
            .stroke(
              Color.white,
              style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
            )
            .frame(width: surfaceWidth, height: surfaceHeight)
            .shadow(color: Color.white.opacity(0.85), radius: 12)
            .shadow(color: Color.white.opacity(0.5), radius: 22)
            .opacity(onboardingGlowOn ? 1 : 0)
            .allowsHitTesting(false)
            .task {
              // Signal-driven (cancels on disappear) instead of asyncAfter:
              // hold the bar un-glowed for a beat, then ease the glow in.
              onboardingGlowOn = false
              try? await Task.sleep(for: .seconds(1))
              guard !Task.isCancelled else { return }
              OmiMotion.withGated(.easeIn(duration: 0.7)) {
                onboardingGlowOn = true
              }
            }
            .onDisappear { onboardingGlowOn = false }
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if state.showingAIConversation {
        ZStack {
          ResizeHandleView(targetWindow: window)
            .frame(width: 20, height: 20)
          ResizeGripShape()
            .foregroundStyle(.white.opacity(0.3))
            .frame(width: 14, height: 14)
            .allowsHitTesting(false)
        }
        .padding(.trailing, notchSurfaceHorizontalInset + 4)
        .padding(.bottom, notchSurfaceBottomInset + 4)
      }
    }
    .overlay(alignment: .bottom) {
      if FloatingChatPTTOverlayPolicy.shouldShow(
        showingAIConversation: state.showingAIConversation,
        isVoiceListening: state.isVoiceListening
      ) {
        // `conversationView` replaces the normal notch waveform while
        // chat is open. Keep the recording/hint projection visible at
        // the bottom of that same surface instead of hiding PTT state.
        voiceListeningView
          .padding(.horizontal, OmiSpacing.md)
          .frame(height: 42)
          .background(Capsule().fill(Color.white.opacity(0.12)))
          .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
          .padding(.horizontal, notchSurfaceHorizontalInset + OmiSpacing.md)
          .padding(.bottom, notchSurfaceBottomInset + 8)
          .accessibilityIdentifier("floating_chat_ptt_recording")
          .accessibilityLabel(
            state.pttHintText.isEmpty ? "Recording voice message" : state.pttHintText
          )
          .allowsHitTesting(false)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .scaleEffect(
      x: max(0.001, state.notchRevealProgress),
      y: max(0.001, state.notchRevealProgress),
      anchor: .top
    )
    .opacity(min(1, max(0, state.notchRevealProgress * 1.4)))
    .contentShape(Rectangle())
    .contextMenu { barContextMenu }
    .onHover(perform: handleBarHover)
    .onChange(of: shouldShowNotchHoverMenu) { _, visible in
      if state.isVoicePresentationActive {
        // A PTT transition replaces the idle hover surface with a separately sized panel. Do not
        // let an in-flight hover spring keep changing the black surface after voice takes over.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          notchSwitcherProgress = 0
        }
        return
      }
      // Fixed window, animated content: in notch mode the NSPanel frame
      // never moves for hover expand/collapse — this value carries the
      // ENTIRE visible morph (black surface height/width, row reveal,
      // dot fan-out). A gentle spring on open, a bounce-free settle on
      // close, both Reduce Motion-gated.
      let morphAnim: Animation =
        visible
        ? FloatingControlBarWindow.notchHoverMenuExpandAnimation
        : FloatingControlBarWindow.notchHoverMenuCollapseAnimation
      OmiMotion.withGated(morphAnim) {
        notchSwitcherProgress = visible ? 1 : 0
      }
    }
    .onChange(of: state.isVoicePresentationActive) { _, active in
      guard active else { return }
      // These view-local values otherwise remain true until pointer exit and can paint stale
      // hover chrome over the voice presentation.
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        isHovering = false
        notchLogoHovering = false
        notchSwitcherProgress = 0
      }
    }
    .onDisappear { state.setNotchHoverMenuOpen(false) }
  }

  /// Size of the visible black surface behind the floating content.
  ///
  /// Notch idle ↔ hover lifecycle: the NSPanel frame is FIXED at the maximum
  /// hover surface, so the visible surface must derive from the content
  /// morph (`notchSwitcherProgress`), not from the window geometry — the
  /// spring on that progress IS the expand/collapse animation. Other states
  /// (chat, voice, notification, PTT hint) still resize the panel and keep
  /// the geometry-driven surface.
  private func floatingSurfaceSize(geometry: GeometryProxy) -> CGSize {
    let notchHoverLifecycle = NotchHoverSurfacePolicy.usesAnimatedHoverSurface(
      usesNotchIsland: state.usesNotchIsland,
      showingAIConversation: state.showingAIConversation,
      isVoicePresentationActive: state.isVoicePresentationActive,
      isShowingNotification: state.isShowingNotification)
    if notchHoverLifecycle {
      let openWidth = max(notchChromeWidth, FloatingControlBarWindow.notchExpandedWidth)
      return CGSize(
        width: notchChromeWidth + (openWidth - notchChromeWidth) * notchSwitcherProgress,
        height: notchChromeHeight + notchHoverMenuHeight * notchSwitcherProgress
      )
    }
    let hasExpandedSurface =
      state.showingAIConversation
      || state.currentNotification != nil
      || shouldShowNotchHoverMenu
      || showingPTTStatusBanner
    guard hasExpandedSurface else {
      return CGSize(width: notchChromeWidth, height: notchChromeHeight)
    }
    return CGSize(
      width: max(notchChromeWidth, geometry.size.width - notchSurfaceHorizontalInset * 2),
      height: max(notchChromeHeight, geometry.size.height - notchSurfaceBottomInset)
    )
  }

  private var notchChrome: some View {
    ZStack {
      HStack(spacing: 0) {
        notchIdentityLobe
          .frame(width: notchSideWidth, height: notchChromeHeight)

        Spacer(minLength: notchHiddenCenterWidth)

        notchControlLobe
          .frame(width: notchSideWidth, height: notchChromeHeight)
      }

      Color.clear
        .frame(width: notchHiddenCenterWidth, height: notchChromeHeight)
        .allowsHitTesting(false)
    }
    .frame(height: notchChromeHeight)
    .frame(width: notchChromeMorphWidth)
  }

  private var notchIdentityLobe: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .trailing) {
        // One always-mounted identity mark owns idle, PTT, and thinking
        // presentation. The reducer still owns the voice lifecycle; this view
        // only morphs its read-only projection at the mark's existing position.
        NotchVoiceMorphMark(
          dotColors: [], isListening: showingNotchWaveform,
          isThinking: showingNotchThinking, isSpeaking: showingNotchSpeaking
        )
        .frame(width: NotchVoiceMorphGeometry.markSize.width, height: NotchVoiceMorphGeometry.markSize.height)
        .accessibilityIdentifier("notch_voice_morph_mark")
        .scaleEffect(notchLogoHovering ? 1.06 : 1.0)
      }
      .frame(width: notchSideWidth, height: notchChromeHeight, alignment: .trailing)
      .padding(.trailing, OmiSpacing.hairline)
      .contentShape(Rectangle())
      .onHover { hovering in
        guard !state.isVoicePresentationActive else { return }
        setNotchLogoHovering(hovering)
      }
      .onTapGesture {
        guard !state.isVoicePresentationActive else { return }
        openMainChatFromIdleNotch()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
  }

  /// Picks the actionable "Couldn't reach Intentive" card for reach errors, else the
  /// normal notification card.
  @ViewBuilder
  private func barNotification(_ notification: FloatingBarNotification) -> some View {
    if notification.assistantId == "reach_error" {
      reachErrorCard(notification)
    } else if notification.assistantId == "suggestion" {
      suggestionCard(notification)
    } else {
      notificationView(notification)
    }
  }

  /// Live proactive suggestion. Monochrome and quiet by design — this card interrupts
  /// unprompted, so it earns attention with the sentence, not with chrome.
  private func suggestionCard(_ notification: FloatingBarNotification) -> some View {
    Button {
      FloatingControlBarManager.shared.openNotificationAsChat(notification)
    } label: {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: "lightbulb")
          .scaledFont(size: 13, weight: .medium)
          .foregroundColor(.white.opacity(0.75))

        Text(notification.message)
          .scaledFont(size: 13, weight: .medium)
          .foregroundColor(.white)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: OmiSpacing.xs)

        Button {
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          Image(systemName: "xmark")
            .scaledFont(size: 10, weight: .semibold)
            .foregroundColor(.white.opacity(0.45))
            .padding(OmiSpacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss suggestion")
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Conversation ends — the USP moment. "N follow-ups ready" + Review / Later.

  /// Hard reach failure (retries exhausted). Persists until the user picks
  /// Retry (re-runs the query, restarting backoff) or Skip (back to idle).
  private func reachErrorCard(_ notification: FloatingBarNotification) -> some View {
    HStack(alignment: .center, spacing: OmiSpacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white.opacity(0.9))

      VStack(alignment: .leading, spacing: 1) {
        Text(notification.title)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(.white)
          .lineLimit(1)
        if !notification.message.isEmpty {
          Text(notification.message)
            .scaledFont(size: 11)
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(1)
        }
      }

      Spacer(minLength: OmiSpacing.sm)

      Button {
        FloatingControlBarManager.shared.retryReachError()
      } label: {
        Text("Retry")
          .scaledFont(size: 12, weight: .semibold)
          .foregroundColor(.white)
          .padding(.horizontal, OmiSpacing.sm)
          .padding(.vertical, OmiSpacing.xxs)
          .background(Color.white.opacity(0.18))
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)

      Button {
        FloatingControlBarManager.shared.dismissReachError()
      } label: {
        Text("Skip")
          .scaledFont(size: 12, weight: .semibold)
          .foregroundColor(.white.opacity(0.6))
          .padding(.horizontal, OmiSpacing.xs)
          .padding(.vertical, OmiSpacing.xxs)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var notchControlLobe: some View {
    // Idle-notch clicking opens the main chat. The floating bar no longer
    // owns typed conversation or a duplicate settings entry point.
    Button(action: openMainChatFromIdleNotch) {
      Color.clear
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(.leading, OmiSpacing.xs)
    .padding(.trailing, OmiSpacing.md)
    .accessibilityLabel(DesktopShellIdentityCopy.openChat)
    .accessibilityHint(DesktopShellIdentityCopy.openChatHint)
  }

  private var notchChromeHeight: CGFloat {
    FloatingControlBarWindow.notchChromeHeight(for: window?.screen ?? NSScreen.main)
  }

  /// Full-width readable status strip under chrome / pill for too-short PTT
  /// taps and mic errors. Keeps long copy out of the narrow logo/mic slot.
  private var pttStatusBanner: some View {
    HStack(spacing: OmiSpacing.xs) {
      Image(systemName: "mic.fill")
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundColor(.white.opacity(0.9))
      Text(state.pttHintText)
        .scaledFont(size: 12, weight: .medium)
        .foregroundColor(.white)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Collapsed pill / hover bar chrome. Conversations, notifications-with-
  /// chat and capture controls render on `unifiedFloatingSurface` — this
  /// chrome only ever shows the idle pill, hover hints, and voice states.
  private var barChrome: some View {
    VStack(spacing: 0) {
      controlBarView

      if showingPTTStatusBanner {
        pttStatusBanner
          .frame(height: FloatingControlBarWindow.pttHintRowHeight)
          .padding(.horizontal, 10)
          .padding(.bottom, OmiSpacing.xs)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: barNeedsFullWidth || showingPTTStatusBanner ? .infinity : nil, alignment: .top)
    // No .clipped() here: the pill's status/voice glow needs to render
    // outside the chrome bounds (the window grows via glow outsets).
    .background(DraggableAreaView(targetWindow: window))
    .floatingBackground(cornerRadius: barNeedsFullWidth ? 20 : 5)
    .contextMenu {
      barContextMenu
    }
    .onHover(perform: handleBarHover)
  }

  @ViewBuilder
  private var barContextMenu: some View {
    Button("Disable for 2 hours") {
      FloatingControlBarManager.shared.snooze(
        for: FloatingControlBarManager.snoozeTwoHoursDuration
      )
    }
  }

  private var conversationView: some View {
    ZStack(alignment: .top) {
      if state.conversationSurface == .mainResponse {
        mainConversationContainer {
          aiResponseView
            .id("response")
        }
        .zIndex(1)
      } else {
        mainConversationContainer {
          aiInputView
            .id("input")
        }
        .zIndex(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private func mainConversationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    // This is the expanded main-chat header, never the compact/hover row.
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.sm) {
        Button(action: mainConversationBackAction) {
          Image(systemName: "chevron.left")
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(.white.opacity(0.82))
            .frame(width: 36, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(DesktopShellIdentityCopy.closeChat)

        Text(DesktopShellIdentityCopy.chatTitle)
          .scaledFont(size: OmiType.body, weight: .bold)
          .foregroundColor(.white)
          .lineLimit(1)

        if state.conversationMicrophoneOpen {
          Button {
            ConversationVoiceController.shared.close()
          } label: {
            Label("End", systemImage: "mic.fill")
              .font(.caption)
          }
          .buttonStyle(.plain)
          .help("Microphone is open. End the conversation.")
          .accessibilityIdentifier("conversation_end")
        }

        Spacer(minLength: 0)

        if state.hasVisibleConversation {
          escToClearHint
        }
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.top, OmiSpacing.sm)

      content()
    }
  }

  private var escToClearHint: some View {
    HStack(spacing: OmiSpacing.xxs) {
      Text("esc")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(.secondary)
        .frame(width: 30, height: 16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(4)
      Text("to clear")
        .scaledFont(size: OmiType.caption)
        .foregroundColor(.secondary)
    }
  }

  private func setControlsHovering(_ hovering: Bool) {
    hoverCollapseWorkItem?.cancel()
    hoverCollapseWorkItem = nil

    if hovering {
      (window as? FloatingControlBarWindow)?.openNotchHoverMenuUntilExit()
      return
    }

    let workItem = DispatchWorkItem {
      (window as? FloatingControlBarWindow)?.updateNotchPointerFromGlobalMouse()
      if !shouldShowNotchHoverMenu {
        notchLogoHovering = false
      }
    }
    hoverCollapseWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
  }

  private func setNotchLogoHovering(_ hovering: Bool) {
    guard !state.isVoicePresentationActive || !hovering else {
      notchLogoHovering = false
      return
    }
    OmiMotion.withGated(.spring(response: 0.18, dampingFraction: 0.74)) {
      notchLogoHovering = hovering
    }
    setControlsHovering(hovering)
  }

  private func openMainChatFromIdleNotch() {
    NotchIdleTapRoute.perform(
      isVoicePresentationActive: state.isVoicePresentationActive,
      isShowingConversation: state.showingAIConversation,
      openMainChat: {
        (NSApp.delegate as? AppDelegate)?.openMainAppChat()
      }
    )
  }

  private func mainConversationBackAction() { onCloseAI() }

  private func handleBarHover(_ hovering: Bool) {
    if state.usesNotchIsland {
      (window as? FloatingControlBarWindow)?.updateNotchPointerFromGlobalMouse()
      let showsHoverChrome = hovering && !state.isVoicePresentationActive
      OmiMotion.withGated(.easeOut(duration: FloatingControlBarWindow.notchHoverMenuExpandDuration)) {
        isHovering = showsHoverChrome && state.isNotchHoverMenuVisible
      }
      if !hovering || !state.isNotchHoverMenuVisible {
        notchLogoHovering = false
      }
      return
    }

    if !hovering {
      state.requiresHoverReset = false
    }

    let effectiveHover = hovering && !state.requiresHoverReset && isWithinActivationZoneForCurrentMode()
    state.isHoveringBar = effectiveHover

    // Resize window BEFORE updating SwiftUI state on expand so the expanded
    // content never renders in a too-small window. If the resize was
    // skipped (guarded), do NOT show the expanded bar — oversized content
    // in a small window force-grows it with the origin pinned, sliding
    // the pill sideways.
    var didExpand = false
    if effectiveHover {
      didExpand = (window as? FloatingControlBarWindow)?.resizeForHover(expanded: true) ?? false
    }
    OmiMotion.withGated(.easeOut(duration: FloatingControlBarWindow.notchHoverMenuExpandDuration)) {
      isHovering = effectiveHover && didExpand
    }
    if !effectiveHover {
      (window as? FloatingControlBarWindow)?.resizeForHover(expanded: false)
    }
  }

  private func isWithinActivationZoneForCurrentMode() -> Bool {
    guard state.usesNotchIsland else { return true }
    guard let window else { return false }
    // The notch window frame is fixed at the maximum hover surface, so the
    // activation zone must be derived from the VISIBLE content (collapsed
    // chrome when idle, the current-agent-count menu when open), never
    // from the window frame — otherwise hover triggers far below/beside
    // the visible island.
    let hitHeight =
      state.isNotchHoverMenuVisible
      ? max(notchChromeHeight, notchChromeHeight + notchHoverMenuHeight)
      : FloatingControlBarWindow.notchActivationHeight
    let visibleWidth =
      state.isNotchHoverMenuVisible
      ? max(notchChromeWidth, FloatingControlBarWindow.notchExpandedWidth)
      : notchChromeWidth
    let horizontalOutset = max(
      FloatingControlBarWindow.notchGlowOutsetX,
      (window.frame.width - visibleWidth) / 2
    )
    return FloatingControlBarGeometry.notchChromeActivationContains(
      mouseLocation: NSEvent.mouseLocation,
      windowFrame: window.frame,
      chromeHeight: hitHeight,
      horizontalOutset: horizontalOutset
    )
  }

  private func notificationView(_ notification: FloatingBarNotification) -> some View {
    // The entire card opens the chat. A SwiftUI Button only hit-tests its
    // visible content, so the previous layout left the padding and spacer
    // as dead zones — users reported clicks landing "on the box" doing
    // nothing. Wrapping the whole card in a single Button with
    // contentShape(Rectangle()) makes every pixel clickable. The dismiss
    // (X) button sits in an overlay on top so it keeps its own hit region.
    Button {
      FloatingControlBarManager.shared.openNotificationAsChat(notification)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.08))
            .frame(width: 34, height: 34)

          Image(systemName: "bell.badge.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
        }

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(notification.title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(.white)
            .lineLimit(1)

          Text(notification.message)
            .scaledFont(size: 12)
            .foregroundColor(.white.opacity(0.72))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        // Reserve space so text never runs under the overlaid action buttons.
        // Wider for actionable (task) notifications that also show Execute.
        Color.clear
          .frame(width: notification.assistantId == "task" ? 90 : 36, height: 18)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topTrailing) {
      HStack(spacing: OmiSpacing.xs) {
        Button {
          FloatingControlBarManager.shared.dismissCurrentNotification()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.62))
            .frame(width: 18, height: 18)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
    }
    .floatingBackground(cornerRadius: 18)
  }

  private var controlBarView: some View {
    let allowsHoverExpansion = isHovering && !state.isVoiceResponseGlowActive
    return Group {
      if !state.pttHintText.isEmpty {
        // Too-short / error copy lives in `pttStatusBanner` below — keep
        // the pill chrome as the idle strip so we don't stack two mics.
        compactCircleView()
          .frame(height: 14)
          .padding(.vertical, 5)
          .transition(.opacity)
      } else if state.isVoiceListening {
        voiceListeningView
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .frame(height: 42)
          .transition(.opacity)
      } else if allowsHoverExpansion {
        VStack(spacing: 1) {
          compactButton(title: DesktopShellIdentityCopy.openApp, keys: shortcutSettings.askOmiShortcut.displayTokens) {
            onAskAI()
          }

          HStack(spacing: OmiSpacing.xs) {
            compactLabel("Talk", keys: shortcutSettings.pttShortcut.displayTokens)
          }
        }
        .padding(.horizontal, OmiSpacing.xs)
        .padding(.vertical, 3)
        .frame(height: 50)
        .transition(.opacity)
      } else {
        compactCircleView()
          .transition(.opacity)
      }
    }
  }

  /// Minimal thin bar shown when not hovering. The fill is the primary
  /// ambient status channel at this size: voice-response gradient wins,
  /// with neutral gray while idle.
  private func compactCircleView() -> some View {
    RoundedRectangle(cornerRadius: OmiChrome.stripRadius)
      .fill(compactPillFill())
      .frame(width: 28, height: 6)
      .shadow(
        color: state.isVoiceResponseGlowActive ? Color.white.opacity(0.85) : .clear,
        radius: state.isVoiceResponseGlowActive ? 16 : 0,
        x: 0,
        y: 0
      )
      .shadow(
        color: state.isVoiceResponseGlowActive ? Color.white.opacity(0.45) : .clear,
        radius: state.isVoiceResponseGlowActive ? 28 : 0,
        x: 0,
        y: 0
      )
      .overlay {
        if state.isVoiceResponseGlowActive {
          RoundedRectangle(cornerRadius: OmiChrome.stripRadius)
            .stroke(
              LinearGradient(
                colors: [
                  Color.white.opacity(0.9),
                  Color(red: 0.25, green: 0.75, blue: 1.0),
                  Color.white.opacity(0.7),
                ],
                startPoint: .leading,
                endPoint: .trailing
              ),
              lineWidth: 1.4
            )
            .padding(-2.2)
            .blur(radius: 0.25)
        }
      }
      .omiAnimation(.easeInOut(duration: 0.18), value: state.isVoiceResponseGlowActive)
  }

  private func compactPillFill() -> LinearGradient {
    if state.isVoiceResponseGlowActive {
      return LinearGradient(
        colors: [
          Color.white.opacity(0.9),
          Color(red: 0.50, green: 0.75, blue: 1.0),
          Color.white.opacity(0.7),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    }
    return LinearGradient(
      colors: [Color.white.opacity(0.5), Color.white.opacity(0.5)],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private func compactToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Button(action: { isOn.wrappedValue.toggle() }) {
      HStack(spacing: 3) {
        Text(title)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(.white)
        RoundedRectangle(cornerRadius: OmiChrome.badgeRadius)
          .fill(isOn.wrappedValue ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
          .frame(width: 26, height: 15)
          .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
            Circle()
              .fill(.white)
              .frame(width: 11, height: 11)
              .padding(OmiSpacing.hairline)
          }
          .omiAnimation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
      }
    }
    .buttonStyle(.plain)
  }

  private func compactButton(title: String, keys: [String], action: @escaping () -> Void) -> some View {
    Button(action: action) {
      compactLabel(title, keys: keys)
    }
    .buttonStyle(.plain)
  }

  private func compactLabel(_ title: String, keys: [String]) -> some View {
    HStack(spacing: 3) {
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(.white)
      ForEach(keys, id: \.self) { key in
        Text(key)
          .scaledFont(size: 9)
          .foregroundColor(.white)
          .padding(.horizontal, key.count > 1 ? 4 : 0)
          .frame(minWidth: 15, minHeight: 15)
          .background(Color.white.opacity(0.1))
          .cornerRadius(OmiChrome.stripRadius)
      }
    }
  }

  private var voiceListeningView: some View {
    HStack(spacing: 7) {
      if state.pttHintText.isEmpty {
        // Playful realtime mic waveform (replaces the old pulsing red dot)
        VoiceWaveformBars(isActive: state.isVoiceListening)
      }

      Image(systemName: "mic.fill")
        .scaledFont(size: 12, weight: .semibold)
        .foregroundColor(.white)

      if state.isVoiceLocked && state.pttHintText.isEmpty {
        Image(systemName: "lock.fill")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(.orange)
          .frame(width: 18, height: 18)
          .background(Color.orange.opacity(0.2))
          .cornerRadius(4)
      }
    }
  }

  private var aiInputView: some View {
    AskAIInputView(
      userInput: Binding(
        get: { state.aiInputText },
        set: { state.aiInputText = $0 }
      ),
      canClearVisibleConversation: false,
      onSend: { message in
        (window as? FloatingControlBarWindow)?
          .beginVisibleMainQuery(message, fromVoice: false, animated: true)
        onSendQuery(message)
      },
      onClearVisibleConversation: onClearVisibleConversation,
      onEscape: onEscape,
      onHeightChange: { [self] height in
        lastInputEditorHeight = height
        recomputeUnifiedInputHeight()
      }
    )
    .transition(
      .asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
      ))
  }

  /// Recompute inputViewHeight from the last known editor height and the
  /// conversation header. Called when the editor height changes.
  private func recomputeUnifiedInputHeight() {
    // Guard against stale zero editor height: the editor has not reported
    // its size yet (or was just re-created after a surface switch), so
    // recomputing now would shrink the window and clip input/send
    // controls. Fall back to the minimum content height so the panel
    // keeps a usable size until a real height arrives. (Cubic P2.)
    let height =
      lastInputEditorHeight > 0
      ? lastInputEditorHeight
      : FloatingControlBarWindow.notchInputPanelMinimumContentHeight
    let topBand =
      (state.usesNotchIsland || state.showingAIConversation)
      ? notchChromeHeight
      : FloatingControlBarWindow.pillSurfaceTopPadding
    let statusBanner =
      showingPTTStatusBanner
      ? FloatingControlBarWindow.pttStatusBannerBudget
      : 0
    let baseHeight = topBand + statusBanner + height + FloatingControlBarWindow.notchInputPanelVerticalPadding
    let headerBudget = FloatingControlBarWindow.notchChatHeaderVerticalBudget
    state.inputViewHeight = baseHeight + headerBudget
  }

  private var floatingChatProvider: ChatProvider? {
    FloatingControlBarManager.shared.sharedFloatingProvider
  }

  private var aiResponseView: some View {
    // Re-read derived content when viewport anchors or streamed answer tokens change.
    let _ = state.chatViewport
    let _ = state.answerStreamToken
    let provider = floatingChatProvider
    return AIResponseView(
      isLoading: Binding(
        get: { state.isAILoading },
        set: { state.isAILoading = $0 }
      ),
      currentMessage: state.currentAIMessage(from: provider),
      userInput: state.displayedQuery,
      chatHistory: state.derivedChatHistory(from: provider),
      canClearVisibleConversation: false,
      showsHeader: false,
      onClearVisibleConversation: onClearVisibleConversation,
      onEscape: onEscape,
      onOpenMainApp: {
        (window as? FloatingControlBarWindow)?.closeAIConversation()
        AppDelegate.summonWindowTarget()?.openMainAppChat()
      }
    )
    .transition(
      .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .bottom).combined(with: .opacity)
      ))
  }

}

private struct NotchDockShape: Shape {
  let bottomRadius: CGFloat
  var topRadius: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let radius = min(bottomRadius, rect.height / 2)
    // Square top corners blend into a physical notch/bezel; a floating
    // surface on a non-notched display rounds them instead.
    let topR = min(topRadius, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + topR),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + topR, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.closeSubpath()
    return path
  }
}

private struct NotchLowerEdgeShape: Shape {
  let bottomRadius: CGFloat
  /// 0 = open lower-edge path (notch mode: the top blends into the bezel).
  /// > 0 = closed full-perimeter ring with rounded top corners (pill mode:
  /// the surface is a floating card, so the glow wraps all the way around).
  var topRadius: CGFloat = 0
  /// Inset from the shape bounds. Pill-mode windows have no glow outsets,
  /// so the ring is drawn slightly inside the surface to avoid clipping.
  var edgeInset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: edgeInset, dy: edgeInset)
    let radius = min(max(0, bottomRadius - edgeInset), rect.height / 2)
    var path = Path()
    if topRadius > 0 {
      let topR = min(max(0, topRadius - edgeInset), rect.height / 2)
      path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + topR),
        control: CGPoint(x: rect.maxX, y: rect.minY)
      )
    } else {
      path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - radius),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    if topRadius > 0 {
      let topR = min(max(0, topRadius - edgeInset), rect.height / 2)
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX + topR, y: rect.minY),
        control: CGPoint(x: rect.minX, y: rect.minY)
      )
      path.closeSubpath()
    } else {
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 1))
    }
    return path
  }
}

private struct NotchResponseGlowView: View {
  let bottomRadius: CGFloat
  /// See `NotchLowerEdgeShape`: 0 = notch lower-edge glow, > 0 = pill-mode
  /// full-perimeter ring with this top corner radius.
  var topRadius: CGFloat = 0
  var edgeInset: CGFloat = 0

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      let phase = time.truncatingRemainder(dividingBy: 2.4) / 2.4
      let sweepStart = UnitPoint(x: -0.35 + phase * 1.7, y: 0.0)
      let sweepEnd = UnitPoint(x: 0.35 + phase * 1.7, y: 1.0)
      let edge = NotchLowerEdgeShape(
        bottomRadius: bottomRadius,
        topRadius: topRadius,
        edgeInset: edgeInset
      )

      ZStack {
        edge
          .stroke(
            LinearGradient(
              colors: [
                Color.white.opacity(1.0),
                Color(red: 0.72, green: 0.88, blue: 1.0).opacity(1.0),
                Color(red: 0.88, green: 0.95, blue: 1.0).opacity(1.0),
                Color.white.opacity(1.0),
              ],
              startPoint: .leading,
              endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
          )

        edge
          .stroke(
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color.white.opacity(0.55), location: 0.28),
                .init(color: Color(red: 0.22, green: 0.88, blue: 1.0).opacity(1.0), location: 0.45),
                .init(color: Color.white.opacity(1.0), location: 0.53),
                .init(color: Color(red: 1.0, green: 0.96, blue: 0.92).opacity(0.95), location: 0.70),
                .init(color: .clear, location: 1.0),
              ],
              startPoint: sweepStart,
              endPoint: sweepEnd
            ),
            style: StrokeStyle(lineWidth: 4.8, lineCap: .round, lineJoin: .round)
          )
      }
    }
    .allowsHitTesting(false)
  }
}
