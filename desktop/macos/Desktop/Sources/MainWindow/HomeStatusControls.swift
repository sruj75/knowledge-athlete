import OmiTheme
import SwiftUI

enum HomeStatusState {
  case active
  case inactive
  case blocked

  var indicator: Color {
    switch self {
    case .active: return Color.green
    case .inactive: return OmiColors.textQuaternary
    case .blocked: return Color(red: 1.0, green: 0.24, blue: 0.30)
    }
  }

  var text: String {
    switch self {
    case .active: return "On"
    case .inactive: return "Off"
    case .blocked: return "Blocked"
    }
  }

  var isActive: Bool {
    if case .active = self { return true }
    return false
  }

  var isBlocked: Bool {
    if case .blocked = self { return true }
    return false
  }
}

struct HomeStatusButton: View {
  let title: String
  let systemImage: String
  let status: HomeStatusState
  let isToggling: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        ZStack {
          if isToggling {
            ProgressView().controlSize(.small).scaleEffect(0.55)
          } else {
            Image(systemName: systemImage)
              .scaledFont(size: OmiType.body, weight: .semibold)
          }
        }
        .frame(width: 18, height: 18)

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .lineLimit(1)
      }
      .foregroundStyle(
        status.isActive ? OmiColors.textPrimary : (status.isBlocked ? status.indicator : OmiColors.textTertiary)
      )
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(height: 34)
      .background(Capsule(style: .continuous).fill(statusFill))
      .overlay(Capsule(style: .continuous).stroke(statusStroke, lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(isToggling)
    .onHover { isHovering = $0 }
    .help("\(title): \(status.text)")
    .accessibilityLabel("\(title) \(status.text)")
  }

  private var statusFill: Color {
    if status.isActive { return Color.green.opacity(isHovering ? 0.20 : 0.12) }
    if status.isBlocked { return status.indicator.opacity(isHovering ? 0.16 : 0.10) }
    return isHovering ? OmiColors.backgroundTertiary.opacity(0.6) : Color.clear
  }

  private var statusStroke: Color {
    if status.isActive { return Color.green.opacity(0.38) }
    if status.isBlocked { return status.indicator.opacity(isHovering ? 0.54 : 0.38) }
    return OmiColors.textPrimary.opacity(isHovering ? 0.12 : 0.0)
  }
}
