import OmiTheme
import SwiftUI

/// Detailed transcript view showing all segments as chat bubbles
struct TranscriptDetailView: View {
  let segments: [TranscriptSegment]
  var onSpeakerTapped: ((TranscriptSegment) -> Void)? = nil

  var body: some View {
    ScrollView {
      LazyVStack(spacing: OmiSpacing.md) {
        ForEach(segments) { segment in
          SpeakerBubbleView(
            segment: segment,
            isUser: segment.isUser,
            personName: segment.isUser ? nil : segment.speaker,
            onSpeakerTapped: segment.isUser ? nil : (onSpeakerTapped != nil ? { onSpeakerTapped?(segment) } : nil)
          )
        }
      }
      .padding(OmiSpacing.lg)
    }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    TranscriptDetailView(segments: [])
      .frame(width: 400, height: 400)
      .background(OmiColors.backgroundSecondary)
  }
#endif
