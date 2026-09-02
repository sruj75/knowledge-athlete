import AppKit
import OmiTheme
import SwiftUI

/// Canonical ordinary Chat host. Home renders the owner-scoped local catalog,
/// journal timeline, composer, local task/Focus/Insight rows, and daily local
/// suggestions through the single shared `ChatProvider` instance.
struct DashboardPage: View {
  @ObservedObject var tasksStore: TasksStore
  @ObservedObject var appState: AppState
  @ObservedObject var chatProvider: ChatProvider
  @ObservedObject var memoriesViewModel: MemoriesViewModel
  @Binding var selectedIndex: Int

  @ObservedObject private var homeSuggestionsStore = HomeSuggestionsStore.shared
  @ObservedObject private var focusStorage = FocusStorage.shared
  @ObservedObject private var insightStorage = InsightStorage.shared

  @State private var homeMode: HomeStageMode = .hub
  @State private var dismissedKnowsTaskIDs: Set<String> = []
  @State private var homeAskFocusPolicy = HomeAskFocusPolicy()
  @FocusState private var homeAskFieldFocused: Bool
  @State private var citedConversation: LocalConversation?
  @State private var isLoadingCitation = false
  @State private var isChatCatalogPresented = false
  @State private var isClearChatConfirmationPresented = false
  @State private var citationGeneration: UInt64 = 0

  private static let contentMaxWidth: CGFloat = 980
  private static let stageAnimation = Animation.spring(response: 0.46, dampingFraction: 0.86)

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        OmiColors.homeBackground.ignoresSafeArea()
        if HomeStageMode.collapseCatcherActive(mode: homeMode, resting: homeRestingMode) {
          Color.black.opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: collapseHomeStagePanel)
        }
        homeStage(size: proxy.size)
      }
      .omiAnimation(Self.stageAnimation, value: homeMode)
    }
    .sheet(item: $citedConversation) { conversation in
      ConversationDetailView(conversation: conversation, onBack: { citedConversation = nil })
        .frame(minWidth: 500, minHeight: 500)
    }
    .overlay {
      if isLoadingCitation {
        ZStack {
          Color.black.opacity(0.3)
          ProgressView().padding(OmiSpacing.xl).background(OmiColors.backgroundSecondary)
        }
      }
    }
    .onAppear {
      syncHomeState()
      consumePendingMainChatOpenRequest()
      autoOpenChatForExistingHistoryIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshNonTaskHomeState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)) { _ in
      dismissedKnowsTaskIDs = []
      citationGeneration &+= 1
      citedConversation = nil
      isLoadingCitation = false
      isChatCatalogPresented = false
      isClearChatConfirmationPresented = false
      syncHomeState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .navigateToChat)) { _ in
      openHomeChat()
    }
    .onReceive(NotificationCenter.default.publisher(for: .openMainChatRequested)) { _ in
      consumePendingMainChatOpenRequest()
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeStageOpenChat)) { _ in
      openHomeChat()
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeStageClose)) { _ in
      collapseHomeStagePanel()
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeChatCatalogOpen)) { _ in
      guard chatProvider.multiChatEnabled else { return }
      openHomeChat(focusInput: false)
      isChatCatalogPresented = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeChatCatalogClose)) { _ in
      isChatCatalogPresented = false
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeStageAsk)) { note in
      guard let query = note.userInfo?["query"] as? String else { return }
      askHomeSuggestion(query)
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeStageAttach)) { note in
      guard let path = note.userInfo?["path"] as? String,
        let attachment = ChatAttachment.from(url: URL(fileURLWithPath: path))
      else { return }
      openHomeChat(focusInput: false)
      chatProvider.addAttachments([attachment])
    }
    .onChange(of: chatProvider.messages.count) { _, _ in
      autoOpenChatForExistingHistoryIfNeeded()
    }
    .onChange(of: chatProvider.isLoading) { _, _ in
      autoOpenChatForExistingHistoryIfNeeded()
    }
    .onChange(of: homeAskFieldFocused) { _, focused in
      if focused && homeMode != .chat { openHomeChat(focusInput: false) }
    }
    .onChange(of: isChatCatalogPresented) { _, isPresented in
      reportHomeAutomationMode()
      guard isPresented else { return }
      Task { await chatProvider.refreshCatalogForPresentation() }
    }
    .onChange(of: chatProvider.multiChatEnabled) { _, enabled in
      if !enabled { isChatCatalogPresented = false }
      reportHomeAutomationMode()
    }
  }

  @ViewBuilder
  private func homeStage(size: CGSize) -> some View {
    if homeMode == .hub {
      homeHub(width: min(Self.contentMaxWidth, max(560, size.width - 80)))
        .transition(.homeHubStage)
    } else {
      homeChat(width: size.width, height: size.height)
        .transition(.homeChatRise)
    }
  }

  private func homeHub(width: CGFloat) -> some View {
    VStack(spacing: OmiSpacing.xl) {
      Spacer(minLength: 28)
      SBLogo(size: 42, spinning: chatProvider.isSending)
      VStack(spacing: OmiSpacing.sm) {
        Text(homeGreeting)
          .scaledFont(size: OmiType.hero, weight: .bold)
          .foregroundStyle(OmiColors.textPrimary)
        Text(homeDailyBrief)
          .scaledFont(size: OmiType.subheading)
          .foregroundStyle(OmiColors.textTertiary)
      }
      .multilineTextAlignment(.center)

      homeKnowsList
        .frame(maxWidth: 560)

      Spacer(minLength: 12)
      homeComposer
        .frame(width: width)
      chatErrors
        .frame(width: width)
      Spacer(minLength: 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 30)
  }

  private func homeChat(width: CGFloat, height: CGFloat) -> some View {
    VStack(spacing: OmiSpacing.sm) {
      if chatProvider.multiChatEnabled || !chatProvider.messages.isEmpty || chatProvider.isClearing {
        HStack {
          if chatProvider.multiChatEnabled {
            Button {
              isChatCatalogPresented.toggle()
            } label: {
              HStack(spacing: OmiSpacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(chatProvider.currentSession?.title ?? "Chats")
                  .lineLimit(1)
                Image(systemName: "chevron.down")
                  .scaledFont(size: OmiType.micro, weight: .semibold)
              }
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundStyle(OmiColors.textSecondary)
              .padding(.horizontal, OmiSpacing.md)
              .padding(.vertical, OmiSpacing.sm)
              .background(OmiColors.backgroundSecondary)
              .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chats")
            .popover(isPresented: $isChatCatalogPresented, arrowEdge: .bottom) {
              HomeChatCatalog(
                chatProvider: chatProvider,
                onDismiss: { isChatCatalogPresented = false }
              )
              .frame(width: 340, height: min(520, max(360, height - 120)))
            }
          }
          Spacer()
          if !chatProvider.messages.isEmpty || chatProvider.isClearing {
            Button {
              isClearChatConfirmationPresented = true
            } label: {
              if chatProvider.isClearing {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: "trash")
              }
            }
            .buttonStyle(.plain)
            .foregroundStyle(OmiColors.textTertiary)
            .help("Clear chat history")
            .accessibilityLabel("Clear chat history")
            .disabled(
              chatProvider.isLoading || chatProvider.isClearing || chatProvider.isSending
                || chatProvider.isCreatingSession || !chatProvider.deletingSessionIds.isEmpty
            )
          }
        }
        .frame(maxWidth: Self.contentMaxWidth)
        .padding(.horizontal, OmiSpacing.xl)
        .padding(.top, OmiSpacing.md)
      }

      chatTimeline
      if chatProvider.messages.isEmpty && chatProvider.onboardingOpener == nil {
        homeQuestionChips
      }
      homeComposer
      chatErrors
    }
    .frame(maxWidth: Self.contentMaxWidth)
    .padding(.horizontal, OmiSpacing.xl)
    .padding(.bottom, OmiSpacing.lg)
    .frame(width: width, height: height)
    .confirmationDialog(
      "Clear this chat?",
      isPresented: $isClearChatConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Clear Chat", role: .destructive) {
        Task { await chatProvider.clearCurrentChat() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently removes this chat's local message history. A named chat is replaced with a new chat.")
    }
  }

  private var chatTimeline: some View {
    ChatMessagesView(
      messages: chatProvider.messages,
      isSending: chatProvider.isSending,
      hasMoreMessages: chatProvider.hasMoreMessages,
      isLoadingMoreMessages: chatProvider.isLoadingMoreMessages,
      isLoadingInitial: chatProvider.isLoading && !chatProvider.isClearing,
      onLoadMore: { await chatProvider.loadMoreMessages() },
      onCitationTap: handleCitationTap,
      sessionsLoadError: chatProvider.sessionsLoadError.map {
        UserFacingErrorPresentation.message(from: $0, while: .chatSessions)
      },
      onRetry: { Task { await chatProvider.retryLoad() } },
      localSendToken: chatProvider.localSendToken,
      onCancelTurn: { chatProvider.stopAgent(owner: .mainChat) },
      onOpenAgent: { agentID, completion in
        FloatingControlBarManager.shared.openAgentChatFromTimeline(agentID: agentID, completion: completion)
      },
      onOpenAgentRef: FloatingControlBarManager.shared.openAgentChatFromTimeline(ref:completion:),
      horizontalContentPadding: 0,
      verticalContentPadding: OmiSpacing.sm,
      trailingContentPadding: OmiSpacing.md,
      contentColumnWidth: 760,
      timelineTrailingInset: 0,
      welcomeContent: { chatWelcome }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottom) {
      ChatComposerFade()
    }
  }

  @ViewBuilder
  private var chatWelcome: some View {
    if let opener = chatProvider.onboardingOpener {
      OnboardingOpenerView(opener: opener, chatProvider: chatProvider)
    } else {
      VStack(spacing: OmiSpacing.md) {
        SBLogo(size: 38, spinning: false)
        Text(DesktopShellIdentityCopy.chatWelcomeTitle)
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundStyle(OmiColors.textPrimary)
        Text(DesktopShellIdentityCopy.chatWelcomeDetail)
          .scaledFont(size: OmiType.body)
          .foregroundStyle(OmiColors.textTertiary)
      }
      .padding(.vertical, 72)
    }
  }

  private var homeComposer: some View {
    ChatInputView(
      onSend: sendFromHomeAskBar,
      onStop: { chatProvider.stopAgent(owner: .mainChat) },
      isSending: chatProvider.isSending,
      isStopping: chatProvider.isStopping,
      isSendDisabled: chatProvider.isCreatingSession,
      placeholder: DesktopShellIdentityCopy.askAnything,
      requiresTextBeforeSend: true,
      mode: $chatProvider.chatMode,
      inputText: $chatProvider.draftText,
      attachments: $chatProvider.pendingAttachments,
      onAttachmentsAdded: { urls in
        chatProvider.addAttachments(urls.compactMap(ChatAttachment.from(url:)))
      },
      onAttachmentRemoved: chatProvider.removePendingAttachment(id:)
    )
    .focused($homeAskFieldFocused)
  }

  @ViewBuilder
  private var chatErrors: some View {
    VStack(spacing: OmiSpacing.sm) {
      if let cardState = chatProvider.currentError {
        ChatErrorCard(
          state: cardState,
          onRecover: { Task { await chatProvider.recoverFromError() } },
          onDismiss: chatProvider.dismissCurrentError
        )
      }
      if let error = chatProvider.errorMessage, !error.isEmpty {
        HStack(spacing: OmiSpacing.sm) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(OmiColors.warning)
          Text(error)
            .scaledFont(size: OmiType.body)
            .foregroundStyle(OmiColors.textSecondary)
          Spacer()
          Button {
            chatProvider.errorMessage = nil
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
        }
        .padding(OmiSpacing.md)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
            .fill(OmiColors.backgroundSecondary)
        )
      }
      if let error = tasksStore.homeTaskError, !error.isEmpty {
        Text(error)
          .scaledFont(size: OmiType.caption)
          .foregroundStyle(OmiColors.textTertiary)
      }
    }
  }

  private var homeKnowsList: some View {
    VStack(spacing: OmiSpacing.sm) {
      ForEach(homeKnowsRows) { row in
        HStack(spacing: OmiSpacing.sm) {
          Button {
            openKnowsRow(row)
          } label: {
            HStack(spacing: OmiSpacing.sm) {
              Image(systemName: icon(for: row.kind))
                .frame(width: 18)
              Text(row.text).lineLimit(1)
              Spacer()
            }
            .foregroundStyle(OmiColors.textSecondary)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          if dismissible(row.kind) {
            Button {
              dismissKnowsRow(row)
            } label: {
              Image(systemName: "xmark")
                .scaledFont(size: OmiType.micro)
                .foregroundStyle(OmiColors.textQuaternary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, OmiSpacing.md)
        .frame(height: 38)
        .background(
          RoundedRectangle(cornerRadius: 11)
            .fill(OmiColors.homeTile.opacity(0.72))
        )
        .overlay {
          RoundedRectangle(cornerRadius: 11)
            .stroke(OmiColors.homeHairline.opacity(0.7), lineWidth: 1)
        }
      }
    }
    .accessibilityIdentifier("home-knows-list")
  }

  private var homeQuestionChips: some View {
    HStack(spacing: OmiSpacing.sm) {
      ForEach(homeSuggestedQuestions, id: \.self) { question in
        Button(question) {
          chatProvider.draftText = question
          homeAskFieldFocused = true
        }
        .buttonStyle(.plain)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundStyle(OmiColors.textSecondary)
        .padding(.horizontal, OmiSpacing.md)
        .frame(height: 32)
        .background(Capsule().fill(OmiColors.homeTile))
      }
    }
  }

  private var homeKnowsRows: [HomeKnowsRow] {
    HomeKnowsListComposer.compose(
      tasks: homeTaskCandidates,
      insights: insightStorage.visibleInsights.prefix(12).map {
        HomeKnowsInsightCandidate(id: $0.id, text: $0.insight.insight)
      },
      tip: homeActionTip,
      questions: homeSuggestedQuestions,
      dismissedTaskIDs: dismissedKnowsTaskIDs
    )
  }

  private var homeTaskCandidates: [HomeKnowsTaskCandidate] {
    tasksStore.homeTasks
      .filter { !$0.completed && $0.deleted != true }
      .map { HomeKnowsTaskCandidate(id: $0.id, text: $0.description) }
  }

  private var homeSuggestedQuestions: [String] {
    HomeSuggestionComposer.compose(personalized: homeSuggestionsStore.personalizedQuestions)
  }

  private var homeActionTip: String? {
    if focusStorage.currentStatus == .distracted { return "Help me get back on track" }
    return homeTaskCandidates.count >= 5
      ? "Sort my open tasks — which 3 actually matter today?"
      : "Recap what I got done today"
  }

  private var homeGreeting: String {
    let name = AuthService.shared.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "I'm ready." : "Hey \(name). I'm ready."
  }

  private var homeDailyBrief: String {
    let count = tasksStore.openTaskCount
    let tail =
      count == 0 ? "nothing's waiting on you." : count == 1 ? "one thing needs you." : "\(count) things need you."
    let lead: String?
    switch focusStorage.currentStatus {
    case .focused:
      let app = (focusStorage.currentApp ?? focusStorage.detectedAppName ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      lead =
        app.isEmpty || app.localizedCaseInsensitiveContains("unknown") ? "Heads-down today" : "Deep in \(app) today"
    case .distracted: lead = "A scattered stretch just now"
    case nil: lead = nil
    }
    if let lead { return "\(lead) — \(tail)" }
    return tail.prefix(1).uppercased() + tail.dropFirst()
  }

  private func icon(for kind: HomeKnowsRowKind) -> String {
    switch kind {
    case .task: return "circle"
    case .insight: return "lightbulb"
    case .focus: return "eye"
    case .question: return "bubble.left"
    }
  }

  private func dismissible(_ kind: HomeKnowsRowKind) -> Bool {
    switch kind {
    case .task, .insight: return true
    case .focus, .question: return false
    }
  }

  private func openKnowsRow(_ row: HomeKnowsRow) {
    switch row.kind {
    case .task(let id):
      if let task = tasksStore.homeTasks.first(where: { $0.id == id }) {
        TaskNavigationRequestStore.shared.request(task: task)
      }
      navigate(to: .tasks)
    case .insight(let id):
      guard InsightsHubNavigationStore.shared.request(segment: .insights, insightID: id) else {
        return
      }
      navigate(to: .insights)
    case .focus:
      guard InsightsHubNavigationStore.shared.request(segment: .focus) else { return }
      navigate(to: .insights)
    case .question:
      chatProvider.draftText = row.text
      openHomeChat()
    }
  }

  private func dismissKnowsRow(_ row: HomeKnowsRow) {
    switch row.kind {
    case .task(let id): dismissedKnowsTaskIDs.insert(id)
    case .insight(let id): Task { await insightStorage.dismissInsight(id) }
    case .focus, .question: break
    }
  }

  private func sendFromHomeAskBar(_ draft: String) {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !chatProvider.isSending else { return }
    openHomeChat(focusInput: false)
    AnalyticsManager.shared.chatMessageSent(messageLength: text.count, source: "home_ask_bar")
    Task { await chatProvider.sendMainDraft(draft) }
  }

  private func askHomeSuggestion(_ suggestion: String) {
    guard case .prefill(let text) = HomeSuggestionSelection.resolve(suggestion) else { return }
    chatProvider.draftText = text
    openHomeChat()
  }

  private func openHomeChat(focusInput: Bool = true) {
    if homeMode != .chat {
      OmiMotion.withGated(Self.stageAnimation) { homeMode = .chat }
    }
    if focusInput { focusHomeAskFieldAfterStageTransition() }
    reportHomeAutomationMode()
  }

  private func focusHomeAskFieldAfterStageTransition() {
    let token = homeAskFocusPolicy.currentToken()
    Task { @MainActor in
      await Task.yield()
      guard homeAskFocusPolicy.isCurrent(token), homeMode == .chat else { return }
      homeAskFieldFocused = true
    }
  }

  private var homeRestingMode: HomeStageMode {
    HomeHistoryPresentationPolicy.restingMode(
      isLoading: chatProvider.isLoading,
      messageCount: chatProvider.messages.count
    )
  }

  private func collapseHomeStagePanel() {
    isChatCatalogPresented = false
    homeAskFieldFocused = false
    homeAskFocusPolicy.invalidate()
    OmiMotion.withGated(Self.stageAnimation) { homeMode = homeRestingMode }
    reportHomeAutomationMode()
  }

  private func autoOpenChatForExistingHistoryIfNeeded() {
    guard homeRestingMode == .chat, homeMode == .hub, chatProvider.onboardingOpener == nil else { return }
    openHomeChat(focusInput: false)
  }

  private func consumePendingMainChatOpenRequest() {
    guard MainChatNavigationRequestStore.shared.consume() else { return }
    openHomeChat()
  }

  private func syncHomeState() {
    Task {
      await tasksStore.loadHomeTasks()
      await insightStorage.refresh()
      await homeSuggestionsStore.refreshIfNeeded()
    }
  }

  private func refreshNonTaskHomeState() {
    Task {
      await insightStorage.refresh()
      await homeSuggestionsStore.refreshIfNeeded()
    }
  }

  private func navigate(to item: DesktopDestination) {
    selectedIndex = item.rawValue
    AnalyticsManager.shared.tabChanged(tabName: item.title)
  }

  private func reportHomeAutomationMode() {
    guard DesktopAutomationLaunchOptions.isEnabled else { return }
    _ = DesktopAutomationStateStore.shared.updateLiveFields { snapshot in
      snapshot.homeMode = homeMode.automationLabel
      snapshot.homeCatalogOpen = isChatCatalogPresented
      snapshot.updatedAt = ISO8601DateFormatter().string(from: Date())
    }
  }

  private func handleCitationTap(_ citation: Citation) {
    guard citation.sourceType == .conversation else { return }
    guard let ownerSnapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    citationGeneration &+= 1
    let generation = citationGeneration
    isLoadingCitation = true
    Task {
      do {
        let conversation = try await LocalAuthorityConversationDataSource().detail(id: citation.id)
        guard generation == citationGeneration,
          RuntimeOwnerIdentity.isAuthorizationCurrent(ownerSnapshot)
        else { return }
        citedConversation = conversation
        isLoadingCitation = false
      } catch {
        guard generation == citationGeneration,
          RuntimeOwnerIdentity.isAuthorizationCurrent(ownerSnapshot)
        else { return }
        isLoadingCitation = false
      }
    }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    DashboardPage(
      tasksStore: TasksStore(observesNotifications: false),
      appState: AppState(),
      chatProvider: ChatProvider(),
      memoriesViewModel: MemoriesViewModel(),
      selectedIndex: .constant(DesktopDestination.home.rawValue)
    )
  }
#endif
