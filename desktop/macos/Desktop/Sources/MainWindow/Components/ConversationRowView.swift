import AppKit
import OmiTheme
import SwiftUI

/// Row view for a conversation in the list
struct ConversationRowView: View {
  let conversation: LocalConversation
  let onTap: () -> Void
  let folders: [Folder]
  let onMoveToFolder: (String, String?) async -> Void

  // Multi-select support
  var isMultiSelectMode: Bool = false
  var isSelected: Bool = false
  var onToggleSelection: (() -> Void)? = nil

  var appState: AppState
  @State private var isStarring = false
  @State private var isHovering = false

  // Context menu action states
  @State private var showEditDialog = false
  @State private var showDeleteConfirmation = false
  @State private var editedTitle: String = ""
  @State private var isDeleting = false
  @State private var isUpdatingTitle = false

  /// The timestamp to display (prefer startedAt, fall back to createdAt)
  private var displayDate: Date {
    conversation.startedAt
  }

  /// Check if conversation was created less than 1 minute ago (newly added)
  private var isNewlyCreated: Bool {
    Date().timeIntervalSince(conversation.createdAt) < 60
  }

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
  }()
  private static let yesterdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "'Yesterday,' h:mm a"
    return f
  }()
  private static let sameYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, h:mm a"
    return f
  }()
  private static let otherYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy, h:mm a"
    return f
  }()

  /// Format timestamp (e.g., "10:43 AM" for today, "Jan 29, 10:43 AM" for other days)
  private var formattedTimestamp: String {
    let calendar = Calendar.current
    let formatter: DateFormatter

    if calendar.isDateInToday(displayDate) {
      formatter = Self.timeFormatter
    } else if calendar.isDateInYesterday(displayDate) {
      formatter = Self.yesterdayFormatter
    } else if calendar.isDate(displayDate, equalTo: Date(), toGranularity: .year) {
      formatter = Self.sameYearFormatter
    } else {
      formatter = Self.otherYearFormatter
    }

    return formatter.string(from: displayDate)
  }

  /// Folder name for inline display
  private var folderName: String? {
    guard let folderId = conversation.folderId else { return nil }
    return folders.first(where: { $0.id == folderId })?.name
  }

  private func toggleStar() async {
    guard !isStarring else { return }
    isStarring = true
    let newStarred = !conversation.starred

    await appState.setConversationStarred(conversation.id, starred: newStarred)

    isStarring = false
  }

  // MARK: - Context Menu Actions

  private func copyTranscript() {
    Task { @MainActor in
      do {
        let transcript = try await appState.conversationRepository.transcriptForCopy(
          id: conversation.id)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        log("Copied transcript to clipboard")
      } catch {
        logError("Failed to load local transcript for copying", error: error)
      }
    }
  }

  private func deleteConversation() async {
    guard !isDeleting else { return }
    isDeleting = true

    if await appState.deleteConversation(conversation.id) {
      log("Deleted conversation \(conversation.id)")
    }

    isDeleting = false
  }

  private func updateTitle() async {
    guard !isUpdatingTitle, !editedTitle.isEmpty else { return }
    isUpdatingTitle = true

    if await appState.updateConversationTitle(conversation.id, title: editedTitle) {
      log("Updated conversation title to: \(editedTitle)")
    }

    isUpdatingTitle = false
  }

  // MARK: - Inline Action Buttons

  private var inlineActionButtons: some View {
    HStack(spacing: OmiSpacing.xxs) {
      // Edit title
      Button(action: {
        editedTitle = conversation.title
        showEditDialog = true
      }) {
        Image(systemName: "pencil")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.textTertiary)
          .frame(width: 22, height: 22)
          .background(Circle().fill(OmiColors.backgroundRaised))
      }
      .buttonStyle(.plain)
      .help("Edit title")

      // Move to folder (if folders exist)
      if !folders.isEmpty {
        Menu {
          if conversation.folderId != nil {
            Button(action: { Task { await onMoveToFolder(conversation.id, nil) } }) {
              Label("Remove from Folder", systemImage: "folder.badge.minus")
            }
            Divider()
          }
          ForEach(folders) { folder in
            Button(action: { Task { await onMoveToFolder(conversation.id, folder.id) } }) {
              HStack {
                Text(folder.name)
                if conversation.folderId == folder.id {
                  Image(systemName: "checkmark")
                }
              }
            }
            .disabled(conversation.folderId == folder.id)
          }
        } label: {
          Image(systemName: conversation.folderId != nil ? "folder.fill" : "folder")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(conversation.folderId != nil ? .white : OmiColors.textTertiary)
            .frame(width: 22, height: 22)
            .background(Circle().fill(OmiColors.backgroundRaised))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 22)
        .help("Move to folder")
      }

      // Delete
      Button(action: { showDeleteConfirmation = true }) {
        Image(systemName: "trash")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(OmiColors.error.opacity(0.8))
          .frame(width: 22, height: 22)
          .background(Circle().fill(OmiColors.backgroundRaised))
      }
      .buttonStyle(.plain)
      .help("Delete")
    }
  }

  // MARK: - Compact Row (single line)

  private var compactRowContent: some View {
    HStack(spacing: OmiSpacing.sm) {
      // Checkbox for multi-select mode
      if isMultiSelectMode {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .scaledFont(size: OmiType.heading)
          .foregroundColor(isSelected ? OmiColors.accent : OmiColors.textTertiary)
      }

      // Emoji
      Text(conversation.structured.emoji.isEmpty ? "💬" : conversation.structured.emoji)
        .scaledFont(size: OmiType.subheading)
        .frame(width: 36, height: 36)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous).fill(
            OmiColors.backgroundRaised))

      // Title + metadata below
      VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
        HStack(spacing: OmiSpacing.sm) {
          Text(conversation.title)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)
            .lineLimit(1)

          if isNewlyCreated {
            NewBadge()
          }

          // Inline action buttons (show on hover)
          if isHovering && !isMultiSelectMode {
            inlineActionButtons
              .transition(.opacity)
          }
        }

        HStack(spacing: OmiSpacing.xs) {
          Text(formattedTimestamp)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)

          Text("·")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textQuaternary)

          Text(conversation.formattedDuration)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textTertiary)
        }
      }

      Spacer()

      // Star button
      Button(action: {
        Task { await toggleStar() }
      }) {
        Image(systemName: conversation.starred ? "star.fill" : "star")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(conversation.starred ? OmiColors.amber : OmiColors.textTertiary)
          .opacity(isStarring ? 0.5 : 1.0)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
        .fill(
          isSelected
            ? OmiColors.accent.opacity(0.22)
            : (isHovering
              ? OmiColors.backgroundRaised
              : (isNewlyCreated
                ? OmiColors.userBubble.opacity(0.18) : OmiColors.backgroundSecondary))
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
        .stroke(
          isSelected ? OmiColors.accent.opacity(0.4) : OmiColors.border.opacity(0.14),
          lineWidth: 1)
    )
    .contentShape(Rectangle())
  }

  var body: some View {
    Button(action: {
      if isMultiSelectMode {
        onToggleSelection?()
      } else {
        onTap()
      }
    }) {
      compactRowContent
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
    }
    .contextMenu {
      Button(action: copyTranscript) {
        Label("Copy Transcript", systemImage: "doc.on.doc")
      }

      Button(action: {
        editedTitle = conversation.title
        showEditDialog = true
      }) {
        Label("Edit Title", systemImage: "pencil")
      }

      // Move to Folder submenu
      if !folders.isEmpty {
        Menu {
          // Option to remove from folder
          if conversation.folderId != nil {
            Button(action: {
              Task {
                await onMoveToFolder(conversation.id, nil)
              }
            }) {
              Label("Remove from Folder", systemImage: "folder.badge.minus")
            }
            Divider()
          }

          // List available folders
          ForEach(folders) { folder in
            Button(action: {
              Task {
                await onMoveToFolder(conversation.id, folder.id)
              }
            }) {
              HStack {
                Text(folder.name)
                if conversation.folderId == folder.id {
                  Image(systemName: "checkmark")
                }
              }
            }
            .disabled(conversation.folderId == folder.id)
          }
        } label: {
          Label("Move to Folder", systemImage: "folder")
        }
      }

      Divider()

      Button(
        role: .destructive,
        action: {
          showDeleteConfirmation = true
        }
      ) {
        Label("Delete", systemImage: "trash")
      }
    }
    .alert("Edit Conversation Title", isPresented: $showEditDialog) {
      TextField("Title", text: $editedTitle)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        Task {
          await updateTitle()
        }
      }
      .disabled(editedTitle.isEmpty || isUpdatingTitle)
    } message: {
      Text("Enter a new title for this conversation")
    }
    .alert("Delete Conversation", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task {
          await deleteConversation()
        }
      }
    } message: {
      Text("Are you sure you want to delete this conversation? This action cannot be undone.")
    }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    VStack(spacing: OmiSpacing.md) {
      // Preview would require mock LocalConversation
      Text("ConversationRowView Preview")
        .foregroundColor(.white)
    }
    .padding()
    .background(OmiColors.backgroundPrimary)
  }
#endif
