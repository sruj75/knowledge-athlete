import AppKit
import XCTest

@testable import Omi_Computer

final class SpatialOverlayGeometryTests: XCTestCase {
  func testTopLeftFrameNormalizesToAppKitCoordinates() {
    let frame = SpatialOverlayGeometry.appKitFrame(
      topLeftOrigin: CGPoint(x: 120, y: 80),
      size: CGSize(width: 640, height: 480),
      screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
    )

    XCTAssertEqual(frame, NSRect(x: 120, y: 340, width: 640, height: 480))
  }

  func testAnchoredBelowFrameMatchesAgentPillPlacement() {
    let frame = SpatialOverlayGeometry.frameAnchoredBelow(
      anchorFrame: NSRect(x: 500, y: 760, width: 280, height: 42),
      contentSize: NSSize(width: 96, height: 56),
      minimumWidth: 240,
      gap: 8
    )

    XCTAssertEqual(frame, NSRect(x: 520, y: 696, width: 240, height: 56))
  }

}
