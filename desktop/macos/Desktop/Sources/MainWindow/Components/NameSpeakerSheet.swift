import OmiTheme
import SwiftUI

/// Conversation-scoped speaker naming. Names are never added to a reusable directory.
struct NameSpeakerSheet: View {
  let segment: TranscriptSegment
  let allSegments: [TranscriptSegment]
  let onSave: (_ name: String?, _ isUser: Bool, _ segmentIndices: [Int]) -> Void
  let onDismiss: () -> Void

  @State private var isUserSelected = false
  @State private var isAddingName = false
  @State private var speakerName = ""
  @State private var tagAllFromSpeaker = true
  @State private var isSaving = false

  private var sameSpeakerSegments: [TranscriptSegment] {
    allSegments.filter { $0.speakerId == segment.speakerId && !$0.isUser }
  }

  private var sameSpeakerIndices: [Int] {
    allSegments.enumerated().compactMap { index, candidate in
      candidate.speakerId == segment.speakerId && !candidate.isUser ? index : nil
    }
  }

  private var tappedSegmentIndex: Int {
    allSegments.firstIndex(where: { $0.id == segment.id }) ?? 0
  }

  private var previewText: String {
    segment.text.count > 120 ? String(segment.text.prefix(120)) + "..." : segment.text
  }

  private var trimmedName: String {
    speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    isUserSelected || (isAddingName && !trimmedName.isEmpty)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Name Speaker")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        DismissButton(action: onDismiss)
      }
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.top, OmiSpacing.xl)
      .padding(.bottom, OmiSpacing.md)

      Divider().background(OmiColors.border)

      ScrollView {
        VStack(alignment: .leading, spacing: OmiSpacing.xl) {
          speakerInfoSection
          selectorSection
          if sameSpeakerSegments.count > 1 {
            Toggle(isOn: $tagAllFromSpeaker) {
              Text(
                "Also tag \(sameSpeakerSegments.count - 1) other segment\(sameSpeakerSegments.count - 1 == 1 ? "" : "s") from this speaker"
              )
              .scaledFont(size: OmiType.body)
              .foregroundColor(OmiColors.textSecondary)
            }
            .toggleStyle(.checkbox)
          }
        }
        .padding(OmiSpacing.xl)
      }

      Divider().background(OmiColors.border)

      HStack {
        Spacer()
        Button("Cancel", action: onDismiss)
          .buttonStyle(.plain)
          .foregroundColor(OmiColors.textSecondary)
          .padding(.horizontal, OmiSpacing.lg)
          .padding(.vertical, OmiSpacing.sm)

        Button(action: save) {
          if isSaving {
            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
          } else {
            Text("Save")
          }
        }
        .buttonStyle(.plain)
        .foregroundColor(canSave ? .black : OmiColors.textTertiary)
        .padding(.horizontal, OmiSpacing.xl)
        .padding(.vertical, OmiSpacing.sm)
        .background(Capsule().fill(canSave ? Color.white : OmiColors.backgroundTertiary))
        .disabled(!canSave || isSaving)
      }
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.vertical, OmiSpacing.md)
    }
    .frame(width: 400, height: 450)
    .background(OmiColors.backgroundPrimary)
  }

  private var speakerInfoSection: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      HStack(spacing: OmiSpacing.sm) {
        Circle()
          .fill(OmiColors.backgroundQuaternary)
          .frame(width: 28, height: 28)
          .overlay(
            Text(String(segment.speakerId))
              .scaledFont(size: OmiType.caption, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary))
        Text("Speaker \(segment.speakerId)")
          .scaledFont(size: OmiType.body, weight: .medium)
          .foregroundColor(OmiColors.textPrimary)
      }
      Text("\"\(previewText)\"")
        .scaledFont(size: OmiType.body)
        .foregroundColor(OmiColors.textSecondary)
        .italic()
        .lineLimit(3)
    }
    .padding(OmiSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
        .fill(OmiColors.backgroundSecondary))
  }

  private var selectorSection: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      Text("Who is this?")
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)

      FlowLayout(spacing: OmiSpacing.sm) {
        selectionChip(label: "You", isSelected: isUserSelected) {
          isUserSelected = true
          isAddingName = false
          speakerName = ""
        }
        selectionChip(label: "+ Add Name", isSelected: isAddingName, isAction: true) {
          isAddingName = true
          isUserSelected = false
        }
      }

      if isAddingName {
        TextField("Speaker name", text: $speakerName)
          .textFieldStyle(.plain)
          .scaledFont(size: OmiType.body)
          .foregroundColor(OmiColors.textPrimary)
          .padding(.horizontal, OmiSpacing.sm)
          .padding(.vertical, OmiSpacing.sm)
          .background(
            RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
              .fill(OmiColors.backgroundSecondary)
          )
          .overlay(
            RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
              .stroke(OmiColors.border, lineWidth: 1)
          )
          .onSubmit { if canSave { save() } }
      }
    }
  }

  private func save() {
    isSaving = true
    onSave(
      isUserSelected ? nil : trimmedName,
      isUserSelected,
      tagAllFromSpeaker ? sameSpeakerIndices : [tappedSegmentIndex])
  }

  private func selectionChip(
    label: String,
    isSelected: Bool,
    isAction: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(label)
        .scaledFont(size: OmiType.body, weight: isSelected ? .semibold : .regular)
        .foregroundColor(isSelected ? .black : (isAction ? OmiColors.accent : OmiColors.textPrimary))
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
        .background(Capsule().fill(isSelected ? Color.white : OmiColors.backgroundTertiary))
        .overlay(
          Capsule().stroke(
            isSelected ? OmiColors.border : (isAction ? OmiColors.accent.opacity(0.3) : Color.clear),
            lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}
