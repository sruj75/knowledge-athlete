import SwiftUI

/// Wraps retained chips and badges into rows within the proposed width.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  struct CacheData {
    var result: FlowResult?
    var width: CGFloat = 0
  }

  func makeCache(subviews: Subviews) -> CacheData {
    CacheData()
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
    let width = proposal.width ?? 0
    let result = FlowResult(in: width, subviews: subviews, spacing: spacing)
    cache.result = result
    cache.width = width
    return result.size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
    let result =
      if let cached = cache.result, cache.width == bounds.width {
        cached
      } else {
        FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
      }
    for (index, subview) in subviews.enumerated() {
      let idealSize = subview.sizeThatFits(.unspecified)
      let subProposal: ProposedViewSize =
        idealSize.width > bounds.width
        ? ProposedViewSize(width: bounds.width, height: nil)
        : .unspecified
      subview.place(
        at: CGPoint(
          x: bounds.minX + result.positions[index].x,
          y: bounds.minY + result.positions[index].y),
        proposal: subProposal)
    }
  }

  struct FlowResult {
    var size: CGSize = .zero
    var positions: [CGPoint] = []

    init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
      var x: CGFloat = 0
      var y: CGFloat = 0
      var rowHeight: CGFloat = 0

      for subview in subviews {
        var size = subview.sizeThatFits(.unspecified)
        if size.width > maxWidth {
          size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        if x + size.width > maxWidth && x > 0 {
          x = 0
          y += rowHeight + spacing
          rowHeight = 0
        }
        positions.append(CGPoint(x: x, y: y))
        rowHeight = max(rowHeight, size.height)
        x += size.width + spacing
        self.size.width = max(self.size.width, min(x, maxWidth))
      }
      self.size.height = y + rowHeight
    }
  }
}
