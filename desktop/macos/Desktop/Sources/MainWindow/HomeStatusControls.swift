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

struct HomeListeningStatusButton: View {
  let title: String
  let systemImage: String
  let status: HomeStatusState
  let modeTitle: String
  let isMeetingsOnly: Bool
  let isToggling: Bool
  let action: () -> Void
  let modeAction: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 0) {
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

          VStack(alignment: .leading, spacing: 1) {
            Text(title)
              .scaledFont(size: OmiType.caption, weight: .semibold)
              .lineLimit(1)
            if isHovering {
              Text(modeTitle)
                .scaledFont(size: 8, weight: .medium)
                .foregroundStyle(status.isActive ? OmiColors.textSecondary : OmiColors.textTertiary)
                .lineLimit(1)
                .transition(.opacity)
            }
          }
        }
        .padding(.leading, OmiSpacing.md)
        .padding(.trailing, OmiSpacing.sm)
        .frame(height: 34)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isToggling)
      .help("Listening: \(status.text), \(modeTitle)")
      .accessibilityLabel("Listening \(status.text), \(modeTitle)")

      if isHovering {
        Rectangle()
          .fill(OmiColors.textPrimary.opacity(0.12))
          .frame(width: 1, height: 18)
          .transition(.opacity)
        Button(action: modeAction) {
          Image(systemName: isMeetingsOnly ? "person.2.fill" : "person.fill")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundStyle(status.isActive ? Color.green : OmiColors.textTertiary)
            .frame(width: 30, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isMeetingsOnly ? "Switch to always listening" : "Switch to meetings only")
        .accessibilityLabel(isMeetingsOnly ? "Switch Listening to Always" : "Switch Listening to Meetings Only")
        .transition(.opacity)
      }
    }
    .foregroundStyle(
      status.isActive ? OmiColors.textPrimary : (status.isBlocked ? status.indicator : OmiColors.textTertiary)
    )
    .background(Capsule(style: .continuous).fill(statusFill))
    .overlay(Capsule(style: .continuous).stroke(statusStroke, lineWidth: 1))
    .contentShape(Capsule())
    .frame(height: 34)
    .onHover { isHovering = $0 }
    .omiAnimation(.easeInOut(duration: 0.14), value: isHovering)
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
