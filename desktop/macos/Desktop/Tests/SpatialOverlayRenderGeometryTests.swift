import XCTest

@testable import Omi_Computer

/// These tests validate the rendered arrow apex and instruction-card placement against
/// the geometry solver rather than only its intended target point.
final class SpatialOverlayRenderGeometryTests: XCTestCase {

  // MARK: Rendered apex matches solver intent on every edge

  func testRenderedArrowApexEqualsSolverGlobalArrowTipForEveryEdge() {
    let panelSize = CGSize(width: 330, height: 118)
    for edge in SpatialOverlayAttachmentEdge.allCases {
      // A representative panel anywhere on screen with the apex offset into the panel.
      let panelFrame = CGRect(x: 640, y: 410, width: panelSize.width, height: panelSize.height)
      let arrowTipInPanel: CGPoint
      switch edge {
      case .above: arrowTipInPanel = CGPoint(x: 165, y: 0)
      case .below: arrowTipInPanel = CGPoint(x: 165, y: panelSize.height)
      case .leading: arrowTipInPanel = CGPoint(x: panelSize.width, y: 59)
      case .trailing: arrowTipInPanel = CGPoint(x: 0, y: 59)
      }
      let placement = SpatialOverlayPlacementResult(
        panelFrame: panelFrame,
        targetPoint: .zero,
        arrowTipInPanel: arrowTipInPanel,
        attachmentEdge: edge,
        score: 0,
        clampDelta: .zero,
        diagnostics: []
      )
      let render = SpatialOverlayRenderGeometry(placement: placement, panelSize: panelSize)

      XCTAssertEqual(
        render.globalRenderedArrowTip.x, placement.globalArrowTip.x, accuracy: 0.001,
        "edge \(edge): rendered apex x drifted from solver target")
      XCTAssertEqual(
        render.globalRenderedArrowTip.y, placement.globalArrowTip.y, accuracy: 0.001,
        "edge \(edge): rendered apex y drifted from solver target")

      // The pointer triangle's apex vertex must coincide with the rendered tip.
      let apexVertex = apexVertex(of: render.pointerFrame, edge: edge)
      XCTAssertEqual(
        apexVertex.x, render.renderedArrowTip.x, accuracy: 0.001,
        "edge \(edge): triangle apex x not at rendered tip")
      XCTAssertEqual(
        apexVertex.y, render.renderedArrowTip.y, accuracy: 0.001,
        "edge \(edge): triangle apex y not at rendered tip")

      // The bubble must never overlap the arrow's tip pixel.
      XCTAssertFalse(
        render.bubbleFrame.contains(render.renderedArrowTip),
        "edge \(edge): bubble covers the arrow tip")
    }
  }

  func testRenderGeometryUsesPlacementArrowSize() {
    let placement = SpatialOverlayPlacementResult(
      panelFrame: CGRect(x: 100, y: 100, width: 240, height: 120),
      targetPoint: .zero,
      arrowTipInPanel: CGPoint(x: 120, y: 0),
      arrowSize: CGSize(width: 48, height: 24),
      attachmentEdge: .above,
      score: 0,
      clampDelta: .zero,
      diagnostics: []
    )

    let render = SpatialOverlayRenderGeometry(
      placement: placement,
      panelSize: CGSize(width: 240, height: 120)
    )

    XCTAssertEqual(render.pointerFrame.width, 48, accuracy: 0.001)
    XCTAssertEqual(render.pointerFrame.height, 24, accuracy: 0.001)
    XCTAssertEqual(render.bubbleFrame.height, 88, accuracy: 0.001)
  }

  func testPlacementCapsArrowInsetForTinyPanels() throws {
    let screen = SpatialOverlayScreen(
      id: "tiny", frame: CGRect(x: 0, y: 0, width: 320, height: 240),
      visibleFrame: CGRect(x: 0, y: 0, width: 320, height: 240))
    let candidate = SpatialOverlayAnchorCandidate(
      id: "tiny-add",
      targetRect: CGRect(x: 110, y: 100, width: 20, height: 20),
      screen: screen,
      evidence: [SpatialOverlayTargetEvidence(source: .layoutHeuristic, confidence: 0.9)],
      confidence: 0.9,
      allowedUses: [.displayGuidance])

    let placement = try SpatialOverlayPlacementSolver.place(
      target: candidate,
      spec: SpatialOverlayPlacementSpec(
        overlaySize: CGSize(width: 42, height: 34),
        preferredEdges: [.above],
        margin: 0,
        arrowSize: CGSize(width: 96, height: 28),
        minimumArrowInset: 60,
        canCoverTarget: true)
    ).get()

    XCTAssertGreaterThanOrEqual(placement.arrowTipInPanel.x, 0)
    XCTAssertLessThanOrEqual(placement.arrowTipInPanel.x, placement.panelFrame.width)
  }

  /// Mirrors `TrianglePointer.path(in:)` — the vertex that should land on the target.
  private func apexVertex(of rect: CGRect, edge: SpatialOverlayAttachmentEdge) -> CGPoint {
    switch edge {
    case .above: return CGPoint(x: rect.midX, y: rect.maxY)
    case .below: return CGPoint(x: rect.midX, y: rect.minY)
    case .leading: return CGPoint(x: rect.maxX, y: rect.midY)
    case .trailing: return CGPoint(x: rect.minX, y: rect.midY)
    }
  }

  // MARK: Coordinate conversion uses the primary display as the flip reference

  func testGlobalTopLeftFlipUsesPrimaryReferenceNotContainingScreen() {
    // A secondary display to the right of and taller than the primary. A target on the
    // secondary must flip against the PRIMARY maxY, otherwise the panel lands at the
    // wrong absolute Y (the multi-monitor variant of the bad screenshot).
    let primaryMaxY: CGFloat = 982
    let secondaryScreenFrame = CGRect(x: 1512, y: -200, width: 1920, height: 1200)

    let targetTopLeft = CGRect(x: 1800, y: 300, width: 100, height: 40)

    let correct = SpatialOverlayGeometry.appKitFrame(
      topLeftOrigin: targetTopLeft.origin, size: targetTopLeft.size, flipMaxY: primaryMaxY)
    let buggyContainingScreenFlip = SpatialOverlayGeometry.appKitFrame(
      topLeftOrigin: targetTopLeft.origin, size: targetTopLeft.size,
      screenFrame: secondaryScreenFrame)

    XCTAssertEqual(correct.minY, primaryMaxY - 300 - 40, accuracy: 0.001)
    XCTAssertNotEqual(
      correct.minY, buggyContainingScreenFlip.minY,
      "primary-reference flip must differ from the old containing-screen flip on a secondary display"
    )
  }

  // MARK: Full pipeline against an independent, screenshot-derived Add rect

  @MainActor
  func testInstructionCardUsesCompactHeightForShortGuidance() {
    let compact = PermissionGuidanceOverlay.instructionCardSize(
      title: "Screen Recording",
      subtitle: "Enable Omi in System Settings."
    )
    let expanded = PermissionGuidanceOverlay.instructionCardSize(
      title: "Allow Screen Recording for Omi",
      subtitle:
        "Flip the Omi toggle on under Screen & System Audio Recording, then return to Omi to continue."
    )

    XCTAssertEqual(compact.width, 420)
    XCTAssertEqual(compact.height, 88)
    XCTAssertEqual(expanded.width, 420)
    XCTAssertEqual(expanded.height, 118)
  }

  @MainActor
  func testInstructionCardCentersOnAnchorAndStaysOnScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let settingsWindow = CGRect(x: 380, y: 120, width: 760, height: 700)
    let card = CGSize(width: 380, height: 96)

    let frame = PermissionGuidanceOverlay.instructionCardFrame(
      anchor: settingsWindow, cardSize: card, visibleFrame: visible)
    // Horizontally centered on the settings window.
    XCTAssertEqual(frame.midX, settingsWindow.midX, accuracy: 0.5)
    // Near the window's top edge (AppKit maxY) and fully on screen.
    XCTAssertLessThanOrEqual(frame.maxY, visible.maxY - 12 + 0.5)
    XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
    XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
    XCTAssertEqual(frame.size, card)
  }

  @MainActor
  func testInstructionCardWithoutAnchorStaysWithinVisibleFrame() {
    let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)
    let card = CGSize(width: 380, height: 96)
    let frame = PermissionGuidanceOverlay.instructionCardFrame(
      anchor: nil, cardSize: card, visibleFrame: visible)
    XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
    XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
    XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
    XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
  }

}
