import XCTest
@testable import ChaiCore

final class ConnectFourTests: XCTestCase {
    private let drawHistory = [1, 4, 6, 6, 6, 0, 2, 0, 3, 6, 3, 3, 5, 3, 6, 1, 0, 3, 0, 4, 3, 5, 0, 6, 5, 2, 2, 5, 1, 2, 2, 0, 2, 5, 4, 5, 4, 4, 4, 1, 1, 1]

    private func board(_ columns: [Int], difficulty: DuelDifficulty = .normal,
                       mode: DuelMode = .localTwoPlayer, human: DuelPlayer = .first, seed: UInt64 = 17,
                       file: StaticString = #filePath, line: UInt = #line) -> ConnectFourBoard {
        var result = ConnectFourBoard(mode: mode, difficulty: difficulty, humanPlayer: human, seed: seed)
        for column in columns { XCTAssertTrue(result.drop(in: column, player: result.currentPlayer), file: file, line: line) }
        return result
    }

    func testGravityTurnOrderFullColumnAndBoundaries() {
        var game = board([])
        let original = game
        XCTAssertFalse(game.drop(in: 0, player: .second))
        XCTAssertFalse(game.drop(in: -1, player: .first))
        XCTAssertFalse(game.drop(in: 7, player: .first))
        XCTAssertEqual(game, original)
        for row in (0..<6).reversed() {
            let player = game.currentPlayer
            XCTAssertTrue(game.drop(in: 0, player: player))
            XCTAssertEqual(game.cells[row * 7], player)
            XCTAssertEqual(game.cells.compactMap { $0 }.count, 6 - row)
        }
        XCTAssertFalse(game.canDrop(in: 0))
        let fullColumn = game
        XCTAssertFalse(game.drop(in: 0, player: game.currentPlayer))
        XCTAssertEqual(game, fullColumn)
        XCTAssertTrue(game.canDrop(in: 1))
        XCTAssertTrue(game.isValidSave)
    }

    func testHorizontalVerticalAndBothDiagonalWins() {
        let diagonal = [0, 1, 1, 2, 4, 2, 2, 3, 4, 3, 5, 3, 3]
        let cases: [([Int], Set<Int>)] = [
            ([0, 6, 1, 6, 2, 5, 3], Set([35, 36, 37, 38])),
            ([0, 1, 0, 1, 0, 2, 0], Set([14, 21, 28, 35])),
            (diagonal, Set([35, 29, 23, 17])),
            (diagonal.map { 6 - $0 }, Set([41, 33, 25, 17]))
        ]
        for (history, line) in cases {
            var game = board(history)
            XCTAssertEqual(game.winner, .first, "history: \(history)")
            XCTAssertEqual(Set(game.winningLine), line)
            XCTAssertTrue(game.isFinished)
            XCTAssertFalse(game.isDraw)
            XCTAssertTrue(game.isValidSave)
            let finished = game
            for column in 0..<7 {
                XCTAssertFalse(game.drop(in: column, player: game.currentPlayer))
                XCTAssertFalse(game.canDrop(in: column))
            }
            XCTAssertEqual(game, finished)
            XCTAssertNil(game.recommendedMove())
        }
    }

    func testSecondPlayerCanWinAndRecordsUseCorrectPerspective() {
        let history = [6, 0, 6, 1, 5, 2, 5, 3]
        let local = board(history)
        XCTAssertEqual(local.winner, .second)
        XCTAssertEqual(local.statistics.losses, 1)
        let humanSecond = board(history, mode: .singlePlayer, human: .second)
        XCTAssertEqual(humanSecond.statistics.wins, 1)
        XCTAssertEqual(humanSecond.statistics.losses, 0)
    }

    func testFullBoardDrawAndTerminalInput() {
        var game = board(drawHistory)
        XCTAssertEqual(game.moves, 42)
        XCTAssertTrue(game.isFinished)
        XCTAssertTrue(game.isDraw)
        XCTAssertNil(game.winner)
        XCTAssertTrue(game.winningLine.isEmpty)
        XCTAssertEqual(game.statistics.draws, 1)
        XCTAssertTrue(game.isValidSave)
        XCTAssertFalse(game.drop(in: 0, player: game.currentPlayer))
        XCTAssertNil(game.recommendedMove())
    }

    func testNormalAndHardTakeImmediateWinBlockAndPreferWin() {
        for difficulty in [DuelDifficulty.normal, .hard] {
            XCTAssertEqual(board([0, 6, 1, 6, 2, 5], difficulty: difficulty).recommendedMove(), 3)
            XCTAssertEqual(board([6, 0, 6, 1, 5, 2], difficulty: difficulty).recommendedMove(), 3)
            XCTAssertEqual(board([0, 6, 1, 6, 2, 6], difficulty: difficulty).recommendedMove(), 3)
        }
    }

    func testSeededAIIsRepeatableAndAllDifficultiesOnlyUseLegalColumns() {
        let history = [0, 0, 0, 0, 0, 0, 1, 2]
        for difficulty in DuelDifficulty.allCases {
            let first = board(history, difficulty: difficulty, seed: 129)
            let second = board(history, difficulty: difficulty, seed: 129)
            XCTAssertEqual(first.analyzeMove(), second.analyzeMove())
            guard let move = first.recommendedMove() else { return XCTFail("Live game needs a legal AI move") }
            XCTAssertTrue(first.canDrop(in: move))
            XCTAssertNotEqual(move, 0)
        }
        let choices = Set((0..<40).compactMap { seed in board([], difficulty: .easy, seed: UInt64(seed)).recommendedMove() })
        XCTAssertGreaterThan(choices.count, 1, "Easy must use the injected RNG")
    }

    func testMeaningfulDifficultyAndHardSearchBudgetAndPerformance() {
        let easy = board([], difficulty: .easy).analyzeMove()
        let normal = board([], difficulty: .normal).analyzeMove()
        let started = Date()
        let hard = board([], difficulty: .hard).analyzeMove()
        XCTAssertEqual(easy.visitedNodes, 0)
        XCTAssertGreaterThan(normal.visitedNodes, 0)
        XCTAssertGreaterThan(hard.visitedNodes, normal.visitedNodes)
        XCTAssertLessThanOrEqual(hard.visitedNodes, ConnectFourBoard.maximumAINodes)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "The bounded AI must remain usable on a debug test runner")
        XCTAssertNotNil(hard.column)
    }

    func testRandomGamesPreserveGravityValidityAndStopExactlyAtResult() {
        for seed in 0..<100 {
            var game = ConnectFourBoard(mode: .localTwoPlayer, difficulty: .easy, seed: UInt64(seed))
            while !game.isFinished {
                guard let column = game.recommendedMove() else { return XCTFail("Missing move for seed \(seed)") }
                XCTAssertTrue(game.drop(in: column, player: game.currentPlayer))
                XCTAssertTrue(game.isValidSave)
                for col in 0..<7 {
                    var foundDisc = false
                    for row in 0..<6 {
                        if game.cells[row * 7 + col] != nil { foundDisc = true }
                        else { XCTAssertFalse(foundDisc, "A disc cannot float above an empty slot") }
                    }
                }
            }
            XCTAssertLessThanOrEqual(game.moves, 42)
            XCTAssertEqual(game.statistics.wins + game.statistics.draws + game.statistics.losses, 1)
        }
    }

    func testRestartNewConfigurationAndClearRecords() {
        var game = board([0, 6, 1, 6, 2, 5, 3])
        game.elapsedSeconds = 73
        XCTAssertEqual(game.statistics.wins, 1)
        game.restart()
        XCTAssertTrue(game.history.isEmpty)
        XCTAssertEqual(game.elapsedSeconds, 0)
        XCTAssertEqual(game.statistics.wins, 1)
        var next = game.newRound(mode: .singlePlayer, difficulty: .hard, humanPlayer: .second, seed: 98)
        XCTAssertEqual(next.mode, .singlePlayer)
        XCTAssertEqual(next.difficulty, .hard)
        XCTAssertEqual(next.humanPlayer, .second)
        XCTAssertEqual(next.seed, 98)
        XCTAssertTrue(next.isComputerTurn)
        XCTAssertEqual(next.statistics.wins, 1)
        next.clearStatistics()
        XCTAssertEqual(next.statistics, DuelStatistics())
        XCTAssertTrue(next.isValidSave)

        var finished = board([0, 6, 1, 6, 2, 5, 3])
        finished.clearStatistics()
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.statistics, DuelStatistics())
        finished.restart()
        XCTAssertEqual(finished.statistics, DuelStatistics())
    }

    func testCodableAndSaveStoreRoundTripsKeepBoardConfigurationAndRecords() throws {
        var game = board([0, 6, 1, 6, 2, 5, 3], difficulty: .hard, mode: .singlePlayer, human: .second)
        game.restart()
        XCTAssertTrue(game.drop(in: 4, player: .first))
        game.elapsedSeconds = 64
        let encoded = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(ConnectFourBoard.self, from: encoded)
        XCTAssertEqual(decoded, game)
        XCTAssertTrue(decoded.isValidSave)
        XCTAssertEqual(decoded.statistics.losses, 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaveStore(directory: directory)
        try store.save(game, namespace: "connectfour")
        let loaded = try SaveStore(directory: directory).load(ConnectFourBoard.self, namespace: "connectfour")
        XCTAssertEqual(loaded, game)
        XCTAssertEqual(loaded?.history, [4])
    }

    private func tampered(_ game: ConnectFourBoard, _ change: (inout [String: Any]) -> Void) throws -> ConnectFourBoard {
        let data = try JSONEncoder().encode(game)
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&dictionary)
        return try JSONDecoder().decode(ConnectFourBoard.self, from: JSONSerialization.data(withJSONObject: dictionary))
    }

    func testCorruptAndImpossibleSaveHistoriesAreRejectedWithoutCrash() throws {
        let initial = board([])
        for history in [[-1], [7], Array(repeating: 0, count: 7), [0, 6, 1, 6, 2, 5, 3, 4], Array(repeating: 0, count: 43)] {
            let corrupt = try tampered(initial) { $0["history"] = history }
            XCTAssertFalse(corrupt.isValidSave)
            XCTAssertEqual(corrupt.cells.count, 42)
            XCTAssertNil(corrupt.recommendedMove())
            var copy = corrupt
            XCTAssertFalse(copy.drop(in: 1, player: copy.currentPlayer))
        }
        XCTAssertFalse(try tampered(initial) { $0["elapsedSeconds"] = -1 }.isValidSave)
        XCTAssertFalse(try tampered(initial) { $0["elapsedSeconds"] = Int.max }.isValidSave)
        XCTAssertFalse(try tampered(initial) {
            $0["completedRounds"] = [["history": [0], "perspective": 1]]
        }.isValidSave)
        XCTAssertThrowsError(try tampered(initial) { $0["mode"] = "online" })
        XCTAssertThrowsError(try tampered(initial) { $0["humanPlayer"] = 0 })
    }

    func testSavedWinningClaimCannotReplaceReplayEvidence() throws {
        let game = board([0, 1])
        let claimedWinner = try tampered(game) {
            $0["winner"] = 1
            $0["winningLine"] = [35, 36, 37, 38]
            $0["statistics"] = ["wins": 100, "draws": 0, "losses": 0]
        }
        XCTAssertTrue(claimedWinner.isValidSave)
        XCTAssertNil(claimedWinner.winner)
        XCTAssertFalse(claimedWinner.isFinished)
        XCTAssertTrue(claimedWinner.winningLine.isEmpty)
        XCTAssertEqual(claimedWinner.statistics, DuelStatistics())
    }
}
