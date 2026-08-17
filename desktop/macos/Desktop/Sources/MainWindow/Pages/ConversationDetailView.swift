import OmiSupport
import OmiTheme
import SwiftUI

/// Full detail view for a single conversation
struct ConversationDetailView: View {
  let conversation: LocalConversation
  let onBack: () -> Void
  var folders: [Folder] = []
  var onMoveToFolder: ((String, String?) async -> Bool)?
  var onDelete: (() -> Void)?
  var onTitleUpdated: ((String) -> Void)?

  // Conversation-scoped speaker naming
  var onAssignSpeaker: ((String, [String], String?, Bool) async -> Bool)?

  // Transcript drawer state (replaces tab system)
  @State private var showTranscriptDrawer = false
  // When expanded, the transcript drawer fills the window (the summary pane
  // collapses) for full-width reading; collapsed it's the fixed side drawer.
  @State private var isTranscriptExpanded = false

  // Entry animation
  @State private var hasAppeared = false

  // Full conversation loaded from API (with transcript segments)
  @State private var loadedConversation: LocalConversation?
  @State private var isLoadingConversation = false
  // True while durable local enrichment work is still pending.
  @State private var isEnrichingDeferred = false

  // Action states
  @State private var showDeleteConfirmation = false
  @State private var showEditDialog = false
  @State private var editedTitle = ""
  @State private var isUpdatingTitle = false
  @State private var isDeleting = false
  @State private var isRetryingEnrichment = false

  // Speaker naming state
  @State private var selectedSegmentForNaming: TranscriptSegment? = nil

  static func assignmentMetadata(
    for segmentIndices: [Int],
    in segments: [TranscriptSegment]
  ) -> [String] {
    let validIndices = segmentIndices.filter { segments.indices.contains($0) }
    return validIndices.map { segments[$0].id }
  }

  /// The conversation to display - use loaded version if available, otherwise use prop
  private var displayConversation: LocalConversation {
    loadedConversation ?? conversation
  }

  /// The date to display (prefer startedAt, fall back to createdAt)
  private var displayDate: Date {
    displayConversation.startedAt
  }

  // Static date formatters — creating DateFormatter is expensive, avoid per-render allocation
  private static let dayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, MMM d, yyyy"
    return f
  }()
  private static let timeOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
  }()
  private static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    return f
  }()

  /// Format date for display
  private var formattedDate: String {
    Self.dayDateFormatter.string(from: displayDate)
  }

  /// Format time for display
  private var formattedTime: String {
    Self.timeOnlyFormatter.string(from: displayDate)
  }

  /// Format time range for header subtitle (e.g., "Jan 15, 2025 from 2:30 PM to 3:15 PM")
  private var formattedTimeRange: String {
    let dateStr = Self.shortDateFormatter.string(from: displayDate)
    let startStr = Self.timeOnlyFormatter.string(from: displayDate)

    if let finishedAt = displayConversation.finishedAt {
      let endStr = Self.timeOnlyFormatter.string(from: finishedAt)
      return "\(dateStr) from \(startStr) to \(endStr)"
    }
    return "\(dateStr) at \(startStr)"
  }

  var body: some View {
    HStack(spacing: 0) {
      // Main content (always visible)
      VStack(alignment: .leading, spacing: 0) {
        headerView

        ScrollView {
          // Card container wrapping summary content
          VStack(alignment: .leading, spacing: 0) {
            // Card header bar
            HStack(spacing: OmiSpacing.sm) {
              Image(systemName: "doc.text")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
              Text("Conversation Details")
                .scaledFont(size: OmiType.body, weight: .medium)
                .foregroundColor(OmiColors.textSecondary)
              Spacer()
            }
            .padding(.horizontal, OmiSpacing.lg)
            .padding(.vertical, OmiSpacing.sm)
            .background(OmiColors.backgroundTertiary.opacity(0.4))

            VStack(alignment: .leading, spacing: OmiSpacing.xxl) {
              summaryContent
            }
            .padding(OmiSpacing.xxl)
          }
          .background(
            RoundedRectangle(cornerRadius: OmiChrome.controlRadius)
              .fill(OmiColors.backgroundSecondary.opacity(0.6))
          )
          .clipShape(RoundedRectangle(cornerRadius: OmiChrome.controlRadius))
          .overlay(
            RoundedRectangle(cornerRadius: OmiChrome.controlRadius)
              .stroke(OmiColors.backgroundTertiary.opacity(0.3), lineWidth: 1)
          )
          .overlay(alignment: .top) {
            if isEnrichingDeferred {
              deferredProcessingSection
                .padding(OmiSpacing.xxl)
                .allowsHitTesting(false)
            }
          }
          .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 8)
          .padding(OmiSpacing.xxl)
        }
      }
      // Collapses to zero width when the transcript is expanded so the drawer
      // can fill the window; otherwise it's the greedy main pane.
      .frame(maxWidth: isTranscriptExpanded ? 0 : .infinity)
      .opacity(isTranscriptExpanded ? 0 : 1)
      .clipped()

      // Transcript drawer (slides in from right; expands to fill on demand)
      if showTranscriptDrawer {
        if !isTranscriptExpanded {
          Rectangle()
            .fill(OmiColors.border)
            .frame(width: 1)
        }

        transcriptDrawerView
          .frame(maxWidth: isTranscriptExpanded ? .infinity : 450)
          .transition(.move(edge: .trailing))
      }
    }
    .opacity(hasAppeared ? 1 : 0)
    .offset(y: hasAppeared ? 0 : 20)
    .onAppear {
      showTranscriptDrawer = ConversationDetailAutomationState.shared.syncPresentedDetail(
        conversationId: conversation.id,
        transcriptDrawerOpen: showTranscriptDrawer
      )
      OmiMotion.withGated(.easeOut(duration: 0.5)) {
        hasAppeared = true
      }
    }
    .onChange(of: conversation.id) { _, conversationId in
      showTranscriptDrawer = ConversationDetailAutomationState.shared.syncPresentedDetail(
        conversationId: conversationId,
        transcriptDrawerOpen: showTranscriptDrawer
      )
    }
    .onDisappear {
      ConversationDetailAutomationState.shared.clear(conversationId: conversation.id)
    }
    .onChange(of: showTranscriptDrawer) { _, newValue in
      ConversationDetailAutomationState.shared.setTranscriptDrawerOpen(
        newValue, conversationId: conversation.id)
    }
    .task {
      AnalyticsManager.shared.conversationDetailOpened()

      // All detail reads go through the owner-scoped local repository.
      if conversation.status == .processing {
        isEnrichingDeferred = true
        var attempts = 0
        while attempts < 15 {
          guard let appState = AppState.current else { break }
          let fetched = await appState.loadConversationDetail(conversation)
          loadedConversation = fetched
          if fetched.status != .processing { break }
          attempts += 1
          try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        isEnrichingDeferred = false
        return
      }

      isLoadingConversation = true
      if let appState = AppState.current {
        loadedConversation = await appState.loadConversationDetail(conversation)
      }
      isLoadingConversation = false
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .desktopAutomationShowConversationTranscriptRequested)
    ) { notification in
      guard let conversationId = notification.userInfo?["conversationId"] as? String,
        conversationId == displayConversation.id
      else { return }
      OmiMotion.withGated(.easeInOut(duration: 0.2)) {
        showTranscriptDrawer = true
      }
    }
    .dismissableSheet(item: $selectedSegmentForNaming) { segment in
      NameSpeakerSheet(
        segment: segment,
        allSegments: displayConversation.transcriptSegments,
        onSave: { speakerName, isUser, segmentIndices in
          Task {
            let segmentIds = Self.assignmentMetadata(
              for: segmentIndices,
              in: displayConversation.transcriptSegments
            )
            let success =
              await onAssignSpeaker?(
                conversation.id,
                segmentIds,
                speakerName,
                isUser
              ) ?? false
            if success {
              updateDisplayedConversation(
                segmentIndices: segmentIndices,
                isUser: isUser,
                speakerName: speakerName)
            }
            selectedSegmentForNaming = nil
          }
        },
        onDismiss: {
          selectedSegmentForNaming = nil
        }
      )
    }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(spacing: OmiSpacing.md) {
      // Back button
      Button(action: onBack) {
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "chevron.left")
            .scaledFont(size: OmiType.body, weight: .medium)
          Text("Back")
            .scaledFont(size: OmiType.body, weight: .medium)
        }
        .foregroundColor(OmiColors.accent)
      }
      .buttonStyle(.plain)

      // Emoji
      Text(displayConversation.structured.emoji.isEmpty ? "\u{1F4AC}" : displayConversation.structured.emoji)
        .scaledFont(size: OmiType.title)

      // Title + timestamp subtitle
      VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
        HStack(spacing: OmiSpacing.sm) {
          Text(displayConversation.title)
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
            .lineLimit(1)

          // Edit title button (inline with title)
          Button(action: {
            editedTitle = displayConversation.title
            showEditDialog = true
          }) {
            Image(systemName: "pencil")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
          }
          .buttonStyle(.plain)
          .help("Edit title")
        }

        Text(formattedTimeRange)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
      }

      Spacer()

      // Status badge
      if displayConversation.status != .completed {
        statusBadge
      }

      // View Transcript pill button
      viewTranscriptButton

      // Inline action buttons
      inlineActionButtons
    }
    .padding(.horizontal, OmiSpacing.xxl)
    .padding(.vertical, OmiSpacing.lg)
    .alert("Edit Conversation Title", isPresented: $showEditDialog) {
      TextField("Title", text: $editedTitle)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        Task { await updateTitle() }
      }
      .disabled(editedTitle.isEmpty || isUpdatingTitle)
    } message: {
      Text("Enter a new title for this conversation")
    }
    .alert("Delete Conversation", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task { await deleteConversation() }
      }
    } message: {
      Text("Are you sure you want to delete this conversation? This action cannot be undone.")
    }
  }

  // MARK: - View Transcript Button

  private var viewTranscriptButton: some View {
    Button(action: {
      OmiMotion.withGated(.easeInOut(duration: 0.25)) {
        showTranscriptDrawer.toggle()
      }
    }) {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: "text.quote")
          .scaledFont(size: OmiType.caption)
        Text(showTranscriptDrawer ? "Hide Transcript" : "View Transcript")
          .scaledFont(size: OmiType.caption, weight: .medium)
      }
      .foregroundColor(showTranscriptDrawer ? OmiColors.backgroundPrimary : OmiColors.textSecondary)
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.xs)
      .background(
        Capsule()
          .fill(showTranscriptDrawer ? OmiColors.accent : OmiColors.backgroundTertiary)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Inline Action Buttons

  private var inlineActionButtons: some View {
    HStack(spacing: OmiSpacing.sm) {
      // Copy transcript button
      Button(action: copyTranscript) {
        Image(systemName: "doc.on.doc")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)
          .frame(width: 28, height: 28)
          .background(
            Circle()
              .fill(OmiColors.backgroundTertiary)
          )
      }
      .buttonStyle(.plain)
      .disabled(!canCopyTranscript)
      .help("Copy transcript")

      // Move to folder button (menu)
      if !folders.isEmpty {
        Menu {
          if displayConversation.folderId != nil {
            Button(action: {
              Task { await moveDisplayedConversation(to: nil) }
            }) {
              Label("Remove from Folder", systemImage: "folder.badge.minus")
            }
            Divider()
          }

          ForEach(folders) { folder in
            Button(action: {
              Task { await moveDisplayedConversation(to: folder.id) }
            }) {
              HStack {
                Text(folder.name)
                if displayConversation.folderId == folder.id {
                  Image(systemName: "checkmark")
                }
              }
            }
            .disabled(displayConversation.folderId == folder.id)
          }
        } label: {
          Image(systemName: displayConversation.folderId != nil ? "folder.fill" : "folder")
            .scaledFont(size: OmiType.body)
            .foregroundColor(displayConversation.folderId != nil ? OmiColors.accent : OmiColors.textSecondary)
            .frame(width: 28, height: 28)
            .background(
              Circle()
                .fill(OmiColors.backgroundTertiary)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .help("Move to folder")
      }

      // Delete button
      Button(action: { showDeleteConfirmation = true }) {
        Image(systemName: "trash")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.error)
          .frame(width: 28, height: 28)
          .background(
            Circle()
              .fill(OmiColors.backgroundTertiary)
          )
      }
      .buttonStyle(.plain)
      .help("Delete conversation")
    }
  }

  private var canCopyTranscript: Bool {
    true
  }

  // MARK: - Actions

  private func copyTranscript() {
    guard canCopyTranscript else { return }

    let transcript: String = displayConversation.transcriptSegments.map { segment -> String in
      let speakerName: String
      if segment.isUser {
        speakerName = "You"
      } else if let label = localSpeakerName(for: segment) {
        speakerName = label
      } else {
        speakerName = "Speaker \(segment.speakerId)"
      }
      return "[\(speakerName)]: \(segment.text)"
    }.joined(separator: "\n\n")

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcript, forType: .string)
  }

  private func updateTitle() async {
    let normalized = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    isUpdatingTitle = true
    defer { isUpdatingTitle = false }

    guard await AppState.current?.updateConversationTitle(conversation.id, title: normalized) == true else {
      return
    }
    var projected = displayConversation
    projected.structured.title = normalized
    loadedConversation = projected
    onTitleUpdated?(normalized)
  }

  private func moveDisplayedConversation(to folderId: String?) async {
    guard await onMoveToFolder?(displayConversation.id, folderId) == true else { return }
    var projected = displayConversation
    projected.folderId = folderId
    loadedConversation = projected
  }

  private func deleteConversation() async {
    isDeleting = true
    defer { isDeleting = false }

    let conversationId = conversation.id
    if await AppState.current?.deleteConversation(conversationId) == true {
      await MainActor.run {
        onDelete?()
        onBack()
      }
    }
  }

  private var statusBadge: some View {
    Text(displayConversation.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
      .scaledFont(size: OmiType.caption, weight: .medium)
      .foregroundColor(statusColor)
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.xxs)
      .background(
        Capsule()
          .fill(statusColor.opacity(0.2))
      )
  }

  private var statusColor: Color {
    switch displayConversation.status {
    case .completed:
      return OmiColors.success
    case .processing, .merging:
      return OmiColors.info
    case .inProgress:
      return OmiColors.warning
    case .failed:
      return OmiColors.error
    }
  }

  // MARK: - Summary Content (always visible, no tabs)

  @ViewBuilder
  private var summaryContent: some View {
    if let message = ConversationEnrichmentFailurePresentation.message(
      for: displayConversation.enrichmentFailures)
    {
      enrichmentFailureSection(message: message)
    }

    // Overview section
    if !displayConversation.overview.isEmpty {
      overviewSection
    }

    // Metadata chips
    metadataSection

    // Action items section
    if !displayConversation.structured.actionItems.isEmpty {
      actionItemsSection
    }
  }

  private func enrichmentFailureSection(message: String) -> some View {
    HStack(spacing: OmiSpacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundColor(OmiColors.warning)
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text(message)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text("Your transcript is safe on this Mac.")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
      }
      Spacer()
      Button(isRetryingEnrichment ? "Retrying…" : "Retry") {
        Task { await retryEnrichment() }
      }
      .disabled(isRetryingEnrichment)
    }
    .padding(OmiSpacing.lg)
    .background(OmiColors.backgroundTertiary.opacity(0.5))
    .cornerRadius(OmiChrome.smallControlRadius)
  }

  private func retryEnrichment() async {
    guard !isRetryingEnrichment else { return }
    isRetryingEnrichment = true
    defer { isRetryingEnrichment = false }
    if let retried = await AppState.current?.retryConversationEnrichment(id: displayConversation.id) {
      loadedConversation = retried
    }
  }

  // MARK: - Transcript Drawer

  @ViewBuilder
  private var transcriptDrawerView: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Drawer header
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: "text.quote")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)

        Text("Transcript")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)

        // Segment count badge
        Text("\(displayConversation.transcriptSegments.count)")
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(OmiColors.accent)
          .padding(.horizontal, OmiSpacing.sm)
          .padding(.vertical, OmiSpacing.hairline)
          .background(
            Capsule()
              .fill(OmiColors.accent.opacity(0.15))
          )

        Spacer()

        // Expand / collapse the drawer to fill the window for full-width reading
        Button(action: {
          OmiMotion.withGated(.easeInOut(duration: 0.25)) {
            isTranscriptExpanded.toggle()
          }
        }) {
          Image(
            systemName: isTranscriptExpanded
              ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
          )
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)
          .frame(width: 28, height: 28)
          .background(Circle().fill(OmiColors.backgroundTertiary))
        }
        .buttonStyle(.plain)
        .help(isTranscriptExpanded ? "Collapse transcript" : "Expand transcript")

        // Copy button
        Button(action: copyTranscript) {
          Image(systemName: "doc.on.doc")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textSecondary)
            .frame(width: 28, height: 28)
            .background(
              Circle()
                .fill(OmiColors.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
        .help("Copy transcript")

        // Close button
        Button(action: {
          OmiMotion.withGated(.easeInOut(duration: 0.25)) {
            showTranscriptDrawer = false
            isTranscriptExpanded = false
          }
        }) {
          Image(systemName: "xmark")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textSecondary)
            .frame(width: 28, height: 28)
            .background(
              Circle()
                .fill(OmiColors.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
        .help("Close transcript")
      }
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.vertical, OmiSpacing.md)
      .background(OmiColors.backgroundTertiary.opacity(0.5))

      // Drawer content
      if displayConversation.transcriptSegments.isEmpty && !isLoadingConversation {
        // Empty state
        VStack(spacing: OmiSpacing.md) {
          Image(systemName: "text.quote")
            .scaledFont(size: OmiType.hero)
            .foregroundColor(OmiColors.textTertiary.opacity(0.5))

          Text("No transcript available")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if isLoadingConversation {
        // Loading state
        VStack(spacing: OmiSpacing.md) {
          ProgressView()
            .scaleEffect(0.8)

          Text("Loading transcript...")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        // LazyVStack is a DIRECT child of ScrollView so it gets bounded proposed height
        // and only materializes visible children.
        ScrollView {
          LazyVStack(alignment: .leading, spacing: OmiSpacing.md) {
            transcriptBubblesContent
          }
          .padding(OmiSpacing.lg)
        }
      }
    }
    .background(OmiColors.backgroundPrimary)
  }

  // MARK: - Transcript Bubbles (shared)

  /// Flat content intended to be placed inside a parent LazyVStack.
  /// Do NOT wrap this in another LazyVStack or VStack — it emits ForEach items directly.
  @ViewBuilder
  private var transcriptBubblesContent: some View {
    ForEach(displayConversation.transcriptSegments) { segment in
      SpeakerBubbleView(
        segment: segment,
        isUser: segment.isUser,
        personName: localSpeakerName(for: segment),
        onSpeakerTapped: segment.isUser
          ? nil
          : {
            selectedSegmentForNaming = segment
          }
      )
      .padding(.horizontal, OmiSpacing.lg)
    }
  }

  @MainActor
  private func updateDisplayedConversation(
    segmentIndices: [Int],
    isUser: Bool,
    speakerName: String?
  ) {
    var updatedConversation = displayConversation
    for index in segmentIndices where updatedConversation.transcriptSegments.indices.contains(index) {
      let oldSegment = updatedConversation.transcriptSegments[index]
      updatedConversation.transcriptSegments[index] = TranscriptSegment(
        id: oldSegment.id,
        text: oldSegment.text,
        speaker: isUser ? "You" : speakerName,
        speakerId: oldSegment.speakerId,
        isUser: isUser,
        start: oldSegment.start,
        end: oldSegment.end,
        translations: oldSegment.translations
      )
    }
    loadedConversation = updatedConversation
  }

  private func localSpeakerName(for segment: TranscriptSegment) -> String? {
    guard !segment.isUser, let value = segment.speaker else { return nil }
    return value.hasPrefix("SPEAKER_") ? nil : value
  }

  // MARK: - Deferred Processing Loader

  /// Overlaid while durable local enrichment work is still pending.
  private var deferredProcessingSection: some View {
    HStack(spacing: OmiSpacing.md) {
      ProgressView()
        .controlSize(.small)
      VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
        Text("Processing conversation…")
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text("Generating summary and action items")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
      }
      Spacer()
    }
    .padding(OmiSpacing.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(OmiColors.backgroundTertiary.opacity(0.5))
    .cornerRadius(OmiChrome.smallControlRadius)
  }

  // MARK: - Overview Section

  private var overviewSection: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: "star.fill")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.15))

        Text("Summary")
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundColor(OmiColors.textSecondary)
      }

      OmiMarkdown(text: displayConversation.overview, sender: .ai)
        .textSelection(.enabled)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Metadata Section

  private var metadataSection: some View {
    HStack(spacing: OmiSpacing.md) {
      // Duration chip
      metadataChip(icon: "hourglass", text: displayConversation.formattedDuration)

      Spacer()
    }
  }

  private func metadataChip(icon: String, text: String) -> some View {
    HStack(spacing: OmiSpacing.xs) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textTertiary)

      Text(text)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textSecondary)
    }
    .padding(.horizontal, OmiSpacing.sm)
    .padding(.vertical, OmiSpacing.xs)
    .background(
      Capsule()
        .fill(OmiColors.backgroundTertiary)
    )
  }

  // MARK: - App Results Section

  // MARK: - Action Items Section

  private var actionItemsSection: some View {
    let activeItems = displayConversation.structured.actionItems.filter { !$0.deleted }
    return VStack(alignment: .leading, spacing: OmiSpacing.md) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: "checklist")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)

        Text("Action Items")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textSecondary)

        // Count badge
        Text("\(activeItems.count)")
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(OmiColors.accent)
          .padding(.horizontal, OmiSpacing.sm)
          .padding(.vertical, OmiSpacing.hairline)
          .background(
            Capsule()
              .fill(OmiColors.accent.opacity(0.15))
          )

        Spacer()
      }

      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        ForEach(activeItems) { item in
          HStack(alignment: .top, spacing: OmiSpacing.sm) {
            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(item.completed ? OmiColors.success : OmiColors.textTertiary)

            Text(item.description)
              .scaledFont(size: OmiType.body)
              .foregroundColor(item.completed ? OmiColors.textTertiary : OmiColors.textPrimary)
              .textSelection(.enabled)
              .strikethrough(item.completed, color: OmiColors.textTertiary)
          }
          .padding(OmiSpacing.md)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
              .fill(OmiColors.backgroundTertiary)
          )
          .overlay(
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
              .stroke(OmiColors.backgroundTertiary.opacity(0.3), lineWidth: 1)
          )
        }
      }
    }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    ConversationDetailView(
      conversation: LocalConversation.preview,
      onBack: {}
    )
    .frame(width: 600, height: 800)
    .background(OmiColors.backgroundPrimary)
  }
#endif

// Preview helper
extension LocalConversation {
  static var preview: LocalConversation {
    // This would need to be implemented with a proper initializer
    // For now, previews won't work without mock data
    fatalError("Preview not implemented")
  }
}
