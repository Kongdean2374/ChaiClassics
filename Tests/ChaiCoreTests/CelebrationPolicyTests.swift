import XCTest
@testable import ChaiCore

final class CelebrationPolicyTests: XCTestCase {
    func testRestoringCompletedGameDoesNotCelebrate() {
        var policy = CelebrationPolicy()
        XCTAssertFalse(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
        XCTAssertFalse(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
        policy.synchronize(completed: true)
        XCTAssertFalse(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
    }
    func testOnlyOneCelebrationForEachNewCompletion() {
        var policy = CelebrationPolicy()
        policy.synchronize(completed: false)
        XCTAssertTrue(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
        for _ in 0..<20 {
            XCTAssertFalse(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
        }
        XCTAssertFalse(policy.observe(completed: false, isActive: true, reduceMotion: false, lowPower: false))
        XCTAssertTrue(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
    }
    func testSuppressedCompletionsAreNeverQueuedForLaterPlayback() {
        for (active, reduced, lowPower) in [(false, false, false), (true, true, false), (true, false, true), (false, true, true)] {
            var policy = CelebrationPolicy()
            policy.synchronize(completed: false)
            XCTAssertFalse(policy.observe(completed: true, isActive: active, reduceMotion: reduced, lowPower: lowPower))
            XCTAssertFalse(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
        }
    }
    func testFirstObservationAndBaselineResetAreNotNewCompletions() {
        var policy = CelebrationPolicy()
        XCTAssertFalse(policy.observe(completed: false, isActive: true, reduceMotion: false, lowPower: false))
        policy.synchronize(completed: true)
        XCTAssertFalse(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
        policy.synchronize(completed: false)
        XCTAssertTrue(policy.observe(completed: true, isActive: true, reduceMotion: false, lowPower: false))
    }
}
