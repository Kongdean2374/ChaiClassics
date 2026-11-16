import XCTest
@testable import ChaiCore

final class MinesweeperTests: XCTestCase {
    func testSeededBoardsAndFirstClickSafety() throws {
        for config in [MineConfiguration.easy, .medium, .hard, try MineConfiguration(width: 5, height: 5, mines: 24)] {
            for seed in UInt64(0)..<100 {
                var board = MinesweeperBoard(configuration: config, seed: seed)
                let first = Int(seed) % board.cellCount
                board.reveal(first)
                XCTAssertFalse(board.mines.contains(first))
                XCTAssertEqual(board.mines.count, config.mineCount)
                if board.cellCount - board.neighbors(first).count - 1 >= config.mineCount {
                    XCTAssertEqual(board.adjacentMines(first), 0)
                }
                for i in 0..<board.cellCount {
                    let r = i / config.width, c = i % config.width
                    let actual = board.mines.filter { abs($0 / config.width - r) <= 1 && abs($0 % config.width - c) <= 1 && $0 != i }.count
                    XCTAssertEqual(board.adjacentMines(i), actual)
                }
                XCTAssertTrue(board.isValidSave)
                let restored = try JSONDecoder().decode(MinesweeperBoard.self, from: JSONEncoder().encode(board))
                XCTAssertEqual(restored, board)
            }
        }
    }
    func testFlagsFloodVictoryAndLoss() throws {
        var board = MinesweeperBoard(configuration: .easy, seed: 23)
        board.mode = .flag; board.tap(0)
        XCTAssertEqual(board.flags, [0]); XCTAssertEqual(board.status, .ready)
        board.mode = .reveal; board.tap(0); XCTAssertEqual(board.status, .ready)
        board.toggleFlag(0); board.tap(0)
        XCTAssertGreaterThan(board.revealed.count, 1)
        let snapshot = board.mines
        let data = try JSONEncoder().encode(board)
        var restored = try JSONDecoder().decode(MinesweeperBoard.self, from: data)
        for i in 0..<restored.cellCount where !restored.mines.contains(i) { restored.reveal(i) }
        XCTAssertEqual(restored.status, .won); XCTAssertTrue(restored.isValidSave)
        restored.reveal(snapshot.first!); XCTAssertEqual(restored.status, .won)
        board.reveal(snapshot.first!); XCTAssertEqual(board.status, .lost); XCTAssertTrue(board.isValidSave)
        let end = board; board.toggleFlag(5); board.reveal(8); XCTAssertEqual(board, end)
    }
    func testCustomValidationAndEdges() throws {
        for (w,h,m) in [(0,9,1),(41,9,1),(9,41,1),(5,5,0),(5,5,25),(Int.max,5,1)] {
            XCTAssertThrowsError(try MineConfiguration(width: w, height: h, mines: m))
        }
        let board = MinesweeperBoard(configuration: .easy, seed: 1)
        XCTAssertEqual(Set(board.neighbors(0)), [1,9,10])
        XCTAssertEqual(board.neighbors(40).count, 8)
        XCTAssertTrue(board.neighbors(-1).isEmpty)
    }
}
