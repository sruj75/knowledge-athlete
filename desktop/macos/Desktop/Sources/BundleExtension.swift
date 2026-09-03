import Foundation

// Custom Bundle accessor for our resource bundle.
// This is necessary because:
// 1. Swift PM generates code that looks for the bundle at the app root
// 2. macOS code signing doesn't allow files at the app root (outside Contents/)
// 3. We need the bundle in Contents/Resources/ for proper code signing
// Note: We use "resourceBundle" instead of "module" to avoid conflicts with Swift PM's generated accessor
extension Foundation.Bundle {
  static let resourceBundle: Bundle = {
    let bundleName = "Omi Computer_Omi Computer"
    let bundleDirectoryName = "\(bundleName).bundle"
    let loadedBundleURLs =
      [Bundle.main.bundleURL]
      + Bundle.allBundles.map(\.bundleURL)
      + Bundle.allFrameworks.map(\.bundleURL)
    var candidatePaths: [String] = []
    var seen = Set<String>()

    for loadedBundleURL in loadedBundleURLs {
      // Installed apps place target resources under Contents/Resources. SwiftPM
      // test hosts place the target resource bundle beside the .xctest bundle.
      let candidates = [
        loadedBundleURL
          .appendingPathComponent("Contents/Resources")
          .appendingPathComponent(bundleDirectoryName),
        loadedBundleURL.appendingPathComponent(bundleDirectoryName),
        loadedBundleURL.deletingLastPathComponent()
          .appendingPathComponent(bundleDirectoryName),
      ]
      for candidate in candidates {
        let path = candidate.standardizedFileURL.path
        guard seen.insert(path).inserted else { continue }
        candidatePaths.append(path)
        if let bundle = Bundle(path: path) {
          return bundle
        }
      }
    }

    // If none found, crash with helpful message
    Swift.fatalError("could not load resource bundle: tried \(candidatePaths.joined(separator: ", "))")
  }()
}
