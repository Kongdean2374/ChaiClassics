import XCTest
@testable import ChaiCore

final class ContinueActivationTests: XCTestCase {
    func testTapAndSmallFingerJitterRemainActionable() {
        var gate = ContinueActivationGate(); gate.begin(1); gate.move(1,travel:4)
        XCTAssertTrue(gate.allowsActivation(at:10)); gate.end(1,at:10); XCTAssertTrue(gate.allowsActivation(at:10))
    }
    func testLeftRightVerticalAndReversedSwipeCannotBecomeTapOnRelease() {
        for distance in [8.0,20,90,300] {
            var gate = ContinueActivationGate(); gate.begin(1); gate.move(1,travel:distance)
            XCTAssertFalse(gate.allowsActivation(at:10)); gate.move(1,travel:0)
            XCTAssertFalse(gate.allowsActivation(at:10)); gate.end(1,at:10)
            XCTAssertFalse(gate.allowsActivation(at:10)); XCTAssertFalse(gate.allowsActivation(at:10.34)); XCTAssertTrue(gate.allowsActivation(at:10.36))
        }
    }
    func testNativeRecognizerCancellationAndMultipleContactsDoNotLeakClick() {
        var gate = ContinueActivationGate(); gate.begin(1); gate.begin(2)
        XCTAssertFalse(gate.allowsActivation(at:10)); gate.end(1,at:10); XCTAssertFalse(gate.allowsActivation(at:11))
        gate.end(2,at:11,cancelled:true); XCTAssertFalse(gate.allowsActivation(at:11)); XCTAssertTrue(gate.allowsActivation(at:12))
    }
    func testModalSuspensionRejectsQueuedContinueAndRequiresFreshTapAfterCancel() {
        var gate = ContinueActivationGate(); gate.suspend(); XCTAssertFalse(gate.allowsActivation(at:100))
        gate.resume(at:100); XCTAssertFalse(gate.allowsActivation(at:100)); gate.begin(2)
        XCTAssertFalse(gate.allowsActivation(at:100.1)); gate.end(2,at:100.1); XCTAssertTrue(gate.allowsActivation(at:101))
    }
    func testCancelledNavigationResetsContactsAndInvalidTimeNeverActivates() {
        var gate = ContinueActivationGate(); gate.begin(1); gate.move(1,travel:.nan); XCTAssertFalse(gate.allowsActivation(at:100))
        gate.cancelAll(at:100); XCTAssertFalse(gate.allowsActivation(at:.nan)); XCTAssertFalse(gate.allowsActivation(at:100)); XCTAssertTrue(gate.allowsActivation(at:101))
    }
}
