import OmiTheme
import SwiftUI

/// Small info button with a pointer-transfer-safe hover preview and a fixed,
/// scrolling detail sheet. Only explicitly retained task fields are rendered.
struct TaskDetailButton: View {
  let task: TaskActionItem
  @Binding var showDetail: Bool
  @State private var showTooltip = false
  @State private var buttonHovered = false
  @State private var popoverHovered = false
  @State private var dismissWork: DispatchWorkItem?

  var body: some View {
    Button {
      dismissWork?.cancel()
      showTooltip = false
      showDetail = true
    } label: {
      Image(systemName: "info.circle")
        .scaledFont(size: OmiType.micro)
        .foregroundColor(showTooltip ? OmiColors.textSecondary : OmiColors.textTertiary)
    }
    .buttonStyle(.plain)
    .onHover { hovered in
      buttonHovered = hovered
      updateTooltip()
    }
    .popover(isPresented: $showTooltip, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
      TaskDetailTooltip(task: task)
        .onHover { hovered in
          popoverHovered = hovered
          updateTooltip()
        }
    }
  }

  private func updateTooltip() {
    dismissWork?.cancel()
    if buttonHovered || popoverHovered {
      showTooltip = true
    } else {
      let work = DispatchWorkItem { showTooltip = false }
      dismissWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
  }
}

private struct TaskDetailTooltip: View {
  let task: TaskActionItem

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: OmiSpacing.xs) {
        detail("Status", task.completed ? "Completed" : "Active")
        if let priority = task.priority { detail("Priority", priority.capitalized) }
        if let dueAt = task.dueAt { detail("Due", Self.date(dueAt)) }
        if let recurrence = task.recurrenceRule { detail("Repeats", Self.recurrence(recurrence)) }
        detail("Created", Self.date(task.createdAt))
        if let source = task.source { detail("Source", task.sourceLabel + " (" + source + ")") }
        if let sourceApp = task.sourceApp { detail("App", sourceApp) }
        if let windowTitle = task.windowTitle { detail("Window", windowTitle) }
        if let context = task.contextSummary, !context.isEmpty { block("Context", context) }
        if let activity = task.currentActivity, !activity.isEmpty { block("Activity", activity) }
        if let confidence = task.confidence { detail("Confidence", "\(Int(confidence * 100))%") }
        let sourceCount = (task.provenance ?? []).count
        if sourceCount > 0 { detail("Evidence", "\(sourceCount) linked source\(sourceCount == 1 ? "" : "s")") }
      }
      .padding(OmiSpacing.sm)
    }
    .frame(maxWidth: 350, maxHeight: 400)
  }

  private func detail(_ label: String, _ value: String) -> some View {
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

  private func block(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.textTertiary)
      Text(value)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textPrimary)
    }
  }

  fileprivate static func date(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  fileprivate static func recurrence(_ value: String) -> String {
    switch value {
    case "daily": return "Daily"
    case "weekdays": return "Weekdays"
    case "weekly": return "Weekly"
    case "biweekly": return "Every 2 Weeks"
    case "monthly": return "Monthly"
    default: return value.capitalized
    }
  }
}

struct TaskDetailView: View {
  let task: TaskActionItem
  var onDismiss: (() -> Void)?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Task Details")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        DismissButton { onDismiss?() ?? dismiss() }
      }
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.vertical, OmiSpacing.lg)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: OmiSpacing.xl) {
          section("Task") {
            Text(task.description)
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textPrimary)
              .textSelection(.enabled)
          }

          section("Details") {
            detail("Status", task.completed ? "Completed" : "Active")
            if let priority = task.priority { detail("Priority", priority.capitalized) }
            detail("Created", TaskDetailTooltip.date(task.createdAt))
            if let dueAt = task.dueAt { detail("Due", TaskDetailTooltip.date(dueAt)) }
            if let completedAt = task.completedAt { detail("Completed", TaskDetailTooltip.date(completedAt)) }
            if let recurrence = task.recurrenceRule {
              detail("Repeats", TaskDetailTooltip.recurrence(recurrence))
            }
          }

          if task.source != nil || task.sourceApp != nil || task.windowTitle != nil || task.confidence != nil {
            section("Source") {
              if let source = task.source { detail("Type", task.sourceLabel + " (" + source + ")") }
              if let sourceApp = task.sourceApp { detail("App", sourceApp) }
              if let windowTitle = task.windowTitle { detail("Window", windowTitle) }
              if let confidence = task.confidence { detail("Confidence", "\(Int(confidence * 100))%") }
              let count = (task.provenance ?? []).count
              if count > 0 { detail("Evidence", "\(count) linked source\(count == 1 ? "" : "s")") }
            }
          }

          if task.contextSummary != nil || task.currentActivity != nil {
            section("Context") {
              if let context = task.contextSummary, !context.isEmpty { block("Summary", context) }
              if let activity = task.currentActivity, !activity.isEmpty { block("Activity", activity) }
            }
          }
        }
        .padding(OmiSpacing.xl)
      }
    }
    .frame(width: 550, height: 600)
    .background(OmiColors.backgroundPrimary)
  }

  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      Text(title)
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundColor(OmiColors.textSecondary)
      VStack(alignment: .leading, spacing: OmiSpacing.xs) { content() }
        .padding(OmiSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
            .fill(OmiColors.backgroundSecondary)
        )
    }
  }

  private func detail(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)
        .frame(width: 100, alignment: .leading)
      Text(value)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textPrimary)
        .textSelection(.enabled)
    }
  }

  private func block(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      Text(label)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)
      Text(value)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(OmiColors.textPrimary)
        .textSelection(.enabled)
    }
  }
}
