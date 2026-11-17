import XCTest
@testable import ChaiCore

final class ConnectFourPresentationTests: XCTestCase {
    func testEveryDestinationRowFollowsGravityIncludingRestoredPositions() throws {
        var board = ConnectFourBoard(mode: .localTwoPlayer, seed: 1)
        var presentation = ConnectFourPresentation()
        for expectedRow in (0..<6).reversed() {
            let before = try JSONDecoder().decode(ConnectFourBoard.self, from: JSONEncoder().encode(board))
            XCTAssertTrue(board.drop(in: 3, player: board.currentPlayer))
            let drop = try XCTUnwrap(presentation.begin(before: before, after: board))
            XCTAssertEqual(drop.row, expectedRow)
            XCTAssertEqual(drop.column, 3)
            XCTAssertEqual(drop.player, before.currentPlayer)
            XCTAssertEqual(drop.history, board.history)
            XCTAssertTrue(presentation.isDropping)
            XCTAssertTrue(presentation.settle(id: drop.id))
            XCTAssertFalse(presentation.isDropping)
        }
        XCTAssertFalse(board.canDrop(in: 3))
    }

    func testSecondDropCannotStartUntilFirstSettlesAndStaleCompletionsAreRejected() throws {
        let initial = ConnectFourBoard(mode: .localTwoPlayer, seed: 2)
        var firstBoard = initial
        XCTAssertTrue(firstBoard.drop(in: 0, player: .first))
        var secondBoard = firstBoard
        XCTAssertTrue(secondBoard.drop(in: 1, player: .second))
        var presentation = ConnectFourPresentation()
        let first = try XCTUnwrap(presentation.begin(before: initial, after: firstBoard))
        XCTAssertNil(presentation.begin(before: firstBoard, after: secondBoard))
        XCTAssertFalse(presentation.settle(id: first.id &+ 1))
        XCTAssertTrue(presentation.isDropping)
        XCTAssertTrue(presentation.settle(id: first.id))
        let second = try XCTUnwrap(presentation.begin(before: firstBoard, after: secondBoard))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(presentation.settle(id: first.id))
        XCTAssertEqual(presentation.drop, second)
    }

    func testPauseOrNavigationCancellationKeepsAcceptedSavedMoveAndRejectsOldCallback() throws {
        let before = ConnectFourBoard(mode: .singlePlayer, humanPlayer: .first, seed: 3)
        var saved = before
        XCTAssertTrue(saved.drop(in: 5, player: .first))
        var presentation = ConnectFourPresentation()
        let first = try XCTUnwrap(presentation.begin(before: before, after: saved))
        presentation.cancel()
        XCTAssertFalse(presentation.isDropping)
        XCTAssertFalse(presentation.settle(id: first.id))
        XCTAssertEqual(saved.history, [5])
        XCTAssertEqual(saved.cells[40], .first)
        XCTAssertTrue(saved.isComputerTurn)
        XCTAssertTrue(saved.isValidSave)
        // A later move uses a fresh token even if an older animation finishes then.
        var later = saved
        XCTAssertTrue(later.drop(in: 5, player: .second))
        let next = try XCTUnwrap(presentation.begin(before: saved, after: later))
        XCTAssertFalse(presentation.settle(id: first.id))
        XCTAssertEqual(presentation.drop, next)
    }

    func testInvalidRoundChangesAndNonMovesCannotBecomeVisualDrops() {
        let before = ConnectFourBoard(mode: .localTwoPlayer, seed: 4)
        var after = before
        var presentation = ConnectFourPresentation()
        XCTAssertNil(presentation.begin(before: before, after: before))
        XCTAssertTrue(after.drop(in: 0, player: .first))
        XCTAssertTrue(after.drop(in: 1, player: .second))
        XCTAssertNil(presentation.begin(before: before, after: after))
        let changed = after.newRound(mode: .singlePlayer, difficulty: .hard, humanPlayer: .second, seed: 7)
        XCTAssertNil(presentation.begin(before: before, after: changed))
        var unrelated = ConnectFourBoard(mode: .singlePlayer, seed: 4)
        XCTAssertTrue(unrelated.drop(in: 0, player: .first))
        XCTAssertNil(presentation.begin(before: before, after: unrelated))
        XCTAssertFalse(presentation.isDropping)
    }
}
