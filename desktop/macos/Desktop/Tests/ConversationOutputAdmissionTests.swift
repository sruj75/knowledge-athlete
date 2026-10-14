import Foundation
import XCTest

@testable import Omi_Computer

final class ConversationOutputAdmissionTests: XCTestCase {
  func testAudioRemainsHeldUntilCanonicalTargetIsAccepted() {
    var admission = ConversationOutputAdmission(maximumBufferedBytes: 8)
    XCTAssertEqual(admission.append(Data([1, 2])), .held)
    XCTAssertEqual(admission.append(Data([3, 4])), .held)
    XCTAssertFalse(admission.isAccepted)
    XCTAssertEqual(admission.accept(), Data([1, 2, 3, 4]))
    XCTAssertEqual(admission.append(Data([5, 6])), .ready(Data([5, 6])))
  }

  func testRejectedOrOverflowedAdmissionCanNeverReleaseBufferedAudio() {
    var admission = ConversationOutputAdmission(maximumBufferedBytes: 2)
    XCTAssertEqual(admission.append(Data([1, 2])), .held)
    XCTAssertEqual(admission.append(Data([3, 4])), .rejected)
    XCTAssertNil(admission.accept())
    XCTAssertEqual(admission.append(Data([5, 6])), .rejected)
    var rejected = ConversationOutputAdmission()
    XCTAssertEqual(rejected.append(Data([7, 8])), .held)
    rejected.reject()
    XCTAssertNil(rejected.accept())
  }
}
