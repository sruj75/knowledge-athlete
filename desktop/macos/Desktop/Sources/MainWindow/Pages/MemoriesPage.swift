import AppKit
import Combine
import OmiTheme
import SwiftUI

extension Notification.Name {
  /// Automation-only: opens a memory's detail panel by local row ID, or closes it
  /// when no id is supplied.
  static let desktopAutomationMemoryDetailOpenRequested = Notification.Name(
    "desktopAutomationMemoryDetailOpenRequested"
  )
}

enum MemoryPageCopy {
  static let subtitle = "Memories and insights saved on this Mac"
}

/// Memory categories for filtering. Categories are stored in the effective
/// owner's local database; tags remain independent presentation metadata.
enum MemoryTag: String, CaseIterable, Identifiable {
  case manual
  case system
  case interesting

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .manual: return "Manual"
    case .system: return "About You"
    case .interesting: return "Insights"
    }
  }

  var icon: String {
    switch self {
    case .manual: return "square.and.pencil"
    case .system: return "person"
    case .interesting: return "lightbulb"
    }
  }

  var color: Color { OmiColors.textSecondary }

  var category: MemoryCategory {
    switch self {
    case .manual: return .manual
    case .system: return .system
    case .interesting: return .interesting
    }
  }

  func matches(_ memory: MemoryItem) -> Bool {
    memory.category == category
  }
}

enum MemoryLayerFilter: String, CaseIterable, Identifiable {
  case defaultAccess
  case shortTerm
  case longTerm
  case archive

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .defaultAccess: return "Default"
    case .shortTerm: return "Short-term"
    case .longTerm: return "Long-term"
    case .archive: return "Archive"
    }
  }

  var description: String {
    switch self {
    case .defaultAccess: return "Short-term + Long-term"
    case .shortTerm: return "Fresh source-backed memories"
    case .longTerm: return "Stable memories"
    case .archive: return "Explicit archive search"
    }
  }

  var layerScope: MemoryLayerScope {
    switch self {
    case .defaultAccess: return .defaultAccess
    case .shortTerm:
      return MemoryLayerScope(layers: [.shortTerm], requiresArchiveAcknowledgement: false)
    case .longTerm:
      return MemoryLayerScope(layers: [.longTerm], requiresArchiveAcknowledgement: false)
    case .archive: return .archiveOnly
    }
  }

  var allowedLayers: [MemoryLayer] { layerScope.layers }
}

// MARK: - Memories Page

struct MemoriesPage: View {
  @ObservedObject var viewModel: MemoriesViewModel
  @State private var showCategoryFilter = false
  @State private var pendingSelectedTags: Set<MemoryTag> = []
  @State private var showManagementMenu = false

  var body: some View {
    Group {
      if let conversation = viewModel.linkedConversation {
        // Show conversation detail view
        ConversationDetailView(
          conversation: conversation,
          onBack: { viewModel.dismissConversation() }
        )
      } else {
        // Main memories view
        mainMemoriesView
      }
    }
  }

  private var memoriesColumn: some View {
    VStack(spacing: 0) {
      // Header (includes search, filters, and action buttons)
      header

      // Content
      if viewModel.isLoading && viewModel.memories.isEmpty {
        loadingView
      } else if let error = viewModel.errorMessage {
        errorView(error)
      } else if viewModel.memories.isEmpty {
        emptyState
      } else if viewModel.filteredMemories.isEmpty {
        noResultsView
      } else {
        memoryList
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func memoryDetailPanel(_ memory: MemoryItem) -> some View {
    MemoryDetailPanel(
      memory: memory,
      viewModel: viewModel,
      categoryIcon: categoryIcon,
      categoryColor: categoryColor,
      tagColorFor: tagColorFor,
      formatDate: formatDate,
      onDismiss: { viewModel.selectedMemory = nil }
    )
    // Identity per memory: the panel holds edit state, and without this
    // SwiftUI reuses the same instance across selections, carrying one
    // memory's unsaved draft into the next memory's editor.
    .id(memory.id)
    // The panel sizes to this column rather than carrying its own width, which
    // is what kept the old sheet's 450pt content clipped inside it.
    .frame(width: 360)
    .frame(maxHeight: .infinity)
    .background(OmiColors.backgroundSecondary)
    .overlay(alignment: .leading) {
      Rectangle().fill(OmiColors.border.opacity(0.25)).frame(width: 1)
    }
    .accessibilityIdentifier("memory_detail_panel")
  }

  private var mainMemoriesView: some View {
    // A memory opens into a side panel, not a modal, so reading one thing never
    // covers the list it came from.
    HStack(spacing: 0) {
      memoriesColumn

      if let memory = viewModel.selectedMemory {
        memoryDetailPanel(memory)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(OmiMotion.gated(.easeOut(duration: 0.18)), value: viewModel.selectedMemory?.id)
    .background(Color.clear)
    .dismissableSheet(isPresented: $viewModel.showingAddMemory) {
      AddMemorySheet(viewModel: viewModel, onDismiss: { viewModel.showingAddMemory = false })
        .frame(width: 400)
    }
    .dismissableSheet(item: $viewModel.editingMemory) { memory in
      EditMemorySheet(
        memory: memory, viewModel: viewModel, onDismiss: { viewModel.editingMemory = nil }
      )
      .frame(width: 400)
    }
    .overlay(alignment: .bottom) {
      undoDeleteToast
    }
    .overlay {
      // Loading overlay for conversation fetch
      if viewModel.isLoadingConversation {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .overlay {
            ProgressView()
              .scaleEffect(1.2)
              .tint(.white)
          }
      }
    }
    .task {
      await viewModel.loadMemoriesIfNeeded()
    }
    // Opening a memory is a click on a card, so the detail panel is otherwise
    // unreachable to cursor-free QA. This is the same entry point the card uses.
    .onReceive(
      NotificationCenter.default.publisher(for: .desktopAutomationMemoryDetailOpenRequested)
    ) { note in
      guard let memoryId = note.userInfo?["memory_id"] as? String, !memoryId.isEmpty else {
        viewModel.selectedMemory = nil
        return
      }
      Task { await viewModel.openMemory(id: memoryId) }
    }
  }

  // MARK: - Undo Delete Toast

  @ViewBuilder
  private var undoDeleteToast: some View {
    if viewModel.pendingDeleteMemory != nil {
      HStack(spacing: OmiSpacing.md) {
        Image(systemName: "trash")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)

        Text("Memory deleted")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textPrimary)

        Spacer()

        // Progress indicator
        Text(String(format: "%.0fs", viewModel.undoTimeRemaining))
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(OmiColors.textTertiary)
          .monospacedDigit()

        Button {
          Task { await viewModel.undoDelete() }
        } label: {
          Text("Undo")
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)
        }
        .buttonStyle(.plain)

        Button {
          // Dismiss immediately and delete now
          viewModel.confirmDelete()
        } label: {
          Image(systemName: "xmark")
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundColor(OmiColors.textTertiary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, OmiSpacing.lg)
      .padding(.vertical, OmiSpacing.md)
      .omiPanel(
        fill: OmiColors.backgroundSecondary, radius: 20, stroke: OmiColors.border.opacity(0.18),
        shadowOpacity: 0.18, shadowRadius: 14, shadowY: 8
      )
      .padding(.horizontal, OmiSpacing.xxl)
      .padding(.bottom, OmiSpacing.xxl)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .omiAnimation(
        .spring(response: 0.3, dampingFraction: 0.8), value: viewModel.pendingDeleteMemory != nil)
    }
  }

  // MARK: - Header
  private var header: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text("Memories")
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundStyle(OmiColors.textPrimary)
          Text(MemoryPageCopy.subtitle)
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(OmiColors.textTertiary)
        }
        Spacer()
      }

      // A pill row and a text field cannot share one line in a narrow column.
      // The pills hold their intrinsic width so their own labels stay readable,
      // which used to leave the search field squeezed to "Sea" whenever the
      // detail panel was open. Below the width where both fit, the search field
      // takes its own line instead of being the thing that loses.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: OmiSpacing.sm) {
          searchField.frame(minWidth: 200)
          filterControls
        }

        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          searchField
          HStack(spacing: OmiSpacing.sm) {
            filterControls
            Spacer(minLength: 0)
          }
        }
      }
    }
    .padding(.horizontal, OmiSpacing.xxl)
    .padding(.top, OmiSpacing.lg)
    .padding(.bottom, OmiSpacing.md)
    .alert("Delete Default Memories?", isPresented: $viewModel.showingDeleteAllConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Default Memories", role: .destructive) {
        Task { await viewModel.deleteMemories(scope: .defaultAccess) }
      }
    } message: {
      Text("This deletes Short-term and Long-term memories saved on this Mac. Archive is not included.")
    }
  }

  private var searchField: some View {
    OmiSearchField(
      placeholder: "Search memories",
      text: $viewModel.searchText,
      isLoading: viewModel.isSearching || viewModel.isLoadingFiltered
    )
  }

  @ViewBuilder
  private var filterControls: some View {
    // Layer filter dropdown. Default is product default access: Short-term + Long-term.
    Menu {
      ForEach(MemoryLayerFilter.allCases) { filter in
        Button {
          viewModel.selectedLayerFilter = filter
        } label: {
          HStack {
            Text(filter.displayName)
            if viewModel.selectedLayerFilter == filter {
              Image(systemName: "checkmark")
            }
          }
        }
        .help(filter.description)
      }
    } label: {
      HStack(spacing: OmiSpacing.xs) {
        Image(
          systemName: viewModel.selectedLayerFilter == .archive
            ? "archivebox" : "clock.badge.checkmark"
        )
        .scaledFont(size: OmiType.caption)
        Text(viewModel.selectedLayerFilter.displayName)
          .scaledFont(
            size: OmiType.body,
            weight: viewModel.selectedLayerFilter == .defaultAccess ? .regular : .medium
          )
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        Image(systemName: "chevron.down")
          .scaledFont(size: OmiType.micro)
      }
      .foregroundColor(
        viewModel.selectedLayerFilter == .defaultAccess
          ? OmiColors.textSecondary : OmiColors.textPrimary
      )
      .padding(.horizontal, OmiSpacing.md)
      .frame(minHeight: 44)
      .omiControlSurface(
        fill: viewModel.selectedLayerFilter == .defaultAccess
          ? OmiColors.backgroundSecondary : OmiColors.backgroundRaised,
        radius: 16,
        stroke: OmiColors.border.opacity(
          viewModel.selectedLayerFilter == .defaultAccess ? 0.18 : 0.6)
      )
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .help("Default shows Short-term + Long-term. Archive is explicit.")

    // Category filter dropdown
    Button {
      pendingSelectedTags = viewModel.selectedTags
      showCategoryFilter = true
    } label: {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: "line.3.horizontal.decrease")
          .scaledFont(size: OmiType.caption)
        Text(categoryFilterLabel)
          .scaledFont(
            size: OmiType.body, weight: viewModel.selectedTags.isEmpty ? .regular : .medium
          )
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        Image(systemName: "chevron.down")
          .scaledFont(size: OmiType.micro)
      }
      .foregroundColor(
        viewModel.selectedTags.isEmpty ? OmiColors.textSecondary : OmiColors.textPrimary
      )
      .padding(.horizontal, OmiSpacing.md)
      .frame(minHeight: 44)
      .omiControlSurface(
        fill: viewModel.selectedTags.isEmpty
          ? OmiColors.backgroundSecondary : OmiColors.backgroundRaised,
        radius: 16,
        stroke: OmiColors.border.opacity(viewModel.selectedTags.isEmpty ? 0.18 : 0.6)
      )
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showCategoryFilter, arrowEdge: .bottom) {
      categoryFilterPopover
    }

    // Add Memory button (icon only)
    Button {
      viewModel.showingAddMemory = true
    } label: {
      Image(systemName: "plus")
        .scaledFont(size: OmiType.body)
        .foregroundColor(.black)
        .frame(width: 44, height: 44)
        .background(OmiColors.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .help("Add Memory")

    // Management menu
    Button {
      showManagementMenu = true
    } label: {
      Image(systemName: "ellipsis")
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundColor(OmiColors.textSecondary)
        .frame(width: 44, height: 44)
        .omiControlSurface(
          fill: OmiColors.backgroundSecondary,
          radius: 14,
          stroke: OmiColors.border.opacity(0.18)
        )
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showManagementMenu, arrowEdge: .bottom) {
      managementMenuPopover
    }
  }

  // MARK: - Filter Bar

  /// Label for the category filter button
  private var categoryFilterLabel: String {
    if viewModel.selectedTags.isEmpty {
      return "All"
    } else if viewModel.selectedTags.count == 1 {
      return viewModel.selectedTags.first!.displayName
    } else {
      return "\(viewModel.selectedTags.count) selected"
    }
  }

  /// Categories sorted by local count (highest first).
  private var filteredCategories: [MemoryTag] {
    MemoryTag.allCases.sorted { viewModel.tagCount($0) > viewModel.tagCount($1) }
  }

  private var categoryFilterPopover: some View {
    VStack(spacing: 0) {
      // Category list
      ScrollView {
        VStack(spacing: OmiSpacing.hairline) {
          // "All" option
          Button {
            pendingSelectedTags.removeAll()
          } label: {
            HStack {
              Image(systemName: "tray.full")
                .scaledFont(size: OmiType.caption)
                .frame(width: 20)
              Text("All")
                .scaledFont(size: OmiType.body)
              Spacer()
              Text("\(viewModel.totalMemoriesCount)")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(OmiColors.textTertiary)
                .padding(.horizontal, OmiSpacing.xs)
                .padding(.vertical, OmiSpacing.hairline)
                .background(OmiColors.backgroundTertiary)
                .cornerRadius(OmiChrome.stripRadius)
              if pendingSelectedTags.isEmpty {
                Image(systemName: "checkmark")
                  .scaledFont(size: OmiType.caption, weight: .medium)
                  .foregroundColor(.white)
              }
            }
            .foregroundColor(OmiColors.textPrimary)
            .padding(.horizontal, OmiSpacing.md)
            .padding(.vertical, OmiSpacing.sm)
            .background(
              pendingSelectedTags.isEmpty ? OmiColors.backgroundTertiary.opacity(0.5) : Color.clear
            )
            .cornerRadius(OmiChrome.badgeRadius)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          Divider()
            .padding(.vertical, OmiSpacing.xxs)

          // Category items
          ForEach(filteredCategories) { tag in
            let isSelected = pendingSelectedTags.contains(tag)
            let count = viewModel.tagCount(tag)

            Button {
              if isSelected {
                pendingSelectedTags.remove(tag)
              } else {
                pendingSelectedTags.insert(tag)
              }
            } label: {
              HStack {
                Image(systemName: tag.icon)
                  .scaledFont(size: OmiType.caption)
                  .frame(width: 20)
                Text(tag.displayName)
                  .scaledFont(size: OmiType.body)
                Spacer()
                Text("\(count)")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(OmiColors.textTertiary)
                  .padding(.horizontal, OmiSpacing.xs)
                  .padding(.vertical, OmiSpacing.hairline)
                  .background(OmiColors.backgroundTertiary)
                  .cornerRadius(OmiChrome.stripRadius)
                if isSelected {
                  Image(systemName: "checkmark")
                    .scaledFont(size: OmiType.caption, weight: .medium)
                    .foregroundColor(.white)
                }
              }
              .foregroundColor(OmiColors.textPrimary)
              .padding(.horizontal, OmiSpacing.md)
              .padding(.vertical, OmiSpacing.sm)
              .background(isSelected ? OmiColors.backgroundTertiary.opacity(0.5) : Color.clear)
              .cornerRadius(OmiChrome.badgeRadius)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
      }
      .frame(maxHeight: 300)

      Divider()
        .padding(.horizontal, OmiSpacing.md)

      // Action buttons
      HStack(spacing: OmiSpacing.sm) {
        Button {
          pendingSelectedTags.removeAll()
        } label: {
          Text("Clear")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textSecondary)
            .padding(.horizontal, OmiSpacing.lg)
            .padding(.vertical, OmiSpacing.sm)
            .background(OmiColors.backgroundTertiary)
            .cornerRadius(OmiChrome.badgeRadius)
        }
        .buttonStyle(.plain)

        Button {
          viewModel.selectedTags = pendingSelectedTags
          showCategoryFilter = false
        } label: {
          Text("Apply")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(.black)
            .padding(.horizontal, OmiSpacing.lg)
            .padding(.vertical, OmiSpacing.sm)
            .background(Color.white)
            .cornerRadius(OmiChrome.badgeRadius)
        }
        .buttonStyle(.plain)
      }
      .padding(OmiSpacing.md)
    }
    .frame(width: 280)
    .background(OmiColors.backgroundSecondary)
  }

  // MARK: - Management Menu Popover

  private var managementMenuPopover: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Danger section
      Button {
        showManagementMenu = false
        viewModel.showingDeleteAllConfirmation = true
      } label: {
        HStack(spacing: OmiSpacing.sm) {
          Image(systemName: "trash")
            .scaledFont(size: OmiType.body)
            .frame(width: 20)
          Text("Delete Default Memories")
            .scaledFont(size: OmiType.body)
          Spacer()
        }
        .foregroundColor(OmiColors.error)
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(
        !viewModel.areBulkMutationsAvailable || viewModel.memories.isEmpty || viewModel.isBulkOperationInProgress
      )
      .opacity(
        !viewModel.areBulkMutationsAvailable || viewModel.memories.isEmpty || viewModel.isBulkOperationInProgress
          ? 0.5 : 1
      )
      .help("Deletes Short-term and Long-term memories. Archive remains available.")
    }
    .padding(.vertical, OmiSpacing.xxs)
    .frame(width: 200)
    .background(OmiColors.backgroundSecondary)
  }

  // MARK: - Memory List

  private var memoryList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: OmiSpacing.md) {
        LazyVStack(spacing: OmiSpacing.sm) {
          ForEach(viewModel.filteredMemories) { memory in
            MemoryCardView(
              memory: memory,
              onTap: {
                viewModel.selectedMemory = memory
              },
              categoryIcon: categoryIcon,
              categoryColor: categoryColor,
              tagColorFor: tagColorFor,
              formatDate: formatDate
            )
            .onAppear {
              // Load more when approaching the end of the list
              Task { await viewModel.loadMoreIfNeeded(currentMemory: memory) }
            }
          }
        }

        // Loading more indicator
        if viewModel.isLoadingMore {
          HStack(spacing: OmiSpacing.sm) {
            ProgressView()
              .scaleEffect(0.8)
            Text("Loading more...")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textTertiary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, OmiSpacing.lg)
        }

        // "Load more" button if there are more memories
        if !viewModel.filteredMemories.isEmpty && !viewModel.isLoadingMore {
          if viewModel.isInFilteredMode && viewModel.hasMoreFilteredResults {
            Button {
              viewModel.loadMoreFiltered()
            } label: {
              HStack(spacing: OmiSpacing.xs) {
                Image(systemName: "arrow.down.circle")
                Text("Load more memories")
              }
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(OmiColors.textSecondary)
              .padding(.horizontal, OmiSpacing.lg)
              .padding(.vertical, OmiSpacing.sm)
              .omiControlSurface(fill: OmiColors.backgroundTertiary, radius: 16)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OmiSpacing.sm)
          } else if !viewModel.isInFilteredMode && viewModel.hasMoreMemories {
            Button {
              Task { await viewModel.loadMore() }
            } label: {
              HStack(spacing: OmiSpacing.xs) {
                Image(systemName: "arrow.down.circle")
                Text("Load more memories")
              }
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(OmiColors.textSecondary)
              .padding(.horizontal, OmiSpacing.lg)
              .padding(.vertical, OmiSpacing.sm)
              .omiControlSurface(fill: OmiColors.backgroundTertiary, radius: 16)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OmiSpacing.sm)
          }
        }
      }
      .padding(.horizontal, OmiSpacing.xxl)
      .padding(.bottom, OmiSpacing.xxl)
    }
  }

  private func tagBadge(_ title: String, _ icon: String, _ color: Color) -> some View {
    HStack(spacing: OmiSpacing.xxs) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.micro)
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .medium)
    }
    .foregroundColor(OmiColors.textSecondary)
  }

  private func categoryIcon(_ category: MemoryCategory) -> String {
    category.icon
  }

  private func categoryColor(_ category: MemoryCategory) -> Color {
    OmiColors.textSecondary
  }

  private func tagColorFor(_ tag: String) -> Color {
    return OmiColors.textSecondary
  }

  private func formatDate(_ date: Date) -> String {
    let relativeFormatter = RelativeDateTimeFormatter()
    relativeFormatter.unitsStyle = .abbreviated
    let relativeTime = relativeFormatter.localizedString(for: date, relativeTo: Date())

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MMM d, h:mm a"
    let absoluteTime = dateFormatter.string(from: date)

    return "\(relativeTime) · \(absoluteTime)"
  }

  // MARK: - Empty States

  private var emptyState: some View {
    VStack(spacing: OmiSpacing.lg) {
      Image(systemName: "brain.head.profile")
        .scaledFont(size: 48)
        .foregroundColor(OmiColors.textTertiary)

      Text("No Memories Yet")
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)

      Text(
        "Your memories and tips will appear here.\nMemories are extracted from your conversations."
      )
      .scaledFont(size: OmiType.body)
      .foregroundColor(OmiColors.textTertiary)
      .multilineTextAlignment(.center)

      Button {
        viewModel.showingAddMemory = true
      } label: {
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "plus")
          Text("Add Your First Memory")
        }
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.backgroundPrimary)
        .padding(.horizontal, OmiSpacing.xl)
        .padding(.vertical, OmiSpacing.sm)
        .background(OmiColors.accent)
        .cornerRadius(OmiChrome.elementRadius)
      }
      .buttonStyle(.plain)
      .padding(.top, OmiSpacing.sm)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var noResultsView: some View {
    VStack(spacing: OmiSpacing.md) {
      Image(systemName: "magnifyingglass")
        .scaledFont(size: 36)
        .foregroundColor(OmiColors.textTertiary)

      Text("No Results")
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)

      Text("Try a different search or filter")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textTertiary)

      if !viewModel.selectedTags.isEmpty {
        Button {
          viewModel.selectedTags.removeAll()
        } label: {
          Text("Clear Filters")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textSecondary)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var loadingView: some View {
    VStack(spacing: OmiSpacing.md) {
      ProgressView()
        .progressViewStyle(.circular)
        .scaleEffect(1.2)

      Text("Loading memories...")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textTertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorView(_ error: String) -> some View {
    VStack(spacing: OmiSpacing.lg) {
      Image(systemName: "exclamationmark.triangle")
        .scaledFont(size: 36)
        .foregroundColor(OmiColors.error)

      Text("Failed to Load Memories")
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)

      Text(error)
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textTertiary)

      Button {
        Task { await viewModel.loadMemories() }
      } label: {
        HStack(spacing: OmiSpacing.xs) {
          Image(systemName: "arrow.clockwise")
          Text("Retry")
        }
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.backgroundPrimary)
        .padding(.horizontal, OmiSpacing.xl)
        .padding(.vertical, OmiSpacing.sm)
        .background(OmiColors.accent)
        .cornerRadius(OmiChrome.elementRadius)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Sheets

}

// MARK: - Memory Card View

private struct MemoryLayerBadge: View {
  let layer: MemoryLayer
  @State private var showLayerInfo = false

  var body: some View {
    Button {
      showLayerInfo.toggle()
    } label: {
      HStack(spacing: OmiSpacing.xxs) {
        Image(systemName: layer.icon)
          .scaledFont(size: OmiType.micro, weight: .medium)
        Text(layer.displayName)
          .scaledFont(size: OmiType.micro, weight: .medium)
      }
      .foregroundColor(layer == .archive ? OmiColors.textPrimary : OmiColors.textSecondary)
      .padding(.horizontal, OmiSpacing.xs)
      .padding(.vertical, OmiSpacing.hairline)
      .background(layer == .archive ? OmiColors.backgroundRaised : OmiColors.backgroundTertiary)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(layer.layerInfoText)
    .popover(isPresented: $showLayerInfo, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: OmiSpacing.xs) {
        Text(layer.displayName)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Text(layer.layerInfoText)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(OmiSpacing.md)
      .frame(maxWidth: 240)
    }
  }
}

private struct MemoryCardView: View {
  let memory: MemoryItem
  let onTap: () -> Void
  let categoryIcon: (MemoryCategory) -> String
  let categoryColor: (MemoryCategory) -> Color
  let tagColorFor: (String) -> Color
  let formatDate: (Date) -> String

  @State private var isHovered = false

  /// Check if memory was created less than 1 minute ago (newly added)
  private var isNewlyCreated: Bool {
    Date().timeIntervalSince(memory.createdAt) < 60
  }

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack(alignment: .top, spacing: OmiSpacing.sm) {
          Text(memory.content)
            .foregroundColor(OmiColors.textPrimary)
            .scaledFont(size: 13.5)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)

          if isNewlyCreated {
            NewBadge()
          }
        }

        HStack(spacing: OmiSpacing.sm) {
          Text(formatDate(memory.createdAt))
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textSecondary)

          MemoryLayerBadge(layer: memory.layer)

          if let sourceName = memory.sourceName {
            Text("From \(sourceName)")
              .scaledFont(size: OmiType.micro)
              .foregroundColor(OmiColors.textTertiary)
              .lineLimit(1)
          }

          Spacer(minLength: 4)

          MemoryDetailButton(
            memory: memory,
            categoryIcon: categoryIcon,
            categoryColor: categoryColor,
            tagColorFor: tagColorFor
          )

          if isHovered {
            Image(systemName: "arrow.up.right")
              .scaledFont(size: OmiType.micro, weight: .medium)
              .foregroundColor(OmiColors.textTertiary)
          }
        }
      }
      .padding(.horizontal, OmiSpacing.lg)
      .padding(.vertical, OmiSpacing.md)
      .background(
        isHovered
          ? OmiColors.backgroundRaised
          : (isNewlyCreated ? OmiColors.userBubble.opacity(0.24) : OmiColors.backgroundSecondary)
      )
      .clipShape(RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous))
      .shadow(
        color: .black.opacity(isHovered ? 0.14 : 0.08), radius: isHovered ? 12 : 8, x: 0,
        y: isHovered ? 8 : 5)
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .onHover { hovering in
      // No animation wrapper - simple state update for instant response
      isHovered = hovering
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
  }
}

// MARK: - Memory Detail Button (info icon with hover popover)

/// Small inline info button with hover preview showing memory metadata.
/// Follows the same pattern as TaskDetailButton in TaskDetailViews.swift.
private struct MemoryDetailButton: View {
  let memory: MemoryItem
  let categoryIcon: (MemoryCategory) -> String
  let categoryColor: (MemoryCategory) -> Color
  let tagColorFor: (String) -> Color

  @State private var showTooltip = false
  @State private var isButtonHovered = false
  @State private var isPopoverHovered = false
  @State private var dismissWork: DispatchWorkItem?

  var body: some View {
    Image(systemName: "info.circle")
      .scaledFont(size: OmiType.micro)
      .foregroundColor(showTooltip ? OmiColors.textSecondary : OmiColors.textTertiary)
      .frame(width: 20, height: 20)
      .contentShape(Rectangle())
      .onHover { hovering in
        isButtonHovered = hovering
        scheduleHoverUpdate()
      }
      .popover(isPresented: $showTooltip, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
        MemoryDetailTooltip(
          memory: memory,
          categoryIcon: categoryIcon,
          categoryColor: categoryColor,
          tagColorFor: tagColorFor
        )
        .onHover { hovering in
          isPopoverHovered = hovering
          scheduleHoverUpdate()
        }
      }
  }

  private func scheduleHoverUpdate() {
    dismissWork?.cancel()
    if isButtonHovered || isPopoverHovered {
      showTooltip = true
    } else {
      let work = DispatchWorkItem { showTooltip = false }
      dismissWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
  }
}

// MARK: - Memory Detail Tooltip

/// Compact hover preview showing memory metadata (category, tags, source, etc.)
private struct MemoryDetailTooltip: View {
  let memory: MemoryItem
  let categoryIcon: (MemoryCategory) -> String
  let categoryColor: (MemoryCategory) -> Color
  let tagColorFor: (String) -> Color

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xs) {
      if memory.layer == .shortTerm, let expiresAt = memory.expiresAt {
        tooltipRow("Layer", memory.layer.displayName)
        tooltipRow("Expires", expiresAt.formatted(date: .abbreviated, time: .shortened))
      } else {
        tooltipRow("Layer", memory.layer.displayName)
      }

      // Category
      if memory.isTip {
        tooltipRow("Category", "Tips")
        if let tipCat = memory.tipCategory {
          tooltipRow("Subcategory", tipCat.capitalized)
        }
      } else {
        tooltipRow("Category", memory.category.displayName)
      }

      // Tags
      let displayTags = memory.tags.filter { tag in
        let lower = tag.lowercased()
        if lower == memory.category.rawValue { return false }
        if lower == "tips" || lower == (memory.tipCategory ?? "") { return false }
        if lower == "has-message" { return false }
        return true
      }
      if !displayTags.isEmpty {
        tooltipRow("Tags", displayTags.joined(separator: ", "))
      }

      // Source
      if let sourceApp = memory.sourceApp {
        tooltipRow("App", sourceApp)
      }
      if let sourceName = memory.sourceName {
        tooltipRow("Source", sourceName)
      }
      if let window = memory.windowTitle {
        tooltipRow("Window", window)
      }

      // Context
      if let ctx = memory.contextSummary, !ctx.isEmpty {
        tooltipBlock("Context", ctx)
      }
      if let activity = memory.currentActivity, !activity.isEmpty {
        tooltipBlock("Activity", activity)
      }

      // Confidence
      if let conf = memory.confidenceString {
        tooltipRow("Confidence", conf)
      }

      if memory.isTip, let reasoning = memory.reasoning, !reasoning.isEmpty {
        tooltipBlock("Why this tip", reasoning)
      }

      // Created date
      tooltipRow(
        "Created",
        {
          let f = DateFormatter()
          f.dateStyle = .medium
          f.timeStyle = .short
          return f.string(from: memory.createdAt)
        }())
    }
    .padding(OmiSpacing.sm)
    .frame(maxWidth: 350, maxHeight: 400)
  }

  private func tooltipRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: OmiSpacing.xs) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.textTertiary)
        .frame(width: 70, alignment: .trailing)

      Text(value)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textPrimary)
    }
  }

  private func tooltipBlock(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.textTertiary)
        .padding(.leading, 76)

      Text(value)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textPrimary)
        .padding(.leading, 76)
        .lineLimit(3)
    }
  }
}

// MARK: - Memory Detail Panel

/// Right-hand inspector for one memory.
///
/// Deliberately unsized: it fills whatever column the Memories page gives it.
/// The earlier version was a modal sheet pinned to 450×600, and reusing it as
/// a panel meant its content laid out at 450pt inside a 360pt column and was
/// clipped mid-word, while its 600pt background stopped short of the window.
///
struct MemoryDetailPanel: View {
  let memory: MemoryItem
  @ObservedObject var viewModel: MemoriesViewModel
  let categoryIcon: (MemoryCategory) -> String
  let categoryColor: (MemoryCategory) -> Color
  let tagColorFor: (String) -> Color
  let formatDate: (Date) -> String
  var onDismiss: (() -> Void)? = nil

  @Environment(\.dismiss) private var environmentDismiss
  @State private var isEditingContent = false
  @State private var editContentText = ""

  private func dismissSheet() {
    if let onDismiss = onDismiss {
      onDismiss()
    } else {
      environmentDismiss()
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider().overlay(OmiColors.border.opacity(0.2))

      ScrollView {
        VStack(alignment: .leading, spacing: OmiSpacing.xl) {
          content

          provenance

          if !displayTags.isEmpty {
            section("Tags") {
              FlowLayout(spacing: OmiSpacing.xxs) {
                ForEach(displayTags, id: \.self) { tag in
                  chip(tag, icon: nil, tint: tagColorFor(tag))
                }
              }
            }
          }

          if memory.isTip, let reasoning = memory.reasoning, !reasoning.isEmpty {
            section("Why this tip") {
              Text(reasoning)
                .scaledFont(size: OmiType.body)
                .foregroundColor(OmiColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
          }

          if hasContext {
            section("Context") {
              VStack(alignment: .leading, spacing: OmiSpacing.xs) {
                if let activity = memory.currentActivity, !activity.isEmpty {
                  contextLine("figure.walk", activity)
                }
                if let window = memory.windowTitle, !window.isEmpty {
                  contextLine("macwindow", window)
                }
                if let summary = memory.contextSummary, !summary.isEmpty {
                  Text(summary)
                    .scaledFont(size: OmiType.body)
                    .foregroundColor(OmiColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
              }
            }
          }

          if let conversationId = memory.conversationId {
            MemoryActionRow(
              icon: "bubble.left.and.bubble.right",
              title: "View Source Conversation",
              iconColor: OmiColors.textPrimary,
              textColor: OmiColors.textPrimary,
              backgroundColor: OmiColors.backgroundTertiary,
              trailingIcon: "arrow.up.right"
            ) {
              NSApp.keyWindow?.makeFirstResponder(nil)
              Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                dismissSheet()
                await viewModel.navigateToConversation(id: conversationId)
              }
            }
          }
        }
        .padding(OmiSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityIdentifier("memory_detail_panel_body")
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: OmiSpacing.sm) {
      if memory.isTip {
        chip("Tips", icon: "lightbulb.fill", tint: OmiColors.textSecondary)
        if let tipCategory = memory.tipCategory {
          chip(
            tipCategory.capitalized, icon: memory.tipCategoryIcon, tint: tagColorFor(tipCategory))
        }
      } else {
        chip(
          memory.category.displayName,
          icon: categoryIcon(memory.category),
          tint: categoryColor(memory.category)
        )
      }

      Spacer(minLength: OmiSpacing.xs)

      Menu {
        Button("Edit text") {
          editContentText = memory.content
          isEditingContent = true
        }
        Divider()
        Button("Delete memory", role: .destructive) {
          NSApp.keyWindow?.makeFirstResponder(nil)
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            dismissSheet()
            await viewModel.deleteMemory(memory)
          }
        }
      } label: {
        Image(systemName: "ellipsis")
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textSecondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .frame(width: 24)
      .help("More actions")
      .accessibilityIdentifier("memory_detail_actions_menu")

      DismissButton(action: dismissSheet)
    }
    .padding(.horizontal, OmiSpacing.lg)
    .padding(.vertical, OmiSpacing.md)
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    if isEditingContent {
      VStack(alignment: .trailing, spacing: OmiSpacing.sm) {
        // Memories run to a full paragraph, and the panel is a tall column
        // with room to spare. An 80pt box showed roughly three lines of a
        // twelve-line memory and made editing a scroll-and-hunt exercise.
        TextEditor(text: $editContentText)
          .scaledFont(size: OmiType.subheading)
          .foregroundColor(OmiColors.textPrimary)
          .scrollContentBackground(.hidden)
          .padding(OmiSpacing.sm)
          .background(OmiColors.backgroundTertiary)
          .cornerRadius(OmiChrome.elementRadius)
          .frame(minHeight: 260)

        HStack(spacing: OmiSpacing.sm) {
          Button {
            isEditingContent = false
          } label: {
            Text("Cancel")
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
          }
          .buttonStyle(.plain)

          Button {
            viewModel.editText = editContentText
            Task {
              await viewModel.saveEditedMemory(memory)
              isEditingContent = false
            }
          } label: {
            Text("Save")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(.black)
              .padding(.horizontal, OmiSpacing.md)
              .padding(.vertical, OmiSpacing.xxs)
              .background(Color.white)
              .cornerRadius(OmiChrome.badgeRadius)
          }
          .buttonStyle(.plain)
          .disabled(editContentText.isEmpty)
        }
      }
    } else {
      Text(memory.content)
        .scaledFont(size: OmiType.subheading)
        .foregroundColor(OmiColors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
          editContentText = memory.content
          isEditingContent = true
        }
        .help("Click to edit")
    }
  }

  // MARK: Provenance

  /// Where a memory came from, as chips rather than a label/value table.
  ///
  /// The table version put every value on its own right-aligned row, so
  /// answering "where did this come from" meant reading five rows and the
  /// longest values were the ones that got truncated. Chips wrap, stay on the
  /// left margin, and read in one pass.
  private var provenance: some View {
    section("Where this came from") {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        if !provenanceFacts.isEmpty {
          FlowLayout(spacing: OmiSpacing.xxs) {
            ForEach(provenanceFacts) { fact in
              chip(fact.label, icon: fact.icon, tint: OmiColors.textSecondary)
            }
          }
        }

        HStack(spacing: OmiSpacing.xxs) {
          Image(systemName: "clock")
            .scaledFont(size: OmiType.micro)
          Text(formatDate(memory.createdAt))
            .scaledFont(size: OmiType.caption)
        }
        .foregroundColor(OmiColors.textTertiary)
      }
      .accessibilityIdentifier("memory_detail_provenance")
    }
  }

  private var provenanceFacts: [MemoryProvenanceFact] {
    MemoryProvenance.facts(for: memory)
  }

  private var hasContext: Bool {
    let values = [memory.currentActivity, memory.contextSummary, memory.windowTitle]
    return values.contains { ($0?.isEmpty == false) }
  }

  /// Tags already shown as the header chip would repeat themselves here.
  private var displayTags: [String] {
    memory.tags.filter { tag in
      let lower = tag.lowercased()
      if lower == memory.category.rawValue { return false }
      if lower == "tips" || lower == (memory.tipCategory ?? "") { return false }
      if lower == "has-message" { return false }
      // The app now reads as a provenance chip, so leaving `app:Codex` in the
      // tag row would say the same thing twice in a rawer form.
      if tag.hasPrefix(MemoryProvenance.appTagPrefix) { return false }
      return true
    }
  }

  // MARK: Building blocks

  @ViewBuilder
  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      Text(title.uppercased())
        .scaledFont(size: OmiType.micro, weight: .semibold)
        .foregroundColor(OmiColors.textQuaternary)
        .tracking(0.6)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func chip(_ title: String, icon: String?, tint: Color) -> some View {
    HStack(spacing: OmiSpacing.xxs) {
      if let icon {
        Image(systemName: icon)
          .scaledFont(size: OmiType.micro)
      }
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .lineLimit(1)
    }
    .foregroundColor(tint)
    .padding(.horizontal, OmiSpacing.xs)
    .padding(.vertical, 3)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.badgeRadius, style: .continuous)
        .fill(OmiColors.backgroundTertiary)
    )
  }

  private func contextLine(_ icon: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: OmiSpacing.xxs) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.micro)
        .padding(.top, 2)
      Text(text)
        .scaledFont(size: OmiType.body)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .foregroundColor(OmiColors.textTertiary)
  }
}

// MARK: - Memory Action Row
/// A row button that prevents click-through when tapped, using the same pattern as SafeDismissButton.
/// Sends a synthetic mouse-up event before executing the action.
private struct MemoryActionRow: View {
  let icon: String
  let title: String
  let iconColor: Color
  let textColor: Color
  let backgroundColor: Color
  var trailingIcon: String? = nil
  let action: () -> Void

  @State private var isPressed = false

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(iconColor)
      Text(title)
      Spacer()
      if let trailing = trailingIcon {
        Image(systemName: trailing)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
      }
    }
    .scaledFont(size: OmiType.body)
    .foregroundColor(textColor)
    .padding(OmiSpacing.md)
    .background(backgroundColor)
    .cornerRadius(OmiChrome.elementRadius)
    .opacity(isPressed ? 0.7 : 1.0)
    .contentShape(Rectangle())
    .onTapGesture {
      guard !isPressed else { return }  // Prevent double-tap
      isPressed = true

      log("MEMORY ACTION: \(title) tapped at mouse position: \(NSEvent.mouseLocation)")

      // Consume the click by resigning first responder
      NSApp.keyWindow?.makeFirstResponder(nil)

      // Post a mouse-up event to ensure any pending click is consumed
      if let window = NSApp.keyWindow {
        let event = NSEvent.mouseEvent(
          with: .leftMouseUp,
          location: window.mouseLocationOutsideOfEventStream,
          modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber,
          context: nil,
          eventNumber: 0,
          clickCount: 1,
          pressure: 0
        )
        if let event = event {
          window.sendEvent(event)
          log("MEMORY ACTION: Sent synthetic mouse-up event for \(title)")
        }
      }

      // Execute the action (which should handle its own delays for dismiss)
      action()
    }
  }
}

// MARK: - Add Memory Sheet

struct AddMemorySheet: View {
  @ObservedObject var viewModel: MemoriesViewModel
  var onDismiss: (() -> Void)? = nil

  @Environment(\.dismiss) private var environmentDismiss

  private func dismissSheet() {
    viewModel.newMemoryText = ""
    if let onDismiss = onDismiss {
      onDismiss()
    } else {
      environmentDismiss()
    }
  }

  var body: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Header with close button
      HStack {
        Text("Add Memory")
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        DismissButton(action: dismissSheet)
      }

      TextEditor(text: $viewModel.newMemoryText)
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textPrimary)
        .scrollContentBackground(.hidden)
        .padding(OmiSpacing.md)
        .background(OmiColors.backgroundTertiary)
        .cornerRadius(OmiChrome.elementRadius)
        .frame(height: 150)

      HStack(spacing: OmiSpacing.md) {
        // Cancel button
        Button(action: dismissSheet) {
          Text("Cancel")
            .foregroundColor(OmiColors.textSecondary)
        }

        Spacer()

        Button {
          Task { await viewModel.createMemory() }
        } label: {
          Text("Save")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(viewModel.newMemoryText.isEmpty ? OmiColors.textTertiary : .black)
            .padding(.horizontal, OmiSpacing.xl)
            .padding(.vertical, OmiSpacing.sm)
            .background(
              viewModel.newMemoryText.isEmpty ? OmiColors.backgroundTertiary : Color.white
            )
            .cornerRadius(OmiChrome.elementRadius)
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                .stroke(
                  viewModel.newMemoryText.isEmpty ? Color.clear : OmiColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.newMemoryText.isEmpty)
      }
    }
    .padding(OmiSpacing.xxl)
    .frame(width: 400)
    .background(OmiColors.backgroundSecondary)
  }
}

// MARK: - Edit Memory Sheet

struct EditMemorySheet: View {
  let memory: MemoryItem
  @ObservedObject var viewModel: MemoriesViewModel
  var onDismiss: (() -> Void)? = nil

  @Environment(\.dismiss) private var environmentDismiss

  private func dismissSheet() {
    viewModel.editText = ""
    if let onDismiss = onDismiss {
      onDismiss()
    } else {
      environmentDismiss()
    }
  }

  var body: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Header with close button
      HStack {
        Text("Edit Memory")
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        DismissButton(action: dismissSheet)
      }

      TextEditor(text: $viewModel.editText)
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textPrimary)
        .scrollContentBackground(.hidden)
        .padding(OmiSpacing.md)
        .background(OmiColors.backgroundTertiary)
        .cornerRadius(OmiChrome.elementRadius)
        .frame(height: 150)

      HStack(spacing: OmiSpacing.md) {
        // Cancel button
        Button(action: dismissSheet) {
          Text("Cancel")
            .foregroundColor(OmiColors.textSecondary)
        }

        Spacer()

        Button {
          Task { await viewModel.saveEditedMemory(memory) }
        } label: {
          Text("Save")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(viewModel.editText.isEmpty ? OmiColors.textTertiary : .black)
            .padding(.horizontal, OmiSpacing.xl)
            .padding(.vertical, OmiSpacing.sm)
            .background(viewModel.editText.isEmpty ? OmiColors.backgroundTertiary : Color.white)
            .cornerRadius(OmiChrome.elementRadius)
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                .stroke(viewModel.editText.isEmpty ? Color.clear : OmiColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.editText.isEmpty)
      }
    }
    .padding(OmiSpacing.xxl)
    .frame(width: 400)
    .background(OmiColors.backgroundSecondary)
  }
}
