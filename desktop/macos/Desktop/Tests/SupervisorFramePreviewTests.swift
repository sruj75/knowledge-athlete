import CoreGraphics
import ImageIO
import XCTest

@testable import Omi_Computer

final class SupervisorFramePreviewTests: XCTestCase {
  private func jpeg(width: Int, height: Int) throws -> Data {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())
    let out = NSMutableData()
    let dest = try XCTUnwrap(
      CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return out as Data
  }

  private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
  }

  func testOversizedFrameIsDownscaledToTheTileBudget() throws {
    let large = try jpeg(width: 3000, height: 1950)
    let preview = SuggestionFramePreview.downscaledJPEG(from: large)

    XCTAssertEqual(try pixelSize(of: preview).width, SuggestionFramePreview.maxWidth)
    XCTAssertLessThan(preview.count, large.count, "downscaling must actually shrink the payload")
  }

  func testAspectRatioIsPreserved() throws {
    let preview = SuggestionFramePreview.downscaledJPEG(from: try jpeg(width: 3000, height: 1500))
    let size = try pixelSize(of: preview)
    XCTAssertEqual(Double(size.width) / Double(size.height), 2.0, accuracy: 0.02)
  }

  func testAlreadySmallFrameIsPassedThroughUntouched() throws {
    let small = try jpeg(width: 800, height: 600)
    XCTAssertEqual(SuggestionFramePreview.downscaledJPEG(from: small), small)
  }

  /// A frame we cannot decode must still be sent — the suggestion is worth more than the
  /// saving, and silently dropping it would look like the feature is broken.
  func testUndecodableDataIsReturnedUnchangedRatherThanDropped() {
    let garbage = Data([0x00, 0x01, 0x02, 0x03])
    XCTAssertEqual(SuggestionFramePreview.downscaledJPEG(from: garbage), garbage)
  }
}
