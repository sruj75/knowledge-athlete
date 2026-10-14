import OmiTheme
import SwiftUI

/// Shared indication for newly created conversations and memories.
struct NewBadge: View {
  var body: some View {
    Text("New")
      .scaledFont(size: OmiType.micro, weight: .semibold)
      .foregroundColor(OmiColors.textSecondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(OmiColors.backgroundTertiary))
  }
}
