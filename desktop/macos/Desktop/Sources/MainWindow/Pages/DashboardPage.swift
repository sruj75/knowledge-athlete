import AppKit
import Combine
import OmiTheme
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dashboard View Model

/// Local projection for the Home dashboard.
///
/// Tasks and goals are deliberately independent of the network. Their storage
/// actors are the only durable authorities; this model only coordinates reads
/// and forwards changes to SwiftUI.
@MainActor
final class DashboardViewModel: ObservableObject {
  typealias GoalLoader = () async throws -> [LocalGoal]

  private let tasksStore = TasksStore.shared
  private let goalLoader: GoalLoader

  @Published var goals: [LocalGoal] = []
  @Published var isLoading = false
  @Published var error: String?

  private var cancellables = Set<AnyCancellable>()
  private var ownerGeneration: UInt64 = 0

  var overdueTasks: [TaskActionItem] { tasksStore.overdueTasks }
  var todaysTasks: [TaskActionItem] { tasksStore.todaysTasks }
  var recentTasks: [TaskActionItem] { tasksStore.tasksWithoutDueDate }

  init(goalLoader: GoalLoader? = nil) {
    self.goalLoader =
      goalLoader ?? {
        try await GoalStorage.shared.getLocalGoals(activeOnly: true)
      }
    tasksStore.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .runtimeOwnerDidChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.resetSessionState()
        Task { @MainActor [weak self] in await self?.loadDashboardData() }
      }
      .store(in: &cancellables)
  }

  func loadDashboardData() async {
    let generation = ownerGeneration
    isLoading = true
    error = nil
    async let taskLoad: Void = tasksStore.loadDashboardTasks()
    async let goalLoad: Void = loadGoals()
    _ = await (taskLoad, goalLoad)
    if generation == ownerGeneration { isLoading = false }
  }

  func loadCachedDashboardData() async {
    await loadGoals()
  }

  func resetSessionState() {
    ownerGeneration &+= 1
    goals = []
    isLoading = false
    error = nil
  }

  func refreshGoals() {
    Task { @MainActor [weak self] in await self?.loadGoals() }
  }

  func toggleTaskCompletion(_ task: TaskActionItem) async {
    await tasksStore.toggleTask(task)
  }

  func createGoal(title: String, description: String?) async {
    guard let authorization = localAuthorization() else { return }
    do {
      _ = try await GoalStorage.shared.createGoal(
        title: title,
        description: description,
        authorization: authorization
      )
      await loadGoals()
    } catch {
      self.error = error.localizedDescription
      logError("Dashboard: Failed to create local goal", error: error)
    }
  }

  func updateGoal(_ goal: LocalGoal, title: String, description: String?) async {
    guard let authorization = localAuthorization() else { return }
    do {
      _ = try await GoalStorage.shared.updateGoal(
        surfacedID: goal.id,
        title: title,
        description: description,
        authorization: authorization
      )
      await loadGoals()
    } catch {
      self.error = error.localizedDescription
      logError("Dashboard: Failed to update local goal", error: error)
    }
  }

  func toggleGoalCompletion(_ goal: LocalGoal) async {
    guard let authorization = localAuthorization() else { return }
    do {
      _ = try await GoalStorage.shared.setCompleted(
        surfacedID: goal.id,
        completed: goal.completedAt == nil,
        authorization: authorization
      )
      await loadGoals()
    } catch {
      self.error = error.localizedDescription
      logError("Dashboard: Failed to complete local goal", error: error)
    }
  }

  private func loadGoals() async {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      goals = []
      return
    }
    let generation = ownerGeneration
    do {
      let loadedGoals = try await goalLoader()
      guard generation == ownerGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot),
        !Task.isCancelled
      else { return }
      goals = loadedGoals
    } catch {
      guard generation == ownerGeneration,
        RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
      else { return }
      self.error = error.localizedDescription
      logError("Dashboard: Failed to load local goals", error: error)
    }
  }

  private func localAuthorization() -> LocalMutationAuthorization? {
    guard let snapshot = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return nil }
    return LocalMutationAuthorization {
      RuntimeOwnerIdentity.isAuthorizationCurrent(snapshot)
    }
  }
}

/// The retained non-task Home projection. S-13 may replace task and goal
/// authority, but Focus, Insights, and once-daily questions remain owned by
/// their existing stores until S-14.
struct HomeRetainedContextProjection: Equatable {
  struct Insight: Equatable {
    let id: String
    let text: String
  }

  let focusTitle: String
  let focusDetail: String
  let latestInsight: Insight?
  let questions: [String]

  static func make(
    focusStatus: FocusStatus?,
    currentApp: String?,
    detectedApp: String?,
    insights: [StoredInsight],
    personalizedQuestions: [String]
  ) -> HomeRetainedContextProjection {
    let rawApp = currentApp ?? detectedApp
    let app = rawApp?.trimmingCharacters(in: .whitespacesAndNewlines)
    let namedApp = app.flatMap { value in
      value.isEmpty || value.localizedCaseInsensitiveContains("unknown") ? nil : value
    }

    let focusTitle: String
    let focusDetail: String
    switch focusStatus {
    case .focused:
      focusTitle = "Focused"
      focusDetail = namedApp.map { "Working in \($0)" } ?? "A focused stretch is in progress"
    case .distracted:
      focusTitle = "Distracted"
      focusDetail = namedApp.map { "Attention shifted in \($0)" } ?? "Open Focus for the recent signal"
    case nil:
      focusTitle = "Focus is ready"
      focusDetail = namedApp.map { "Watching \($0)" } ?? "Open Focus to see today's pattern"
    }

    let latestInsight =
      insights
      .filter { !$0.isDismissed }
      .max(by: { $0.createdAt < $1.createdAt })
      .map { Insight(id: $0.id, text: $0.insight.insight) }

    return HomeRetainedContextProjection(
      focusTitle: focusTitle,
      focusDetail: focusDetail,
      latestInsight: latestInsight,
      questions: HomeSuggestionComposer.compose(personalized: personalizedQuestions)
    )
  }
}

// MARK: - Dashboard Page

struct DashboardPage: View {
  @ObservedObject var viewModel: DashboardViewModel
  @ObservedObject var homeStatusStore: HomeStatusStore = HomeStatusStore()
  @ObservedObject var appState: AppState
  @ObservedObject var chatProvider: ChatProvider
  @ObservedObject var memoriesViewModel: MemoriesViewModel
  @ObservedObject private var homeSuggestionsStore = HomeSuggestionsStore.shared
  @ObservedObject private var focusStorage = FocusStorage.shared
  @ObservedObject private var insightStorage = InsightStorage.shared
  @Binding var selectedIndex: Int
  @State private var citedConversation: LocalConversation?
  @State private var isLoadingCitation = false
  @AppStorage("dashboardWidgetsCollapsed") private var widgetsCollapsed = false
  @AppStorage("useLegacyHomeDesign") private var useLegacyHomeDesign = false
  @State private var homeMode: HomeStageMode = .hub
  @State private var homeAskFocusPolicy = HomeAskFocusPolicy()
  @FocusState private var homeAskFieldFocused: Bool

  private static let homeStageMaxWidth: CGFloat = 1360
  private static let homeStageMinSideInset: CGFloat = 30
  private static let homeStageMaxSideInset: CGFloat = 96
  private static let homeAskBarMinWidth: CGFloat = 560
  private static let homeAskBarMaxWidth: CGFloat = 980
  private static let homeChatColumnMaxWidth: CGFloat = 900
  private static let homeStageTopPadding: CGFloat = 42
  private static let homeStageBottomPadding: CGFloat = 26
  private static let homeStageAnimation = Animation.spring(response: 0.46, dampingFraction: 0.86)

  var body: some View {
    applyChatNavigation(to: applyHomeLifecycle(to: applyHomeSheets(to: homeSurface)))
  }

  private func applyChatNavigation<Content: View>(to content: Content) -> some View {
    content.onReceive(NotificationCenter.default.publisher(for: .navigateToChat)) { _ in
      openHomeChat(focusInput: true)
    }
  }

  private var homeSurface: some View {
    Group {
      if useLegacyHomeDesign {
        legacyHome
      } else {
        redesignedHome
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(useLegacyHomeDesign ? Color.clear : HomePalette.paper)
  }

  private func applyHomeSheets<Content: View>(to content: Content) -> some View {
    content
      .sheet(item: $citedConversation) { conversation in
        ConversationDetailView(conversation: conversation, onBack: { citedConversation = nil })
          .frame(minWidth: 500, minHeight: 500)
      }
      .overlay {
        if isLoadingCitation {
          ZStack {
            Color.black.opacity(0.3)
            ProgressView()
              .padding(OmiSpacing.xl)
              .background(OmiColors.backgroundSecondary)
              .cornerRadius(OmiChrome.smallControlRadius)
          }
        }
      }
  }

  private func applyHomeLifecycle<Content: View>(to content: Content) -> some View {
    content
      .onAppear {
        autoOpenChatForExistingHistoryIfNeeded()
        if chatProvider.onboardingOpener != nil { openHomeChat(focusInput: false) }
        consumePendingMainChatOpenRequest()
        reportHomeAutomationMode()
        Task { await viewModel.loadDashboardData() }
        Task { await homeStatusStore.refreshIfNeeded() }
        Task { await homeSuggestionsStore.refreshIfNeeded() }
      }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        viewModel.refreshGoals()
        appState.checkAllPermissions()
        Task { await homeStatusStore.refreshIfNeeded() }
        Task { await homeSuggestionsStore.refreshIfNeeded() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .openMainChatRequested)) { _ in
        consumePendingMainChatOpenRequest()
      }
      .onChange(of: chatProvider.messages.count) { _, _ in
        autoOpenChatForExistingHistoryIfNeeded()
      }
      .onChange(of: chatProvider.isLoading) { _, _ in
        autoOpenChatForExistingHistoryIfNeeded()
      }
      .onChange(of: homeAskFieldFocused) { _, focused in
        if focused && !useLegacyHomeDesign && homeMode != .chat { openHomeChat() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageOpenChat)) { _ in
        guard !useLegacyHomeDesign else { return }
        openHomeChat()
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageClose)) { _ in
        guard !useLegacyHomeDesign else { return }
        collapseHomeStagePanel()
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageAsk)) { note in
        guard !useLegacyHomeDesign, let query = note.userInfo?["query"] as? String else { return }
        askHomeSuggestion(query)
      }
      .onReceive(NotificationCenter.default.publisher(for: .homeStageAttach)) { note in
        guard !useLegacyHomeDesign, let path = note.userInfo?["path"] as? String else { return }
        if let attachment = ChatAttachment.from(url: URL(fileURLWithPath: path)) {
          chatProvider.addAttachments([attachment])
        }
      }
  }

  private var legacyHome: some View {
    VStack(spacing: 0) {
      dashboardWidgets
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
        contentColumnWidth: 760,
        welcomeContent: { dashboardChatWelcome }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      dashboardChatErrorCard.padding(.horizontal, OmiSpacing.section)

      ChatInputView(
        onSend: { text in
          AnalyticsManager.shared.chatMessageSent(messageLength: text.count, source: "dashboard_chat")
          Task { await chatProvider.sendMainDraft(text) }
        },
        onStop: { chatProvider.stopAgent(owner: .mainChat) },
        isSending: chatProvider.isSending,
        isStopping: chatProvider.isStopping,
        placeholder: "Ask omi anything",
        mode: $chatProvider.chatMode,
        inputText: $chatProvider.draftText,
        attachments: $chatProvider.pendingAttachments,
        onAttachmentsAdded: { urls in
          chatProvider.addAttachments(urls.compactMap { ChatAttachment.from(url: $0) })
        },
        onAttachmentRemoved: chatProvider.removePendingAttachment
      )
      .padding(.horizontal, OmiSpacing.section)
      .padding(.vertical, OmiSpacing.md)
    }
  }

  private var redesignedHome: some View {
    GeometryReader { proxy in
      ZStack {
        HomePalette.paper.ignoresSafeArea()
        if HomeStageMode.collapseCatcherActive(mode: homeMode, resting: homeRestingMode) {
          Color.black.opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { collapseHomeStagePanel() }
        }
        homeStage(stageWidth: proxy.size.width, stageHeight: proxy.size.height)
          .frame(width: proxy.size.width, height: proxy.size.height)
        if HomeStageMode.collapseCatcherActive(mode: homeMode, resting: homeRestingMode) {
          OverlayModalEscapeCatcher { collapseHomeStagePanel() }
        }
      }
      .omiAnimation(Self.homeStageAnimation, value: homeMode)
    }
  }

  private func homeStage(stageWidth: CGFloat, stageHeight: CGFloat) -> some View {
    let askBarWidth = homeAskBarWidth(for: stageWidth)
    return Group {
      if homeMode == .hub {
        homeHubStage(stageWidth: stageWidth, askBarWidth: askBarWidth)
          .transition(.homeHubStage)
      } else {
        homePanelStage(stageWidth: stageWidth, askBarWidth: askBarWidth)
      }
    }
    .padding(.top, homeMode.topPadding(hub: Self.homeStageTopPadding))
    .padding(.bottom, Self.homeStageBottomPadding)
  }

  private func homeHubStage(stageWidth: CGFloat, askBarWidth: CGFloat) -> some View {
    VStack(spacing: OmiSpacing.lg) {
      ScrollView { dashboardWidgets }
        .frame(maxWidth: homeStageContentWidth(for: stageWidth), maxHeight: .infinity)
      homeAskBar.frame(width: askBarWidth)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func homePanelStage(stageWidth: CGFloat, askBarWidth: CGFloat) -> some View {
    VStack(spacing: 0) {
      homeChatPanel(width: askBarWidth)
        .transition(.homeChatRise)
        .frame(maxHeight: .infinity)
      homeAskBar
        .frame(width: askBarWidth)
        .padding(.top, OmiSpacing.xxs)
      dashboardChatErrorCard
        .frame(width: askBarWidth)
        .padding(.top, OmiSpacing.sm)
    }
  }

  private func homeChatPanel(width: CGFloat) -> some View {
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
      welcomeContent: { dashboardChatWelcome }
    )
    .frame(width: width)
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private var dashboardChatErrorCard: some View {
    if let cardState = chatProvider.currentError {
      ChatErrorCard(
        state: cardState,
        onRecover: { Task { await chatProvider.recoverFromError() } },
        onDismiss: { chatProvider.dismissCurrentError() }
      )
    }
  }

  private var homeAskBar: some View {
    HomeAskBar(
      text: $chatProvider.draftText,
      isSending: chatProvider.isSending,
      isStopping: chatProvider.isStopping,
      focus: $homeAskFieldFocused,
      attachments: $chatProvider.pendingAttachments,
      onAttachmentsAdded: { urls in
        chatProvider.addAttachments(urls.compactMap { ChatAttachment.from(url: $0) })
      },
      onAttachmentRemoved: chatProvider.removePendingAttachment,
      onSend: sendFromHomeAskBar,
      onStop: { chatProvider.stopAgent(owner: .mainChat) },
      onActivate: focusHomeAskBar
    )
  }

  private func homeStageSideInset(for stageWidth: CGFloat) -> CGFloat {
    min(Self.homeStageMaxSideInset, max(Self.homeStageMinSideInset, stageWidth * 0.06))
  }

  private func homeStageContentWidth(for stageWidth: CGFloat) -> CGFloat {
    min(Self.homeStageMaxWidth, max(0, stageWidth - (homeStageSideInset(for: stageWidth) * 2)))
  }

  private func homeAskBarWidth(for stageWidth: CGFloat) -> CGFloat {
    let available = min(
      homeMode == .hub ? Self.homeAskBarMaxWidth : Self.homeChatColumnMaxWidth,
      homeStageContentWidth(for: stageWidth)
    )
    return min(available, max(Self.homeAskBarMinWidth, available))
  }

  private func reportHomeAutomationMode() {
    guard DesktopAutomationLaunchOptions.isEnabled else { return }
    let modeLabel = useLegacyHomeDesign ? nil : homeMode.automationLabel
    _ = DesktopAutomationStateStore.shared.updateLiveFields { snapshot in
      snapshot.homeMode = modeLabel
      snapshot.updatedAt = ISO8601DateFormatter().string(from: Date())
    }
  }

  private func autoOpenChatForExistingHistoryIfNeeded() {
    guard
      HomeHistoryPresentationPolicy.restingMode(
        isLoading: chatProvider.isLoading,
        messageCount: chatProvider.messages.count
      ) == .chat,
      homeMode == .hub,
      chatProvider.onboardingOpener == nil
    else { return }
    openHomeChat(focusInput: false)
  }

  private func consumePendingMainChatOpenRequest() {
    guard MainChatNavigationRequestStore.shared.consume(), !useLegacyHomeDesign else { return }
    openHomeChat()
  }

  private func openHomeChat(focusInput: Bool = true) {
    if homeMode != .chat {
      OmiMotion.withGated(Self.homeStageAnimation) { homeMode = .chat }
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
    homeAskFieldFocused = false
    homeAskFocusPolicy.invalidate()
    OmiMotion.withGated(Self.homeStageAnimation) { homeMode = homeRestingMode }
    reportHomeAutomationMode()
  }

  private func focusHomeAskBar() {
    homeAskFieldFocused = true
  }

  private func sendFromHomeAskBar() {
    let draft = chatProvider.draftText
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !chatProvider.isSending else { return }
    openHomeChat(focusInput: false)
    AnalyticsManager.shared.chatMessageSent(messageLength: text.count, source: "home_ask_bar")
    Task { await chatProvider.sendMainDraft(draft) }
  }

  private func askHomeSuggestion(_ suggestion: String) {
    openHomeChat(focusInput: false)
    AnalyticsManager.shared.chatMessageSent(messageLength: suggestion.count, source: "home_suggested_question")
    Task { await chatProvider.sendMessage(suggestion) }
  }

  private func prefillHomeQuestion(_ question: String) {
    chatProvider.draftText = question
    openHomeChat()
  }

  @ViewBuilder
  private var dashboardChatWelcome: some View {
    if let opener = chatProvider.onboardingOpener {
      OnboardingOpenerView(opener: opener, chatProvider: chatProvider)
    } else {
      VStack(spacing: OmiSpacing.md) {
        Text("Ask omi anything")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text("Your personal AI assistant — knows you through your memories and conversations")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, OmiSpacing.section)
    }
  }

  private func handleCitationTap(_ citation: Citation) {
    guard citation.sourceType == .conversation else { return }
    isLoadingCitation = true
    Task {
      do {
        let conversation = try await LocalAuthorityConversationDataSource().detail(id: citation.id)
        await MainActor.run {
          citedConversation = conversation
          isLoadingCitation = false
        }
      } catch {
        await MainActor.run { isLoadingCitation = false }
      }
    }
  }

  private var dashboardWidgets: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      HStack {
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          Text("Home")
            .scaledFont(size: OmiType.title, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
          Text("Your local tasks and goals, with today's focus and insights")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
        }
        Spacer()
        if viewModel.isLoading { ProgressView().controlSize(.small) }
        Button {
          widgetsCollapsed.toggle()
        } label: {
          Image(systemName: widgetsCollapsed ? "chevron.down" : "chevron.up")
        }
        .buttonStyle(.plain)
      }

      retainedHomeContext

      if !widgetsCollapsed {
        HStack(alignment: .top, spacing: OmiSpacing.lg) {
          TasksWidget(
            overdueTasks: viewModel.overdueTasks,
            todaysTasks: viewModel.todaysTasks,
            recentTasks: viewModel.recentTasks,
            onToggleCompletion: { task in
              Task { await viewModel.toggleTaskCompletion(task) }
            }
          )
          GoalsWidget(
            goals: viewModel.goals,
            onCreateGoal: { title, description in
              Task { await viewModel.createGoal(title: title, description: description) }
            },
            onUpdateGoal: { goal, title, description in
              Task { await viewModel.updateGoal(goal, title: title, description: description) }
            },
            onToggleCompletion: { goal in
              Task { await viewModel.toggleGoalCompletion(goal) }
            }
          )
        }
        .frame(minHeight: 260)
      }

      if let error = viewModel.error {
        Text(error)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
      }
    }
    .padding(.horizontal, OmiSpacing.section)
    .padding(.vertical, OmiSpacing.md)
  }

  private var retainedHomeProjection: HomeRetainedContextProjection {
    HomeRetainedContextProjection.make(
      focusStatus: focusStorage.currentStatus,
      currentApp: focusStorage.currentApp,
      detectedApp: focusStorage.detectedAppName,
      insights: insightStorage.insightHistory,
      personalizedQuestions: homeSuggestionsStore.personalizedQuestions
    )
  }

  private var retainedHomeContext: some View {
    let projection = retainedHomeProjection
    return LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 250), spacing: OmiSpacing.md)],
      alignment: .leading,
      spacing: OmiSpacing.md
    ) {
      HomeRetainedContextCard(
        icon: "eye",
        eyebrow: "Focus",
        title: projection.focusTitle,
        detail: projection.focusDetail,
        accessibilityIdentifier: "home-focus-projection"
      ) {
        selectedIndex = SidebarNavItem.focus.rawValue
      }

      if let insight = projection.latestInsight {
        HomeRetainedContextCard(
          icon: "lightbulb",
          eyebrow: "Latest insight",
          title: insight.text,
          detail: "Open Insights for context and history",
          accessibilityIdentifier: "home-insight-projection"
        ) {
          insightStorage.markAsRead(insight.id)
          selectedIndex = SidebarNavItem.insight.rawValue
        }
      }

      HomeQuestionCard(questions: projection.questions, onSelect: prefillHomeQuestion)
    }
    .accessibilityIdentifier("home-retained-context")
  }
}

// MARK: - Home Components

enum HomePalette {
  static let paper = Color(red: 0.018, green: 0.019, blue: 0.021)
  static let tile = Color(red: 0.078, green: 0.078, blue: 0.088)
  static let ink = Color(red: 0.97, green: 0.97, blue: 0.975)
  static let secondary = Color(red: 0.72, green: 0.73, blue: 0.75)
  static let muted = Color(red: 0.46, green: 0.47, blue: 0.50)
  static let stageGlow = Color(red: 0.72, green: 0.74, blue: 0.78)
}

private struct HomeRetainedContextCard: View {
  let icon: String
  let eyebrow: String
  let title: String
  let detail: String
  let accessibilityIdentifier: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: icon)
          Text(eyebrow.uppercased())
        }
        .scaledFont(size: OmiType.micro, weight: .semibold)
        .foregroundStyle(HomePalette.muted)

        Text(title)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(HomePalette.ink)
          .lineLimit(2)

        Text(detail)
          .scaledFont(size: OmiType.caption)
          .foregroundStyle(HomePalette.secondary)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
      .padding(OmiSpacing.md)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(HomePalette.tile.opacity(0.62))
      )
      .contentShape(.rect(cornerRadius: OmiChrome.smallControlRadius))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

private struct HomeQuestionCard: View {
  let questions: [String]
  let onSelect: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: "bubble.left")
        Text("ASK OMI")
      }
      .scaledFont(size: OmiType.micro, weight: .semibold)
      .foregroundStyle(HomePalette.muted)

      ForEach(questions, id: \.self) { question in
        Button {
          onSelect(question)
        } label: {
          HStack(spacing: OmiSpacing.xs) {
            Text(question)
              .scaledFont(size: OmiType.caption, weight: .medium)
              .foregroundStyle(HomePalette.secondary)
              .lineLimit(1)
            Spacer(minLength: OmiSpacing.xs)
            Image(systemName: "arrow.up.right")
              .scaledFont(size: OmiType.micro, weight: .semibold)
              .foregroundStyle(HomePalette.muted)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .padding(OmiSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
        .fill(HomePalette.tile.opacity(0.62))
    )
    .accessibilityIdentifier("home-question-projection")
  }
}

struct HomeAskBar: View {
  @Binding var text: String
  let isSending: Bool
  let isStopping: Bool
  var focus: FocusState<Bool>.Binding
  @Binding var attachments: [ChatAttachment]
  let onAttachmentsAdded: ([URL]) -> Void
  let onAttachmentRemoved: (String) -> Void
  let onSend: () -> Void
  let onStop: () -> Void
  let onActivate: () -> Void

  @State private var isHovering = false
  @State private var isDropTargeted = false

  private var hasText: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Requires text: ChatProvider.sendMessage drops empty-text sends, so
  /// presenting attachment-only as sendable would silently do nothing.
  /// Staged files ride along with the typed message instead.
  private var canSend: Bool {
    hasText
  }

  private var isFocused: Bool { focus.wrappedValue }

  var body: some View {
    VStack(spacing: OmiSpacing.sm) {
      if !attachments.isEmpty {
        AttachmentPreviewRow(
          attachments: attachments,
          onRemove: onAttachmentRemoved
        )
        .padding(.top, OmiSpacing.sm)
        .padding(.horizontal, OmiSpacing.md)
      }

      HStack(alignment: .bottom, spacing: OmiSpacing.sm) {
        Button(action: pickFiles) {
          Image(systemName: "paperclip")
            .scaledFont(size: OmiType.subheading, weight: .medium)
            .foregroundStyle(isFocused ? HomePalette.secondary : HomePalette.muted)
            .frame(width: 24, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(attachments.count >= kMaxChatAttachments)
        .help("Attach files")

        // Auto-growing input: `axis: .vertical` + `lineLimit(1...6)` grow the pill
        // as text wraps (scrolls past six lines). Return submits, Shift+Return
        // newlines — via onKeyPress, since a vertical field would otherwise insert
        // a newline on Return and never fire onSubmit.
        TextField(
          "",
          text: $text,
          prompt: Text("Ask omi anything").foregroundColor(HomePalette.muted),
          axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(HomePalette.ink)
        .lineLimit(1...6)
        .focused(focus)
        .padding(.vertical, 7)
        .onKeyPress(phases: .down) { press in
          guard press.key == .return else { return .ignored }
          // Shift+Return falls through to the field's newline handling.
          if press.modifiers.contains(.shift) { return .ignored }
          handleSubmit()
          return .handled
        }

        actionButton
      }
      .padding(.leading, OmiSpacing.lg)
      .padding(.trailing, OmiSpacing.sm)
      .padding(.vertical, 12)
      .frame(minHeight: 58)
    }
    .background(
      RoundedRectangle(cornerRadius: 29, style: .continuous)
        .fill(HomePalette.tile.opacity(isHovering || isFocused ? 1 : 0.92))
    )
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: 29, style: .continuous)
          .stroke(Color.white.opacity(0.42), lineWidth: 1)
      } else {
        RoundedRectangle(cornerRadius: 29, style: .continuous)
          .stroke(HomePalette.stageGlow.opacity(isFocused ? 0.16 : 0.08), lineWidth: 1)
      }
    }
    // Keep the composer visually separate without casting a large, opaque bezel
    // into the transcript. These are intentionally only 10% of the old shadow.
    .shadow(color: HomePalette.stageGlow.opacity(isFocused ? 0.011 : 0.0045), radius: isFocused ? 2.2 : 1.6)
    .shadow(color: .black.opacity(isFocused ? 0.045 : 0.034), radius: 2.4, y: 1)
    .contentShape(.rect(cornerRadius: 29))
    .onTapGesture {
      onActivate()
      focus.wrappedValue = true
    }
    .onHover { isHovering = $0 }
    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    .omiAnimation(.easeOut(duration: 0.16), value: isFocused)
    .omiAnimation(.easeOut(duration: 0.16), value: canSend)
    .omiAnimation(.easeOut(duration: 0.16), value: attachments.count)
  }

  private func pickFiles() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [
      .image, .jpeg, .png, .gif, .heic, .heif, .webP, .tiff, .bmp,
      .pdf, .plainText, .json, .commaSeparatedText, .html,
      .text, .content,
    ]
    if panel.runModal() == .OK {
      let remaining = max(0, kMaxChatAttachments - attachments.count)
      let urls = Array(panel.urls.prefix(remaining))
      if !urls.isEmpty {
        onAttachmentsAdded(urls)
      }
    }
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    ChatAttachmentDropHandler.collectURLs(from: providers) { [attachments] urls in
      guard !urls.isEmpty else { return }
      let remaining = max(0, kMaxChatAttachments - attachments.count)
      let allowed = Array(urls.prefix(remaining))
      if !allowed.isEmpty {
        onAttachmentsAdded(allowed)
      }
    }
  }

  private func handleSubmit() {
    if isSending {
      onStop()
    } else if canSend {
      onSend()
    }
  }

  @ViewBuilder
  private var actionButton: some View {
    switch actionMode {
    case .stop:
      stopButton
    case .send:
      sendButton
    case .none:
      EmptyView()
    }
  }

  private var actionMode: HomeAskBarActionMode {
    if isSending { return .stop }
    if canSend { return .send }
    return .none
  }

  private var sendButton: some View {
    Button(action: handleSubmit) {
      ZStack {
        Circle()
          .fill(Color.white)

        Image(systemName: "arrow.up")
          .scaledFont(size: OmiType.body, weight: .bold)
          .foregroundStyle(Color.black)
      }
      .frame(width: 34, height: 34)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Send")
    .accessibilityLabel("Send message")
  }

  private var stopButton: some View {
    Button(action: onStop) {
      ZStack {
        Circle()
          .fill(Color.white.opacity(0.14))

        if isStopping {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.6)
        } else {
          Image(systemName: "square.fill")
            .scaledFont(size: OmiType.micro, weight: .bold)
            .foregroundStyle(HomePalette.ink)
        }
      }
      .frame(width: 34, height: 34)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isStopping)
    .help("Stop")
    .accessibilityLabel("Stop response")
  }

}

private enum HomeAskBarActionMode: Equatable {
  case send
  case stop
  case none
}
