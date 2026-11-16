import XCTest
@testable import ChaiCore

final class GameplayReviewTests: XCTestCase {
    func testFourDirectionalSwipesRejectOppositeDiagonalShortAndNonadjacentMoves() throws {
        var seen = Set<String>()
        for size in 3...5 {
            for seed in UInt64(0)..<30 {
                let board = try SlidingBoard(size: size, difficulty: .easy, seed: seed)
                for tile in board.tiles.indices where board.canMove(tile) {
                    let direction = try XCTUnwrap(SlidingInput.direction(tile: tile, board: board))
                    let x: Double, y: Double
                    switch direction {
                    case .left: x = -60; y = 0; seen.insert("left")
                    case .right: x = 60; y = 0; seen.insert("right")
                    case .up: x = 0; y = -60; seen.insert("up")
                    case .down: x = 0; y = 60; seen.insert("down")
                    }
                    XCTAssertTrue(SlidingInput.accepts(tile: tile, board: board, horizontal: x, vertical: y, minimumDistance: 20))
                    XCTAssertFalse(SlidingInput.accepts(tile: tile, board: board, horizontal: -x, vertical: -y, minimumDistance: 20))
                    XCTAssertFalse(SlidingInput.accepts(tile: tile, board: board, horizontal: x / 10, vertical: y / 10, minimumDistance: 20))
                    XCTAssertFalse(SlidingInput.accepts(tile: tile, board: board, horizontal: x == 0 ? 60 : x, vertical: y == 0 ? 60 : y, minimumDistance: 20))
                    var moved = board; moved.move(tile)
                    XCTAssertEqual(moved.moves, board.moves + 1); XCTAssertEqual(moved.blank, tile)
                    XCTAssertEqual(moved.tiles[board.blank], board.tiles[tile]); XCTAssertTrue(moved.isValidSave)
                    XCTAssertEqual(try JSONDecoder().decode(SlidingBoard.self, from: JSONEncoder().encode(moved)), moved)
                }
                XCTAssertFalse(SlidingInput.accepts(tile: board.blank, board: board, horizontal: 60, vertical: 0, minimumDistance: 20))
                XCTAssertFalse(SlidingInput.accepts(tile: -1, board: board, horizontal: 60, vertical: 0, minimumDistance: 20))
                XCTAssertFalse(SlidingInput.accepts(tile: 0, board: board, horizontal: .nan, vertical: .infinity, minimumDistance: 20))
            }
        }
        XCTAssertEqual(seen, ["left", "right", "up", "down"])
        let solved = """
        {"size":3,"difficulty":"easy","initialTiles":[1,2,3,4,5,6,7,0,8],"tiles":[1,2,3,4,5,6,7,8,0],"moves":1,"elapsedSeconds":0}
        """
        let board = try JSONDecoder().decode(SlidingBoard.self, from: Data(solved.utf8))
        XCTAssertNil(SlidingInput.direction(tile: 7, board: board))
    }
    func testMinesDensityEstimatesAndRandomBoardBoundaries() throws {
        XCTAssertEqual(MineConfiguration.easy.difficultyKey, "difficulty.easy")
        XCTAssertEqual(MineConfiguration.medium.difficultyKey, "difficulty.medium")
        XCTAssertEqual(MineConfiguration.hard.difficultyKey, "difficulty.hard")
        for (mines, expected) in [(13,"easy"),(14,"medium"),(18,"medium"),(19,"hard")] {
            let configuration = try MineConfiguration(width: 10, height: 10, mines: mines)
            XCTAssertEqual(configuration.difficultyKey, "difficulty." + expected)
        }
        var layouts = Set<[Int]>()
        for seed in UInt64(0)..<30 {
            var board = MinesweeperBoard(configuration: .easy, seed: seed); board.reveal(40)
            layouts.insert(board.mines.sorted())
        }
        XCTAssertGreaterThan(layouts.count, 1)
        for (width, height) in [(5,5),(5,40),(40,5),(40,40)] {
            for count in [1, width * height - 1] {
                let configuration = try MineConfiguration(width: width, height: height, mines: count)
                for first in [0, width - 1, width * (height - 1), width * height - 1, width * height / 2] {
                    var board = MinesweeperBoard(configuration: configuration, seed: UInt64(first))
                    let flag = (first + 1) % board.cellCount
                    board.mode = .flag; board.toggleFlag(flag); board.reveal(first)
                    XCTAssertFalse(board.mines.contains(first)); XCTAssertEqual(board.mines.count, count)
                    XCTAssertEqual(board.flags, [flag]); XCTAssertFalse(board.revealed.contains(flag))
                    XCTAssertTrue(board.isValidSave)
                    var reference = MinesweeperBoard(configuration: configuration, seed: UInt64(first)); reference.reveal(first)
                    XCTAssertEqual(board.mines, reference.mines)
                    XCTAssertEqual(try JSONDecoder().decode(MinesweeperBoard.self, from: JSONEncoder().encode(board)), board)
                }
            }
        }
    }
}
