import OmiTheme
import SwiftUI

struct GoalsWidget: View {
  let goals: [LocalGoal]
  let onCreateGoal: (String, String?) -> Void
  let onUpdateGoal: (LocalGoal, String, String?) -> Void
  let onToggleCompletion: (LocalGoal) -> Void

  @State private var editingGoal: LocalGoal?
  @State private var showingCreateSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      HStack {
        Text("Goals")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        Button {
          showingCreateSheet = true
        } label: {
          Image(systemName: "plus")
            .foregroundColor(OmiColors.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Add goal")
      }

      if goals.isEmpty {
        VStack(spacing: OmiSpacing.sm) {
          Image(systemName: "target")
            .scaledFont(size: OmiType.title)
            .foregroundColor(OmiColors.textQuaternary)
          Text("No active goals")
            .scaledFont(size: OmiType.body)
            .foregroundColor(OmiColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: OmiSpacing.sm) {
          ForEach(goals) { goal in
            HStack(alignment: .top, spacing: OmiSpacing.md) {
              Button {
                onToggleCompletion(goal)
              } label: {
                Image(systemName: "circle")
                  .scaledFont(size: OmiType.heading)
                  .foregroundColor(OmiColors.textTertiary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Complete \(goal.title)")

              Button {
                editingGoal = goal
              } label: {
                VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
                  Text(goal.title)
                    .scaledFont(size: OmiType.body, weight: .medium)
                    .foregroundColor(OmiColors.textPrimary)
                    .lineLimit(2)
                  if let description = goal.description, !description.isEmpty {
                    Text(description)
                      .scaledFont(size: OmiType.caption)
                      .foregroundColor(OmiColors.textTertiary)
                      .lineLimit(2)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
            }
            .padding(.vertical, OmiSpacing.sm)
            .padding(.horizontal, OmiSpacing.md)
            .background(
              RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
                .fill(OmiColors.backgroundTertiary.opacity(0.45))
            )
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(OmiSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .omiPanel(fill: OmiColors.backgroundSecondary)
    .sheet(isPresented: $showingCreateSheet) {
      LocalGoalEditSheet(
        title: "New Goal",
        initialTitle: "",
        initialDescription: nil,
        onSave: onCreateGoal
      )
    }
    .sheet(item: $editingGoal) { goal in
      LocalGoalEditSheet(
        title: "Edit Goal",
        initialTitle: goal.title,
        initialDescription: goal.description,
        onSave: { title, description in
          onUpdateGoal(goal, title, description)
        }
      )
    }
  }
}

private struct LocalGoalEditSheet: View {
  let title: String
  let initialTitle: String
  let initialDescription: String?
  let onSave: (String, String?) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var goalTitle: String
  @State private var goalDescription: String

  init(
    title: String,
    initialTitle: String,
    initialDescription: String?,
    onSave: @escaping (String, String?) -> Void
  ) {
    self.title = title
    self.initialTitle = initialTitle
    self.initialDescription = initialDescription
    self.onSave = onSave
    _goalTitle = State(initialValue: initialTitle)
    _goalDescription = State(initialValue: initialDescription ?? "")
  }

  private var normalizedTitle: String {
    goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      Text(title)
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)

      TextField("Goal", text: $goalTitle)
        .textFieldStyle(.roundedBorder)
      TextField("Description (optional)", text: $goalDescription, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...5)

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save") {
          let description = goalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
          onSave(normalizedTitle, description.isEmpty ? nil : description)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(normalizedTitle.isEmpty)
      }
    }
    .padding(OmiSpacing.xl)
    .frame(width: 420)
    .background(OmiColors.backgroundPrimary)
  }
}
