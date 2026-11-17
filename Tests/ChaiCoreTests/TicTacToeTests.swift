import XCTest
@testable import ChaiCore

final class TicTacToeTests: XCTestCase {
    private func position(_ moves: [Int], mode: DuelMode = .localTwoPlayer,
                          difficulty: DuelDifficulty = .hard, human: DuelPlayer = .first) -> TicTacToeBoard {
        var board = TicTacToeBoard(mode: mode, difficulty: difficulty, humanPlayer: human, seed: 2374)
        for move in moves { XCTAssertTrue(board.play(at: move, by: board.currentPlayer)) }
        return board
    }
    func testEveryWinningLineForBothPlayers() {
        let lines = [[0,1,2], [3,4,5], [6,7,8], [0,3,6], [1,4,7], [2,5,8], [0,4,8], [2,4,6]]
        for line in lines {
            let rest = (0..<9).filter { !line.contains($0) }
            let first = position([line[0],rest[0],line[1],rest[1],line[2]])
            XCTAssertEqual(first.winner, .first); XCTAssertEqual(first.winningLine, line)
            XCTAssertTrue(first.isValidSave); XCTAssertFalse(first.isDraw)
            // Select three X positions which do not themselves make a line before O wins.
            let fillers = rest.combinationsOfThree.first { chosen in !lines.contains { Set($0).isSubset(of: Set(chosen)) } }!
            let second = position([fillers[0],line[0],fillers[1],line[1],fillers[2],line[2]])
            XCTAssertEqual(second.winner, .second); XCTAssertEqual(second.winningLine, line)
            XCTAssertTrue(second.isValidSave)
        }
    }
    func testDrawAndTerminalRejection() {
        var board = position([0,1,2,4,3,5,7,6,8])
        XCTAssertTrue(board.isDraw); XCTAssertTrue(board.isFinished); XCTAssertNil(board.winner)
        let finished = board
        XCTAssertFalse(board.play(at: 0, by: board.currentPlayer)); XCTAssertEqual(board, finished)
        XCTAssertNil(board.recommendedMove()); XCTAssertEqual(board.statistics.draws, 1)
    }
    func testRejectsWrongTurnOccupiedAndOutOfBoundsWithoutMutation() {
        var board = TicTacToeBoard(mode: .localTwoPlayer, seed: 1)
        let empty = board
        XCTAssertFalse(board.play(at: 0, by: .second)); XCTAssertFalse(board.play(at: -1, by: .first))
        XCTAssertFalse(board.play(at: 9, by: .first)); XCTAssertEqual(board, empty)
        XCTAssertTrue(board.play(at: 0, by: .first)); let once = board
        XCTAssertFalse(board.play(at: 0, by: .second)); XCTAssertFalse(board.play(at: 1, by: .first)); XCTAssertEqual(board, once)
        var won = position([0,3,1,4,2]); let terminal = won
        XCTAssertFalse(won.play(at: 8, by: .second)); XCTAssertEqual(won, terminal)
    }
    func testNormalAndHardWinAndBlock() {
        for level in [DuelDifficulty.normal, .hard] {
            let win = position([0,3,1,4], mode: .singlePlayer, difficulty: level, human: .second)
            XCTAssertEqual(win.computerMove(), 2)
            let block = position([0,4,1], mode: .singlePlayer, difficulty: level)
            XCTAssertEqual(block.computerMove(), 2)
        }
    }
    func testSeededDifficultyAndTurnGating() {
        let a = position([], mode: .singlePlayer, difficulty: .easy, human: .second)
        XCTAssertEqual(a.computerMove(), a.computerMove())
        XCTAssertEqual(a.recommendedMove(seed: 52), a.recommendedMove(seed: 52))
        XCTAssertGreaterThan(Set((1...30).compactMap { a.recommendedMove(seed: UInt64($0)) }).count, 4)
        XCTAssertEqual(a.recommendedMove(difficulty: .normal), 4)
        XCTAssertNil(position([]).computerMove())
        XCTAssertNil(position([], mode: .singlePlayer, human: .first).computerMove())
        for level in DuelDifficulty.allCases {
            for seed in 0..<50 { XCTAssertTrue((0..<9).contains(a.recommendedMove(difficulty: level, seed: UInt64(seed))!)) }
        }
    }
    func testHardIsUnbeatableAgainstEveryHumanContinuationWithEitherStarter() {
        // The human branches over every legal option; the AI must never allow a human win.
        for human in DuelPlayer.allCases {
            let board = TicTacToeBoard(mode: .singlePlayer, difficulty: .hard, humanPlayer: human, seed: 42)
            var visited = Set<String>()
            func explore(_ state: TicTacToeBoard) {
                let key = state.history.map(String.init).joined(separator: ",")
                guard visited.insert(key).inserted else { return }
                if state.isFinished { XCTAssertNotEqual(state.winner, human); return }
                if state.isComputerTurn {
                    var next = state
                    guard let move = state.computerMove() else { XCTFail("Missing legal computer move"); return }
                    XCTAssertTrue(next.play(at: move, by: next.currentPlayer)); explore(next)
                } else {
                    for index in state.cells.indices where state.cells[index] == nil {
                        var next = state; XCTAssertTrue(next.play(at: index, by: next.currentPlayer)); explore(next)
                    }
                }
            }
            explore(board); XCTAssertGreaterThan(visited.count, 100)
        }
    }
    func testAllReachablePositionsValidateAndRejectPostWinMoves() {
        var seen = Set<String>()
        func visit(_ board: TicTacToeBoard) {
            let key = board.cells.map { String($0?.rawValue ?? 0) }.joined()
            guard seen.insert(key).inserted else { return }
            XCTAssertTrue(board.isValidSave)
            for index in 0..<9 {
                var next = board
                let accepted = next.play(at: index, by: next.currentPlayer)
                XCTAssertEqual(accepted, !board.isFinished && board.cells[index] == nil)
                if accepted { visit(next) }
            }
        }
        visit(TicTacToeBoard(mode: .localTwoPlayer, seed: 4)); XCTAssertEqual(seen.count, 5478)
    }
    func testRestartReplayAndChangingConfigurationPreserveClearableRecords() throws {
        var board = position([0,3,1,4,2])
        XCTAssertEqual(board.statistics.wins, 1)
        board.elapsedSeconds = 7
        let session = board.sessionID
        board.restart()
        XCTAssertEqual(board.moves, 0); XCTAssertEqual(board.elapsedSeconds, 0); XCTAssertNotEqual(board.sessionID, session)
        XCTAssertEqual(board.statistics.wins, 1); XCTAssertTrue(board.isValidSave)
        board.restart(); XCTAssertEqual(board.statistics.wins, 1)
        for move in [0,1,2,4,3,5,7,6,8] { XCTAssertTrue(board.play(at: move, by: board.currentPlayer)) }
        XCTAssertEqual(board.statistics.draws, 1)
        let next = board.newGame(mode: .singlePlayer, difficulty: .easy, humanPlayer: .second, seed: 9)
        XCTAssertEqual(next.statistics.wins, 1); XCTAssertEqual(next.statistics.draws, 1); XCTAssertTrue(next.isValidSave)
        board.clearStatistics(); XCTAssertEqual(board.statistics, DuelStatistics()); XCTAssertTrue(board.isValidSave)
        board.restart(); XCTAssertEqual(board.statistics, DuelStatistics()); XCTAssertTrue(board.isValidSave)
    }
    func testStatisticsPerspectiveAndAbandonment() {
        let loss = position([0,3,1,4,2], mode: .singlePlayer, human: .second)
        XCTAssertEqual(loss.statistics.losses, 1); XCTAssertEqual(loss.statistics.wins, 0)
        var partial = position([0,1]); partial.restart(); XCTAssertEqual(partial.statistics, DuelStatistics())
    }
    func testPersistentRoundTripsAndNamespaceIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaveStore(directory: directory)
        var board = position([0,3,1,4,2]); board.restart()
        XCTAssertTrue(board.play(at: 4, by: .first)); board.elapsedSeconds = 37
        try store.save(board, namespace: "tictactoe"); try store.save([4,5,6], namespace: "sliding")
        let reopened = try SaveStore(directory: directory)
        let loaded = try XCTUnwrap(reopened.load(TicTacToeBoard.self, namespace: "tictactoe"))
        XCTAssertEqual(loaded, board); XCTAssertTrue(loaded.isValidSave)
        XCTAssertEqual(try reopened.load([Int].self, namespace: "sliding"), [4,5,6])
    }
    func testRejectsForgedCellsHistoryElapsedAndCompletedRecords() throws {
        let base = position([0,3,1,4])
        func changed(_ update: (inout [String: Any]) -> Void) throws -> TicTacToeBoard {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
            update(&object)
            return try JSONDecoder().decode(TicTacToeBoard.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertFalse(try changed { $0["cells"] = ([1,1,1,2,2,NSNull(),NSNull(),NSNull(),NSNull()] as [Any]) }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = [0,0] }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = [0,3,1,4,2,8] }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = [-1] }.isValidSave)
        XCTAssertFalse(try changed { $0["elapsedSeconds"] = -1 }.isValidSave)
        XCTAssertFalse(try changed { $0["elapsedSeconds"] = Int.max }.isValidSave)
        let malformed = try changed { $0["cells"] = [] }
        XCTAssertFalse(malformed.isValidSave); XCTAssertNil(malformed.winner); XCTAssertEqual(malformed.winningLine, [])
        XCTAssertNil(malformed.recommendedMove())
        XCTAssertFalse(try changed { $0["completedRounds"] = [["history": [0,1], "perspective": 1]] }.isValidSave)
        XCTAssertFalse(try changed { $0["includeCurrentResult"] = false }.isValidSave)
    }
    func testHardOpeningPerformanceIsBounded() {
        let board = TicTacToeBoard(mode: .singlePlayer, difficulty: .hard, humanPlayer: .second, seed: 1)
        let start = Date(); XCTAssertNotNil(board.computerMove())
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "A full 3×3 search must remain bounded, including debug builds")
    }
}

private extension Array where Element == Int {
    var combinationsOfThree: [[Int]] {
        guard count >= 3 else { return [] }
        var result: [[Int]] = []
        for i in 0..<(count - 2) { for j in (i + 1)..<(count - 1) { for k in (j + 1)..<count { result.append([self[i],self[j],self[k]]) } } }
        return result
    }
}
