import XCTest
@testable import ChaiCore

final class SlidingTests: XCTestCase {
    func testSeededSolvabilityAndPersistence() throws {
        for size in 3...5 {
            for difficulty in SlidingBoard.Difficulty.allCases {
                for seed in UInt64(0)..<100 {
                    let board = try SlidingBoard(size: size, difficulty: difficulty, seed: seed)
                    XCTAssertFalse(board.isComplete)
                    XCTAssertTrue(SlidingBoard.isSolvable(board.tiles, size: size))
                    XCTAssertTrue(board.isValidSave)
                    XCTAssertEqual(try JSONDecoder().decode(SlidingBoard.self, from: JSONEncoder().encode(board)), board)
                }
            }
        }
    }
    func testMoveRestrictionCompletionRestartAndRandomWalks() throws {
        for size in 3...5 {
            var board = try SlidingBoard(size: size, difficulty: .easy, seed: 42)
            let original = board
            let distant = try XCTUnwrap(board.tiles.indices.first { !board.canMove($0) })
            board.move(distant); board.move(-1); XCTAssertEqual(board, original)
            var rng = SeededRandom(seed: 777)
            for _ in 0..<200 {
                let options = board.tiles.indices.filter { board.canMove($0) }
                if let i = options.randomElement(using: &rng) { board.move(i) }
                XCTAssertTrue(board.isValidSave)
            }
            board.restart(); XCTAssertEqual(board, original)
        }
        // Decode a legitimate almost-solved saved board to exercise the terminal transition.
        let json = """
        {"size":3,"difficulty":"easy","initialTiles":[1,2,3,4,5,6,7,0,8],"tiles":[1,2,3,4,5,6,7,0,8],"moves":0,"elapsedSeconds":0}
        """
        var b = try JSONDecoder().decode(SlidingBoard.self, from: Data(json.utf8))
        b.move(8); XCTAssertTrue(b.isComplete); XCTAssertEqual(b.moves, 1)
        let won = b; b.move(7); XCTAssertEqual(won, b)
        XCTAssertFalse(SlidingBoard.isSolvable([2,1,3,4,5,6,7,8,0], size: 3))
        XCTAssertThrowsError(try SlidingBoard(size: 2, difficulty: .easy))
    }
}
