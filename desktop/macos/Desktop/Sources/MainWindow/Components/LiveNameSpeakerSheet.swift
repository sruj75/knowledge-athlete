import OmiTheme
import SwiftUI

/// Conversation-scoped naming during live transcription.
struct LiveNameSpeakerSheet: View {
  let speakerId: Int
  let sampleText: String
  let currentName: String?
  let onSave: (_ name: String) async -> Bool
  let onDismiss: () -> Void

  @State private var name = ""
  @State private var isSaving = false

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var previewText: String {
    sampleText.count > 120 ? String(sampleText.prefix(120)) + "..." : sampleText
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

      VStack(alignment: .leading, spacing: OmiSpacing.xl) {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          HStack(spacing: OmiSpacing.sm) {
            Circle()
              .fill(OmiColors.backgroundQuaternary)
              .frame(width: 28, height: 28)
              .overlay(Text(String(speakerId)).scaledFont(size: OmiType.caption, weight: .semibold))
            Text("Speaker \(speakerId)")
              .scaledFont(size: OmiType.body, weight: .medium)
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

        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          Text("Who is this?")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(OmiColors.textSecondary)
          TextField("Speaker name", text: $name)
            .textFieldStyle(.plain)
            .scaledFont(size: OmiType.body)
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
            .onSubmit { if !trimmedName.isEmpty { save() } }
          Text("This name applies only to this conversation, including future segments from the same speaker.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(OmiColors.textQuaternary)
        }
      }
      .padding(OmiSpacing.xl)

      Spacer()
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
        .foregroundColor(trimmedName.isEmpty ? OmiColors.textTertiary : .black)
        .padding(.horizontal, OmiSpacing.xl)
        .padding(.vertical, OmiSpacing.sm)
        .background(Capsule().fill(trimmedName.isEmpty ? OmiColors.backgroundTertiary : Color.white))
        .disabled(trimmedName.isEmpty || isSaving)
      }
      .padding(.horizontal, OmiSpacing.xl)
      .padding(.vertical, OmiSpacing.md)
    }
    .frame(width: 400, height: 400)
    .background(OmiColors.backgroundPrimary)
    .onAppear { name = currentName ?? "" }
  }

  private func save() {
    let submitted = trimmedName
    guard !submitted.isEmpty else { return }
    isSaving = true
    Task {
      if await onSave(submitted) {
        onDismiss()
      }
      isSaving = false
    }
  }
}
