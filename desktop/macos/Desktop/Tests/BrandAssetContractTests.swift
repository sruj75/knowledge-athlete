import AppKit
import XCTest

@testable import Omi_Computer

final class BrandAssetContractTests: XCTestCase {
  private let requiredPNGResources = [
    "intentive_app_icon",
    "intentive_mark",
    "intentive_menu_bar_icon",
    "intentive_signin_backdrop",
    "intentive_microphone_settings",
    "intentive_permission_01_privacy",
    "intentive_permission_02_screen_recording",
    "intentive_permission_03_enable",
    "intentive_permission_04_return",
  ]

  func testApprovedIntentiveAssetPackResolvesFromTheShippingBundle() throws {
    let bundle = try testResourceBundle()
    for name in requiredPNGResources {
      let url = try XCTUnwrap(
        bundle.url(forResource: name, withExtension: "png"),
        "Missing shipping resource: \(name).png")
      XCTAssertNotNil(NSImage(contentsOf: url), "Unreadable shipping resource: \(name).png")
    }
  }

  func testBrandAssetsKeepTheirRendererDimensions() throws {
    XCTAssertEqual(try pixelSize(of: "intentive_app_icon"), PixelSize(width: 1024, height: 1024))
    XCTAssertEqual(try pixelSize(of: "intentive_menu_bar_icon"), PixelSize(width: 88, height: 88))
    XCTAssertEqual(
      try pixelSize(of: "intentive_signin_backdrop"),
      PixelSize(width: 4096, height: 2304))

    for step in PermissionTutorialContent.steps {
      let size = try pixelSize(of: step.imageName)
      XCTAssertEqual(size.width * 3, size.height * 4, "\(step.imageName) must remain 4:3")
    }
  }

  func testDockIconKeepsTheStandardTileInsetAndStrongCanonicalMark() throws {
    let bundle = try testResourceBundle()
    let url = try XCTUnwrap(bundle.url(forResource: "intentive_app_icon", withExtension: "png"))
    let data = try Data(contentsOf: url)
    let representation = try XCTUnwrap(NSBitmapImageRep(data: data))
    let bounds = try pixelBounds(in: representation)

    XCTAssertTrue((810...834).contains(bounds.opaque.width))
    XCTAssertTrue((810...834).contains(bounds.opaque.height))
    XCTAssertEqual(bounds.opaque.midX, 511, accuracy: 2)
    XCTAssertEqual(bounds.opaque.midY, 511, accuracy: 2)

    XCTAssertTrue((540...565).contains(bounds.dark.width))
    XCTAssertTrue((575...610).contains(bounds.dark.height))
    // The head silhouette is deliberately asymmetric; preserve the canonical
    // owner-supplied geometry rather than centering its rectangular bounds.
    XCTAssertEqual(bounds.dark.midX, 479, accuracy: 8)
  }

  func testPermissionTutorialOwnsFourOrderedFramesAndLoops() {
    XCTAssertEqual(
      PermissionTutorialContent.steps.map(\.imageName),
      [
        "intentive_permission_01_privacy",
        "intentive_permission_02_screen_recording",
        "intentive_permission_03_enable",
        "intentive_permission_04_return",
      ])
    XCTAssertEqual(PermissionTutorialContent.nextIndex(after: 0), 1)
    XCTAssertEqual(PermissionTutorialContent.nextIndex(after: 3), 0)
    XCTAssertEqual(PermissionTutorialContent.nextIndex(after: -1), 0)
    XCTAssertEqual(PermissionTutorialContent.nextIndex(after: 0, count: 0), 0)
  }

  func testRetiredInheritedIdentityAssetsAreNotPackaged() throws {
    let bundle = try testResourceBundle()
    for resource in [
      ("herologo", "png"),
      ("signin_bg", "png"),
      ("omi_app_icon", "png"),
      ("omi_menu_bar_icon", "png"),
      ("permissions", "gif"),
      ("omi_notch_logo", "svg"),
      ("tray_icon", "png"),
    ] {
      XCTAssertNil(
        bundle.url(forResource: resource.0, withExtension: resource.1),
        "Retired identity resource still packaged: \(resource.0).\(resource.1)")
    }
  }

  private func pixelSize(of name: String) throws -> PixelSize {
    let bundle = try testResourceBundle()
    let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "png"))
    let data = try Data(contentsOf: url)
    let representation = try XCTUnwrap(NSBitmapImageRep(data: data))
    return PixelSize(width: representation.pixelsWide, height: representation.pixelsHigh)
  }

  private func pixelBounds(in representation: NSBitmapImageRep) throws -> (
    opaque: PixelBounds, dark: PixelBounds
  ) {
    XCTAssertEqual(representation.bitsPerSample, 8)
    XCTAssertFalse(representation.isPlanar)
    XCTAssertGreaterThanOrEqual(representation.samplesPerPixel, 4)
    let bytes = try XCTUnwrap(representation.bitmapData)
    var opaque = PixelBounds.empty
    var dark = PixelBounds.empty

    for y in 0..<representation.pixelsHigh {
      for x in 0..<representation.pixelsWide {
        let offset = y * representation.bytesPerRow + x * representation.samplesPerPixel
        let red = Int(bytes[offset])
        let green = Int(bytes[offset + 1])
        let blue = Int(bytes[offset + 2])
        let alpha = Int(bytes[offset + representation.samplesPerPixel - 1])
        if alpha >= 16 {
          opaque.include(x: x, y: y)
        }
        if alpha >= 230, max(red, green, blue) <= 64 {
          dark.include(x: x, y: y)
        }
      }
    }

    return (try opaque.required(), try dark.required())
  }

  private func testResourceBundle() throws -> Bundle {
    let bundleName = "Omi Computer_Omi Computer.bundle"
    let testBundleURL = Bundle(for: Self.self).bundleURL
    let candidates = [
      testBundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
      testBundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(bundleName),
    ]
    return try XCTUnwrap(
      candidates.lazy.compactMap { Bundle(url: $0) }.first,
      "Could not locate the SwiftPM resource bundle beside \(testBundleURL.path)")
  }
}

private struct PixelSize: Equatable {
  let width: Int
  let height: Int
}

private struct PixelBounds {
  var minX: Int
  var minY: Int
  var maxX: Int
  var maxY: Int

  static let empty = PixelBounds(minX: .max, minY: .max, maxX: .min, maxY: .min)

  var width: Int { maxX - minX + 1 }
  var height: Int { maxY - minY + 1 }
  var midX: Double { Double(minX + maxX) / 2 }
  var midY: Double { Double(minY + maxY) / 2 }

  mutating func include(x: Int, y: Int) {
    minX = min(minX, x)
    minY = min(minY, y)
    maxX = max(maxX, x)
    maxY = max(maxY, y)
  }

  func required() throws -> PixelBounds {
    guard minX <= maxX, minY <= maxY else {
      throw PixelBoundsError.noPixels
    }
    return self
  }
}

private enum PixelBoundsError: Error {
  case noPixels
}
