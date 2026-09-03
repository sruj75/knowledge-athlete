import AppKit
import OmiTheme
import SwiftUI

struct PermissionTutorialStep: Equatable, Identifiable {
  let imageName: String
  let title: String
  let detail: String

  var id: String { imageName }
}

enum PermissionTutorialContent {
  static let steps = [
    PermissionTutorialStep(
      imageName: "intentive_permission_01_privacy",
      title: "Open Privacy & Security",
      detail: "In System Settings, select Privacy & Security."
    ),
    PermissionTutorialStep(
      imageName: "intentive_permission_02_screen_recording",
      title: "Choose screen recording",
      detail: "Open Screen & System Audio Recording."
    ),
    PermissionTutorialStep(
      imageName: "intentive_permission_03_enable",
      title: "Enable Intentive",
      detail: "Turn Intentive on in the app list."
    ),
    PermissionTutorialStep(
      imageName: "intentive_permission_04_return",
      title: "Return to Intentive",
      detail: "Permission updates automatically when you come back."
    ),
  ]

  static func nextIndex(after index: Int, count: Int = steps.count) -> Int {
    guard count > 0, (0..<count).contains(index) else { return 0 }
    return (index + 1) % count
  }
}

struct PermissionTutorialSlideshow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentIndex = 0
  @State private var isPointerInside = false

  private var currentStep: PermissionTutorialStep {
    PermissionTutorialContent.steps[currentIndex]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      ZStack {
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(OmiColors.backgroundTertiary)

        if let image = image(named: currentStep.imageName) {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .transition(.opacity)
            .id(currentStep.id)
        } else {
          Image(systemName: "rectangle.stack")
            .scaledFont(size: 32, weight: .medium)
            .foregroundStyle(OmiColors.textTertiary)
            .accessibilityLabel("Permission tutorial image unavailable")
        }
      }
      .aspectRatio(4.0 / 3.0, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .stroke(OmiColors.backgroundQuaternary, lineWidth: 1)
      )

      HStack(alignment: .firstTextBaseline, spacing: OmiSpacing.sm) {
        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(currentStep.title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(OmiColors.textPrimary)
          Text(currentStep.detail)
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(OmiColors.textSecondary)
        }

        Spacer(minLength: OmiSpacing.sm)

        HStack(spacing: OmiSpacing.xs) {
          ForEach(Array(PermissionTutorialContent.steps.enumerated()), id: \.element.id) {
            index, step in
            Button {
              select(index)
            } label: {
              Capsule()
                .fill(index == currentIndex ? OmiColors.textPrimary : OmiColors.textTertiary)
                .frame(width: index == currentIndex ? 16 : 6, height: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show step \(index + 1): \(step.title)")
          }
        }
      }
    }
    .onHover { isPointerInside = $0 }
    .task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(4))
        } catch {
          return
        }
        guard !reduceMotion, !isPointerInside else { continue }
        select(PermissionTutorialContent.nextIndex(after: currentIndex))
      }
    }
  }

  private func image(named name: String) -> NSImage? {
    guard let url = Bundle.resourceBundle.url(forResource: name, withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }

  private func select(_ index: Int) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
      currentIndex = index
    }
  }
}
