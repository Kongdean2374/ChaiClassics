import XCTest
@testable import ChaiCore

final class TicTacToeInputTests: XCTestCase {
    func testEveryOtherCellRejectsHumanInputDuringAIThenReopensAfterRealReply() throws {
        var board = TicTacToeBoard(mode: .singlePlayer, difficulty: .normal, humanPlayer: .first, seed: 21)
        XCTAssertTrue(board.canHumanPlay(at: 0, active: true))
        XCTAssertTrue(board.play(at: 0, by: board.humanPlayer))
        let awaitingComputer = board
        XCTAssertTrue(board.isComputerTurn)
        for index in 1..<9 {
            XCTAssertFalse(board.canHumanPlay(at: index, active: true))
            XCTAssertFalse(board.play(at: index, by: board.humanPlayer))
        }
        XCTAssertEqual(board, awaitingComputer)
        let reply = try XCTUnwrap(board.computerMove())
        XCTAssertTrue(board.play(at: reply, by: board.currentPlayer))
        XCTAssertEqual(board.moves, 2)
        for index in 0..<9 {
            XCTAssertEqual(board.canHumanPlay(at: index, active: true), board.cells[index] == nil)
        }
    }

    func testInactivePauseAndComputerFirstRejectAllCellsWithoutChangingBoard() throws {
        let humanFirst = TicTacToeBoard(mode: .singlePlayer, humanPlayer: .first, seed: 22)
        for index in 0..<9 { XCTAssertFalse(humanFirst.canHumanPlay(at: index, active: false)) }
        var computerFirst = TicTacToeBoard(mode: .singlePlayer, difficulty: .normal, humanPlayer: .second, seed: 23)
        for index in 0..<9 {
            XCTAssertFalse(computerFirst.canHumanPlay(at: index, active: true))
            XCTAssertFalse(computerFirst.canHumanPlay(at: index, active: false))
        }
        XCTAssertEqual(computerFirst.moves, 0)
        let reply = try XCTUnwrap(computerFirst.computerMove())
        XCTAssertTrue(computerFirst.play(at: reply, by: .first))
        for index in 0..<9 where computerFirst.cells[index] == nil {
            XCTAssertTrue(computerFirst.canHumanPlay(at: index, active: true))
            XCTAssertFalse(computerFirst.canHumanPlay(at: index, active: false))
        }
    }

    func testLocalBothPlayersUseCurrentTurnButRejectOccupiedAndOutOfRange() {
        var board = TicTacToeBoard(mode: .localTwoPlayer, humanPlayer: .second, seed: 24)
        XCTAssertTrue(board.canHumanPlay(at: 0, active: true))
        XCTAssertTrue(board.play(at: 0, by: .first))
        XCTAssertFalse(board.canHumanPlay(at: 0, active: true))
        XCTAssertTrue(board.canHumanPlay(at: 1, active: true))
        XCTAssertTrue(board.play(at: 1, by: .second))
        XCTAssertTrue(board.canHumanPlay(at: 2, active: true))
        for index in [-1, 9, Int.min, Int.max] {
            XCTAssertFalse(board.canHumanPlay(at: index, active: true))
        }
        for index in 0..<9 { XCTAssertFalse(board.canHumanPlay(at: index, active: false)) }
    }

    func testWonAndDrawnRoundsRejectAllHumanInput() {
        for history in [[0, 3, 1, 4, 2], [0, 1, 2, 4, 3, 5, 7, 6, 8]] {
            var board = TicTacToeBoard(mode: .localTwoPlayer, seed: 25)
            for index in history { XCTAssertTrue(board.play(at: index, by: board.currentPlayer)) }
            XCTAssertTrue(board.isFinished)
            let finished = board
            for index in 0..<9 {
                XCTAssertFalse(board.canHumanPlay(at: index, active: true))
                XCTAssertFalse(board.canHumanPlay(at: index, active: false))
            }
            XCTAssertEqual(board, finished)
        }
    }
}
