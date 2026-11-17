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

    func testRapidSecondSelectionIsAllowedButMismatchWaitsForActualSecondReveal() throws {
        var board = MemoryBoard(seed: 24)
        var presentation = MemoryTurnPresentation()
        XCTAssertTrue(board.select(0))
        XCTAssertTrue(presentation.acceptsSelection, "Opening the first card must not delay the second tap")
        XCTAssertFalse(board.select(0))
        XCTAssertTrue(board.select(1))
        let token = try XCTUnwrap(presentation.beginPair(secondCard: 1, mismatchedCards: board.selectedIndices))
        XCTAssertFalse(presentation.acceptsSelection)
        XCTAssertFalse(board.select(2))
        XCTAssertNil(presentation.remainingHold(at: 10.1))
        XCTAssertFalse(presentation.revealCompleted(card: 0, token: token, at: 10.15))
        XCTAssertEqual(presentation.phase, .revealing)
        XCTAssertTrue(presentation.revealCompleted(card: 1, token: token, at: 10.4))
        XCTAssertEqual(presentation.phase, .holding)
        XCTAssertEqual(try XCTUnwrap(presentation.remainingHold(at: 10.4)), 0.65, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(presentation.remainingHold(at: 10.7)), 0.35, accuracy: 0.000_001)
        XCTAssertFalse(presentation.beginClosing(token: token, at: 10.4 + 0.65 - 0.000_001))
        XCTAssertTrue(presentation.beginClosing(token: token, at: 10.4 + 0.65))
        XCTAssertEqual(presentation.closingCards, [0, 1])
        XCTAssertEqual(board.phase, .mismatch, "The persisted pair stays locked until closing really finishes")
        XCTAssertTrue(board.isValidSave)
        XCTAssertFalse(presentation.finishClosing(token: token))
        XCTAssertFalse(presentation.closeCompleted(card: 0, token: token))
        XCTAssertFalse(presentation.closeCompleted(card: 0, token: token))
        XCTAssertFalse(presentation.acceptsSelection)
        XCTAssertTrue(presentation.closeCompleted(card: 1, token: token))
        XCTAssertFalse(presentation.acceptsSelection, "Saving resolution is the last step before accepting input")
        XCTAssertTrue(board.resolveMismatch(expectedMoves: 1, expectedSelection: [0, 1]))
        XCTAssertTrue(presentation.finishClosing(token: token))
        XCTAssertTrue(presentation.acceptsSelection)
        XCTAssertTrue(board.select(2), "There is no extra cooldown after the pair has closed")
    }

    func testMatchingPairOnlyBlocksUntilSecondRevealCompletes() throws {
        var board = MemoryBoard(seed: 24)
        var presentation = MemoryTurnPresentation()
        XCTAssertTrue(board.select(1))
        XCTAssertTrue(board.select(3))
        XCTAssertEqual(board.matchedPairCount, 1)
        let token = try XCTUnwrap(presentation.beginPair(secondCard: 3, mismatchedCards: []))
        XCTAssertTrue(board.canSelect(2))
        XCTAssertFalse(presentation.acceptsSelection, "Even a committed match must finish its second reveal before a third tap")
        XCTAssertFalse(presentation.revealCompleted(card: 1, token: token, at: 0.1))
        XCTAssertTrue(presentation.revealCompleted(card: 3, token: token, at: 0.15))
        XCTAssertTrue(presentation.acceptsSelection)
        XCTAssertNil(presentation.remainingHold(at: 0.15))
        XCTAssertFalse(presentation.beginClosing(token: token, at: 100))
        XCTAssertTrue(board.select(2))
        XCTAssertTrue(board.isFaceUp(1))
        XCTAssertTrue(board.isFaceUp(3))
    }

    func testPauseBackgroundRestartAndDeckReplacementInvalidateEveryCompletionPhase() throws {
        for phase in 0..<3 {
            var presentation = MemoryTurnPresentation()
            let old = try XCTUnwrap(presentation.beginPair(secondCard: 1, mismatchedCards: [0, 1]))
            if phase > 0 { XCTAssertTrue(presentation.revealCompleted(card: 1, token: old, at: 1)) }
            if phase > 1 { XCTAssertTrue(presentation.beginClosing(token: old, at: 1.65)) }
            presentation.cancel()
            XCTAssertTrue(presentation.acceptsSelection)
            XCTAssertTrue(presentation.closingCards.isEmpty)
            XCTAssertNil(presentation.remainingHold(at: 5))
            let next = try XCTUnwrap(presentation.beginPair(secondCard: 1, mismatchedCards: [0, 1]))
            XCTAssertNotEqual(next, old)
            let newTurn = presentation
            XCTAssertFalse(presentation.revealCompleted(card: 1, token: old, at: 50))
            XCTAssertFalse(presentation.beginClosing(token: old, at: 50))
            XCTAssertFalse(presentation.closeCompleted(card: 0, token: old))
            XCTAssertFalse(presentation.closeCompleted(card: 1, token: old))
            XCTAssertFalse(presentation.finishClosing(token: old))
            XCTAssertEqual(presentation, newTurn, "Old animation/hold callbacks cannot mutate a new turn with the same indices")
        }
    }

    func testReducedMotionImmediateCompletionsRetainReadableHoldAndReleaseWithoutCooldown() throws {
        var presentation = MemoryTurnPresentation()
        let token = try XCTUnwrap(presentation.beginPair(secondCard: 9, mismatchedCards: [4, 9]))
        // Reduced Motion supplies reveal/close callbacks immediately, rather
        // than inserting a pretend wait for a visual rotation that did not run.
        XCTAssertTrue(presentation.revealCompleted(card: 9, token: token, at: 20))
        XCTAssertFalse(presentation.beginClosing(token: token, at: 20.649))
        XCTAssertTrue(presentation.beginClosing(token: token, at: 20.65))
        XCTAssertFalse(presentation.closeCompleted(card: 4, token: token))
        XCTAssertTrue(presentation.closeCompleted(card: 9, token: token))
        XCTAssertTrue(presentation.finishClosing(token: token))
        XCTAssertNotNil(presentation.beginPair(secondCard: 3, mismatchedCards: []))
        XCTAssertEqual(MemoryTurnPresentation.flipDuration, 0.15)
        XCTAssertEqual(MemoryTurnPresentation.mismatchHoldDuration, 0.65)
    }

    func testInvalidAndDuplicatePresentationCallbacksDoNotAdvanceTheTurn() throws {
        var presentation = MemoryTurnPresentation()
        let initial = presentation
        XCTAssertNil(presentation.beginPair(secondCard: -1, mismatchedCards: []))
        XCTAssertNil(presentation.beginPair(secondCard: 1, mismatchedCards: [1]))
        XCTAssertNil(presentation.beginPair(secondCard: 1, mismatchedCards: [1, 1]))
        XCTAssertNil(presentation.beginPair(secondCard: 1, mismatchedCards: [2, 3]))
        XCTAssertNil(presentation.beginPair(secondCard: 1, mismatchedCards: [-1, 1]))
        XCTAssertEqual(presentation, initial)
        let token = try XCTUnwrap(presentation.beginPair(secondCard: 1, mismatchedCards: [0, 1]))
        XCTAssertNil(presentation.beginPair(secondCard: 2, mismatchedCards: []))
        XCTAssertFalse(presentation.revealCompleted(card: 1, token: token, at: .nan))
        XCTAssertFalse(presentation.revealCompleted(card: 1, token: token, at: .infinity))
        XCTAssertFalse(presentation.closeCompleted(card: 0, token: token))
        XCTAssertTrue(presentation.revealCompleted(card: 1, token: token, at: 2))
        XCTAssertFalse(presentation.revealCompleted(card: 1, token: token, at: 3))
        XCTAssertNil(presentation.remainingHold(at: .nan))
        XCTAssertFalse(presentation.beginClosing(token: token, at: .infinity))
        XCTAssertEqual(try XCTUnwrap(presentation.remainingHold(at: 1)), 0.65, accuracy: 0.000_001)
        XCTAssertTrue(presentation.beginClosing(token: token, at: 2.65))
        XCTAssertFalse(presentation.closeCompleted(card: 99, token: token))
        XCTAssertFalse(presentation.closeCompleted(card: 0, token: token))
        XCTAssertFalse(presentation.closeCompleted(card: 0, token: token))
        XCTAssertFalse(presentation.finishClosing(token: token))
        XCTAssertTrue(presentation.closeCompleted(card: 1, token: token))
        XCTAssertTrue(presentation.finishClosing(token: token))
        XCTAssertFalse(presentation.finishClosing(token: token))
    }

    func testAnimationPresentationDoesNotChangeSavedSchemaOrResetPendingProgress() throws {
        var board = MemoryBoard(seed: 24)
        board.elapsedSeconds = 27
        board.select(0); board.select(1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = try encoder.encode(board)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["mode", "seed", "cards", "matched", "selectedIndices", "moves", "elapsedSeconds"])
        var presentation = MemoryTurnPresentation()
        let token = try XCTUnwrap(presentation.beginPair(secondCard: 1, mismatchedCards: [0, 1]))
        presentation.revealCompleted(card: 1, token: token, at: 0)
        presentation.beginClosing(token: token, at: 0.65)
        presentation.closeCompleted(card: 0, token: token)
        presentation.closeCompleted(card: 1, token: token)
        XCTAssertEqual(try encoder.encode(board), saved)
        let restored = try JSONDecoder().decode(MemoryBoard.self, from: saved)
        XCTAssertEqual(restored, board)
        XCTAssertTrue(restored.isValidSave)
        XCTAssertEqual(restored.moves, 1)
        XCTAssertEqual(restored.elapsedSeconds, 27)
        XCTAssertEqual(restored.selectedIndices, [0, 1])
    }
}
