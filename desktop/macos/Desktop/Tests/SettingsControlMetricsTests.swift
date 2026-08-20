import XCTest

@testable import Omi_Computer

final class SettingsControlMetricsTests: XCTestCase {
  func testSteppedSliderEndpointsKeepThumbInsideContainer() {
    let containerWidth: CGFloat = 200
    let thumbRadius = SettingsControlMetrics.steppedSliderThumbDiameter / 2

    let firstPosition = SettingsControlMetrics.steppedSliderPosition(
      index: 0, stepCount: 6, containerWidth: containerWidth)
    let lastPosition = SettingsControlMetrics.steppedSliderPosition(
      index: 5, stepCount: 6, containerWidth: containerWidth)

    XCTAssertEqual(firstPosition - thumbRadius, 0)
    XCTAssertEqual(lastPosition + thumbRadius, containerWidth)
  }

  func testSteppedSliderMapsInsetTrackToFirstAndLastSteps() {
    let containerWidth: CGFloat = 200
    let firstPosition = SettingsControlMetrics.steppedSliderPosition(
      index: 0, stepCount: 6, containerWidth: containerWidth)
    let lastPosition = SettingsControlMetrics.steppedSliderPosition(
      index: 5, stepCount: 6, containerWidth: containerWidth)

    XCTAssertEqual(
      SettingsControlMetrics.steppedSliderIndex(
        locationX: firstPosition, stepCount: 6, containerWidth: containerWidth), 0)
    XCTAssertEqual(
      SettingsControlMetrics.steppedSliderIndex(
        locationX: lastPosition, stepCount: 6, containerWidth: containerWidth), 5)
  }

}
