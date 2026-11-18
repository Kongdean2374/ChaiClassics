import XCTest
@testable import ChaiCore

final class V030ArcadeTests: XCTestCase {
    func testSnakeOpensSlowerAndSpeedsUpWhenItEats() throws {
        let initial = SnakeBoard(size: 20, seed: 3)
        XCTAssertGreaterThan(initial.stepInterval(difficulty: .hard), 0.18)
        XCTAssertGreaterThan(initial.stepInterval(difficulty: .normal), initial.stepInterval(difficulty: .hard))
        XCTAssertGreaterThan(initial.stepInterval(difficulty: .easy), initial.stepInterval(difficulty: .normal))
        var fed = try v030Fixture(initial, ["food": initial.body[0] + 1])
        XCTAssertTrue(fed.step())
        XCTAssertEqual(fed.score, 1)
        for difficulty in DuelDifficulty.allCases {
            let change = initial.stepInterval(difficulty: difficulty) - fed.stepInterval(difficulty: difficulty)
            XCTAssertGreaterThan(change, 0)
            XCTAssertLessThan(change, 0.025, "One food should not cause a large speed jump.")
        }
    }
    func testSnakeFoodBodyReversalQueueWallsAndRoundTrip() throws {
        var board = SnakeBoard(size:16,seed:7); XCTAssertTrue(board.isValidSave)
        XCTAssertFalse(board.turn(.left)); XCTAssertTrue(board.turn(.up)); XCTAssertTrue(board.turn(.left)); XCTAssertFalse(board.turn(.down))
        XCTAssertTrue(board.step()); XCTAssertEqual(board.direction,.up); XCTAssertTrue(board.step()); XCTAssertEqual(board.direction,.left)
        for _ in 0..<20 where !board.hasLost { XCTAssertTrue(board.step()); XCTAssertTrue(board.isValidSave) }
        XCTAssertTrue(board.hasLost); XCTAssertFalse(board.step()); XCTAssertFalse(board.turn(.up))
        XCTAssertEqual(try JSONDecoder().decode(SnakeBoard.self,from:JSONEncoder().encode(board)),board)
    }
    func testSnakeEatGrowsOnceAndNeverSpawnsFoodInsideBody() throws {
        for seed in 0..<50 {
            var board = SnakeBoard(size:16,seed:UInt64(seed)); let head = board.body[0]
            board = try v030Fixture(board,["food":head+1]); XCTAssertTrue(board.step()); XCTAssertEqual(board.body.count,4); XCTAssertEqual(board.score,1)
            XCTAssertFalse(board.body.contains(try XCTUnwrap(board.food))); XCTAssertTrue(board.isValidSave)
        }
    }
    func testFallingBagsRotationHoldHardDropAndTerminalCollision() throws {
        var board = FallingBlocksBoard(seed:22); XCTAssertTrue(board.isValidSave)
        XCTAssertEqual(Set([board.active]+board.next.prefix(6)),Set(0...6))
        let active = board.active; XCTAssertTrue(board.hold()); XCTAssertEqual(board.held,active); XCTAssertFalse(board.hold())
        for _ in 0..<100 where !board.hasLost { XCTAssertTrue(board.hardDrop()); XCTAssertTrue(board.isValidSave) }
        XCTAssertTrue(board.hasLost); XCTAssertFalse(board.hardDrop()); XCTAssertFalse(board.move(1)); XCTAssertFalse(board.rotate())
        XCTAssertEqual(try JSONDecoder().decode(FallingBlocksBoard.self,from:JSONEncoder().encode(board)),board)
    }
    func testFallingFourLineClearAndNoOverlappingOccupiedCells() throws {
        var board = FallingBlocksBoard(seed:4), cells = Array(repeating:0,count:200)
        for row in 16..<20 { for col in 0..<10 where col != 5 { cells[row*10+col] = 2 } }
        board = try v030Fixture(board,["cells":cells,"active":0,"rotation":1,"x":3,"y":0])
        XCTAssertTrue(board.isValidSave); XCTAssertTrue(board.hardDrop()); XCTAssertEqual(board.lines,4); XCTAssertEqual(board.score,800+32)
        XCTAssertEqual(board.cells.filter{$0 != 0}.count,0); XCTAssertTrue(board.isValidSave)
    }
    func testFallingWallKicksAndIllegalMoveAreAtomic() throws {
        var board = FallingBlocksBoard(seed:9)
        board = try v030Fixture(board,["active":2,"rotation":0,"x":0,"y":5]); XCTAssertTrue(board.isValidSave)
        XCTAssertFalse(board.move(-1)); let old = board.cells; XCTAssertTrue(board.rotate()); XCTAssertEqual(board.cells,old); XCTAssertTrue(board.isValidSave)
        XCTAssertFalse(board.move(9))
    }
    func testBrickPaddleLaunchSubstepsAndNoBackgroundJump() throws {
        var board = BrickBreakerBoard(seed:1); XCTAssertTrue(board.isValidSave); XCTAssertTrue(board.movePaddle(to:100)); XCTAssertEqual(board.paddle,0.88)
        XCTAssertFalse(board.movePaddle(to:.nan)); XCTAssertTrue(board.launch()); XCTAssertFalse(board.launch())
        let old = board; XCTAssertFalse(board.advance(5)); XCTAssertFalse(board.advance(.nan)); XCTAssertEqual(board,old)
        for _ in 0..<600 { _ = board.advance(1.0/120); XCTAssertTrue(board.isValidSave) }
        XCTAssertGreaterThan(board.score,0); XCTAssertEqual(try JSONDecoder().decode(BrickBreakerBoard.self,from:JSONEncoder().encode(board)),board)
    }
    func testBrickPaddleReflectsAndEachMissCostsExactlyOneLife() throws {
        var board = BrickBreakerBoard(seed:8)
        board = try v030Fixture(board,["ballX":0.5,"ballY":0.88,"velocityX":0.0,"velocityY":0.43,"launched":true])
        XCTAssertTrue(board.advance(0.05)); XCTAssertLessThan(board.velocityY,0); XCTAssertEqual(board.lives,3)
        for life in (0...2).reversed() {
            board = try v030Fixture(board,["ballX":0.02,"ballY":1.01,"velocityX":0.0,"velocityY":0.43,"launched":true])
            XCTAssertTrue(board.advance(0.05)); XCTAssertEqual(board.lives,life); XCTAssertFalse(board.launched)
        }
        XCTAssertTrue(board.hasLost); XCTAssertFalse(board.launch()); XCTAssertFalse(board.advance(0.05))
    }
}
