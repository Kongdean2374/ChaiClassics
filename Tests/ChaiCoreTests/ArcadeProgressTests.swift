import XCTest
@testable import ChaiCore

final class ArcadeProgressTests: XCTestCase {
    func testTimerOnlyWriteReproducesOldFreezeAndRetainsGameplayOwnership() throws {
        let saved = try XCTUnwrap(ExpandedGameSave(game:.snake,seed:42))
        var clockWrite = saved; clockWrite.elapsedSeconds = 1
        // The former whole-value guard stopped the display clock at this point.
        XCTAssertNotEqual(saved,clockWrite)
        let id = UUID()
        XCTAssertTrue(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:id,expected:saved,current:clockWrite))
        if case .snake(let before) = saved.state,case .snake(let after) = clockWrite.state { XCTAssertEqual(before,after) }
        else { XCTFail("Expected the actual Snake engine.") }
    }

    func testSnakeKeepsMovingAcrossTenTimerWritesAt60And120Hz() throws {
        for fps in [60,120] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:directory) }
            let store = try SaveStore(directory:directory), id = UUID()
            var current = try XCTUnwrap(ExpandedGameSave(game:.snake,seed:42)), expected = current, local = current
            var accumulated = 0.0, timerOnlyDifferences = 0
            for frame in 1...(fps*10) {
                if frame % fps == 0 {
                    current.elapsedSeconds += 1
                    if current != expected { timerOnlyDifferences += 1 }
                }
                XCTAssertTrue(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:id,expected:expected,current:current))
                accumulated += 1/Double(fps)
                guard case .snake(var board) = local.state else { return XCTFail("Expected Snake.") }
                let interval = board.stepInterval(difficulty: local.difficulty)
                while accumulated >= interval {
                    let x = board.body[0]%board.size, y = board.body[0]/board.size
                    switch board.direction {
                    case .right: if x == board.size-2 { _ = board.turn(.down) }
                    case .down: if y == board.size-2 { _ = board.turn(.left) }
                    case .left: if x == 1 { _ = board.turn(.up) }
                    case .up: if y == 1 { _ = board.turn(.right) }
                    }
                    XCTAssertTrue(board.step()); accumulated -= interval
                }
                XCTAssertFalse(board.hasLost); local.state = .snake(board)
                if frame % (fps/4) == 0 {
                    local.elapsedSeconds = max(local.elapsedSeconds,current.elapsedSeconds)
                    try store.save(local,namespace:"snake")
                    current = try XCTUnwrap(store.load(ExpandedGameSave.self,namespace:"snake")); expected = current
                }
            }
            XCTAssertEqual(timerOnlyDifferences,10);XCTAssertEqual(current.elapsedSeconds,10)
            guard case .snake(let board) = current.state else { return XCTFail("Expected persisted Snake.") }
            XCTAssertGreaterThan(board.ticks,35);XCTAssertTrue(board.isValidSave)
        }
    }

    func testDeletedRestartedOrActuallyChangedProgressCannotBeOverwritten() throws {
        let id = UUID(), saved = try XCTUnwrap(ExpandedGameSave(game:.snake,seed:42))
        XCTAssertFalse(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:nil,expected:saved,current:nil))
        XCTAssertFalse(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:UUID(),expected:saved,current:saved))
        var changed = saved
        if case .snake(var board) = changed.state { XCTAssertTrue(board.turn(.up)); changed.state = .snake(board) }
        XCTAssertFalse(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:id,expected:saved,current:changed))
        let newDeal = try XCTUnwrap(ExpandedGameSave(game:.snake,seed:43))
        XCTAssertFalse(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:id,expected:saved,current:newDeal))
    }

    func testClockOnlyUpdatesAlsoKeepFallingBlocksAndBrickBreakerRunning() throws {
        for game in [GameID.fallingBlocks,.brickBreaker] {
            let id = UUID(), saved = try XCTUnwrap(ExpandedGameSave(game:game,seed:8))
            var timed = saved; timed.elapsedSeconds = 12
            XCTAssertTrue(ArcadeSaveOwnership.matches(expectedSessionID:id,currentSessionID:id,expected:saved,current:timed))
            timed.elapsedSeconds = 0
            XCTAssertEqual(try JSONDecoder().decode(ExpandedGameSave.self,from:JSONEncoder().encode(timed)),saved)
        }
    }
}
