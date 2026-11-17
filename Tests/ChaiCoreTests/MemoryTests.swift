import XCTest
@testable import ChaiCore

final class MemoryTests: XCTestCase {
    private func pair(in board: MemoryBoard, symbol: Int = 0) -> [Int] {
        board.cards.indices.filter { board.cards[$0] == symbol }
    }

    private func mismatch(in board: MemoryBoard) -> [Int] {
        let first = board.cards.startIndex
        return [first, board.cards.indices.first { board.cards[$0] != board.cards[first] }!]
    }

    private func decoded(_ board: MemoryBoard, changing change: (inout [String: Any]) -> Void) throws -> MemoryBoard {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(board)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(MemoryBoard.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testEveryModeHasExactlyTwoOfEverySymbolAcrossOneThousandSeeds() {
        XCTAssertEqual(MemoryBoard.Mode.easy.cardCount, 16)
        XCTAssertEqual(MemoryBoard.Mode.normal.cardCount, 20)
        XCTAssertEqual(MemoryBoard.Mode.hard.cardCount, 36)
        XCTAssertEqual(MemoryBoard.symbols.count, 18)
        XCTAssertEqual(Set(MemoryBoard.symbols).count, 18)
        for seed in UInt64(0)..<1_000 {
            let mode = MemoryBoard.Mode.allCases[Int(seed % 3)]
            let board = MemoryBoard(mode: mode, seed: seed)
            XCTAssertTrue(board.isValidSave, "seed \(seed)")
            XCTAssertEqual(board.cards.count, mode.cardCount)
            for symbol in 0..<mode.pairCount { XCTAssertEqual(pair(in: board, symbol: symbol).count, 2) }
            XCTAssertFalse(board.isComplete)
            XCTAssertEqual(board.phase, .ready)
            XCTAssertTrue(board.cards.indices.allSatisfy { !board.isFaceUp($0) })
        }
    }

    func testSeedsAreReproducibleAndProductionDecksVary() {
        for mode in MemoryBoard.Mode.allCases {
            XCTAssertEqual(MemoryBoard(mode: mode, seed: 107), MemoryBoard(mode: mode, seed: 107))
            let decks = Set((0..<24).map { _ in MemoryBoard(mode: mode).cards })
            XCTAssertGreaterThan(decks.count, 1)
            let seededDecks = Set((0..<24).map { MemoryBoard(mode: mode, seed: UInt64($0)).cards })
            XCTAssertEqual(seededDecks.count, 24)
        }
    }

    func testRapidRepeatAndThirdTapsCannotChangePendingMismatch() {
        var board = MemoryBoard(seed: 9)
        let wrong = mismatch(in: board)
        XCTAssertTrue(board.select(wrong[0]))
        XCTAssertEqual(board.phase, .oneCard)
        XCTAssertEqual(board.moves, 0)
        let once = board
        for _ in 0..<100 { XCTAssertFalse(board.select(wrong[0])) }
        XCTAssertFalse(board.select(-1))
        XCTAssertFalse(board.select(board.cards.count))
        XCTAssertEqual(board, once)
        XCTAssertTrue(board.select(wrong[1]))
        XCTAssertEqual(board.phase, .mismatch)
        XCTAssertEqual(board.moves, 1)
        let pending = board
        for _ in 0..<10 {
            for index in board.cards.indices { XCTAssertFalse(board.select(index)) }
        }
        XCTAssertEqual(board, pending)
        XCTAssertTrue(board.isFaceUp(wrong[0]))
        XCTAssertTrue(board.isFaceUp(wrong[1]))
        XCTAssertFalse(board.resolveMismatch(expectedMoves: 0))
        XCTAssertFalse(board.resolveMismatch(expectedSelection: Array(wrong.reversed())))
        XCTAssertEqual(board, pending)
        XCTAssertTrue(board.resolveMismatch(expectedMoves: 1, expectedSelection: wrong))
        XCTAssertEqual(board.phase, .ready)
        XCTAssertEqual(board.moves, 1)
        XCTAssertTrue(board.selectedIndices.isEmpty)
        XCTAssertFalse(board.resolveMismatch())
    }

    func testCorrectPairsArePermanentAndDoubleTapsDoNotConsumeTurns() {
        var board = MemoryBoard(mode: .normal, seed: 23)
        let indices = pair(in: board)
        XCTAssertTrue(board.select(indices[0]))
        XCTAssertFalse(board.select(indices[0]))
        XCTAssertTrue(board.select(indices[1]))
        XCTAssertEqual(board.moves, 1)
        XCTAssertEqual(board.matchedPairCount, 1)
        XCTAssertEqual(board.phase, .ready)
        for index in indices {
            XCTAssertTrue(board.matched[index])
            XCTAssertTrue(board.isFaceUp(index))
            XCTAssertFalse(board.canSelect(index))
            XCTAssertFalse(board.select(index))
        }
        XCTAssertFalse(board.resolveMismatch())
        board.settleUnmatchedCards()
        XCTAssertEqual(board.matchedPairCount, 1)
        XCTAssertTrue(board.isValidSave)
    }

    func testPauseBackgroundAndCanceledResolutionSettleTransientState() {
        var board = MemoryBoard(seed: 12)
        board.elapsedSeconds = 37
        let good = pair(in: board)
        good.forEach { board.select($0) }
        let single = board.cards.indices.first { !board.matched[$0] }!
        board.select(single)
        board.settleUnmatchedCards()
        XCTAssertEqual(board.phase, .ready)
        XCTAssertFalse(board.isFaceUp(single))
        XCTAssertEqual(board.matchedPairCount, 1)
        let first = board.cards.indices.first { !board.matched[$0] }!
        let second = board.cards.indices.first { !board.matched[$0] && board.cards[$0] != board.cards[first] }!
        board.select(first); board.select(second)
        let previousMoves = board.moves
        let oldSelection = board.selectedIndices
        board.settleUnmatchedCards()
        XCTAssertEqual(board.phase, .ready)
        XCTAssertEqual(board.moves, previousMoves)
        XCTAssertEqual(board.elapsedSeconds, 37)
        board.select(first); board.select(second)
        let newTurn = board
        XCTAssertFalse(board.resolveMismatch(expectedMoves: previousMoves, expectedSelection: oldSelection))
        XCTAssertEqual(board, newTurn, "A delayed callback from before pause must not close the new turn")
        XCTAssertTrue(board.resolveMismatch(expectedMoves: previousMoves + 1, expectedSelection: oldSelection))
        XCTAssertTrue(board.isValidSave)
    }

    func testAllPairsWinAndRestartRetainsDeckButResetsProgress() {
        for mode in MemoryBoard.Mode.allCases {
            var board = MemoryBoard(mode: mode, seed: 20)
            let original = board
            board.elapsedSeconds = 90
            for symbol in 0..<mode.pairCount {
                for index in pair(in: board, symbol: symbol) { XCTAssertTrue(board.select(index)) }
                XCTAssertEqual(board.matchedPairCount, symbol + 1)
                XCTAssertTrue(board.isValidSave)
            }
            XCTAssertTrue(board.isComplete)
            XCTAssertEqual(board.phase, .complete)
            XCTAssertEqual(board.moves, mode.pairCount)
            let complete = board
            for index in board.cards.indices { XCTAssertFalse(board.select(index)) }
            XCTAssertFalse(board.resolveMismatch())
            XCTAssertEqual(board, complete)
            board.restart()
            XCTAssertEqual(board, original)
        }
    }

    func testSavedSelectionsMatchesMovesAndElapsedTimeRoundTrip() throws {
        var board = MemoryBoard(mode: .hard, seed: 85)
        pair(in: board).forEach { board.select($0) }
        board.elapsedSeconds = 113
        let first = board.cards.indices.first { !board.matched[$0] }!
        let second = board.cards.indices.first { !board.matched[$0] && board.cards[$0] != board.cards[first] }!
        board.select(first)
        var restored = try JSONDecoder().decode(MemoryBoard.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(restored, board)
        board.select(second)
        restored = try JSONDecoder().decode(MemoryBoard.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(restored, board)
        XCTAssertTrue(restored.isValidSave)
        XCTAssertEqual(restored.phase, .mismatch)
        restored.settleUnmatchedCards()
        XCTAssertEqual(restored.matched, board.matched)
        XCTAssertEqual(restored.moves, board.moves)
        XCTAssertEqual(restored.elapsedSeconds, 113)
        XCTAssertEqual(restored.phase, .ready)
    }

    func testMemoryNamespaceDoesNotModifyOtherGameSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaveStore(directory: directory)
        let sliding = try SlidingBoard(size: 3, difficulty: .easy, seed: 7)
        try store.save(sliding, namespace: "sliding")
        let oldData = try Data(contentsOf: directory.appendingPathComponent("sliding.json"))
        var memory = MemoryBoard(seed: 43)
        memory.select(0)
        try store.save(memory, namespace: "memory")
        XCTAssertEqual(try store.load(MemoryBoard.self, namespace: "memory"), memory)
        memory.settleUnmatchedCards()
        try store.save(memory, namespace: "memory")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("sliding.json")), oldData)
        XCTAssertEqual(try store.load(SlidingBoard.self, namespace: "sliding"), sliding)
    }

    func testCorruptCardsCountersMatchedFlagsAndSelectionAreRejected() throws {
        let board = MemoryBoard(seed: 99)
        let good = pair(in: board)
        let wrong = mismatch(in: board)
        let invalid: [(inout [String: Any]) -> Void] = [
            { $0["cards"] = Array(board.cards.dropLast()) },
            { $0["cards"] = Array(repeating: 0, count: board.cards.count) },
            { var cards = board.cards; cards[0] = -1; $0["cards"] = cards },
            { var cards = board.cards; cards[0] = 18; $0["cards"] = cards },
            { $0["mode"] = "hard" },
            { $0["matched"] = [false] },
            { var matched = board.matched; matched[good[0]] = true; $0["matched"] = matched },
            { var matched = board.matched; wrong.forEach { matched[$0] = true }; $0["matched"] = matched },
            { $0["selectedIndices"] = [-1] },
            { $0["selectedIndices"] = [board.cards.count] },
            { $0["selectedIndices"] = [0, 0] },
            { $0["selectedIndices"] = [0, 1, 2] },
            { $0["selectedIndices"] = good; $0["moves"] = 1 },
            { $0["selectedIndices"] = wrong; $0["moves"] = 0 },
            { var matched = board.matched; good.forEach { matched[$0] = true }; $0["matched"] = matched; $0["moves"] = 0 },
            { var matched = board.matched; good.forEach { matched[$0] = true }; $0["matched"] = matched; $0["moves"] = 1; $0["selectedIndices"] = [good[0]] },
            { $0["moves"] = -1 }, { $0["moves"] = Int.max },
            { $0["elapsedSeconds"] = -1 }, { $0["elapsedSeconds"] = Int.max }
        ]
        for (index, mutation) in invalid.enumerated() {
            var corrupt = try decoded(board, changing: mutation)
            XCTAssertFalse(corrupt.isValidSave, "mutation \(index)")
            XCTAssertFalse(corrupt.select(0), "Invalid data must not permit indexing or gameplay")
            XCTAssertFalse(corrupt.resolveMismatch())
        }
        XCTAssertThrowsError(try decoded(board) { $0["mode"] = "unknown-future-mode" })
        XCTAssertThrowsError(try decoded(board) { $0.removeValue(forKey: "cards") })
    }

    func testDeckGenerationPerformanceIsBounded() {
        let start = Date()
        for seed in UInt64(0)..<1_000 {
            let board = MemoryBoard(mode: .hard, seed: seed)
            XCTAssertTrue(board.isValidSave)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "One thousand largest decks should generate without expensive search")
    }
}
