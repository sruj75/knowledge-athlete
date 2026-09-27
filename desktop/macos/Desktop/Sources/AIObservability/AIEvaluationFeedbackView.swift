import OmiTheme
import SwiftUI

struct AIEvaluationFeedbackView: View {
  let message: ChatMessage
  @ObservedObject private var reporter = AIEvaluationReporter.shared

  var body: some View {
    if !message.isStreaming, message.sender == .ai,
      let key = message.clientTurnId, let receipt = reporter.receipts[key]
    {
      HStack(spacing: OmiSpacing.sm) {
        feedbackButton(key: key, helpful: true, selected: receipt.score == 1)
        feedbackButton(key: key, helpful: false, selected: receipt.score == 0)
      }
    }
  }

  private func feedbackButton(key: String, helpful: Bool, selected: Bool) -> some View {
    Button {
      reporter.score(continuityKey: key, helpful: helpful)
    } label: {
      Image(systemName: (helpful ? "hand.thumbsup" : "hand.thumbsdown") + (selected ? ".fill" : ""))
        .scaledFont(size: OmiType.caption)
        .foregroundColor(selected ? OmiColors.accent : OmiColors.textTertiary)
    }
    .buttonStyle(.plain)
    .help(helpful ? "Helpful" : "Unhelpful")
    .accessibilityLabel(helpful ? "Helpful response" : "Unhelpful response")
  }
}
