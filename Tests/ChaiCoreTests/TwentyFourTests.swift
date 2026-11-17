import XCTest
@testable import ChaiCore

final class TwentyFourTests: XCTestCase {
    func testRationalNormalizationZeroDivisionAndOverflow() throws {
        XCTAssertEqual(Rational(2, -6), Rational(-1, 3))
        XCTAssertEqual(Rational(-2, -6), Rational(1, 3))
        XCTAssertEqual(Rational(0, -7), Rational(0))
        XCTAssertNil(Rational(1, 0))
        XCTAssertNil(Rational(1, Int64.min))
        XCTAssertEqual(Rational(2, Int64.min), Rational(-1, 4_611_686_018_427_387_904))
        XCTAssertEqual(Rational(1, 3)!.applying(.add, to: Rational(2, 3)!), Rational(1))
        XCTAssertEqual(Rational(7, 3)!.applying(.multiply, to: Rational(9, 7)!), Rational(3))
        XCTAssertNil(Rational(8)!.applying(.divide, to: Rational(0)!))
        XCTAssertNil(Rational(Int64.max)!.applying(.add, to: Rational(1)!))
        XCTAssertNil(Rational(Int64.max)!.applying(.multiply, to: Rational(2)!))
        XCTAssertNil(Rational(Int64.min)!.applying(.subtract, to: Rational(1)!))
        XCTAssertNil(Rational(Int64.min)!.applying(.divide, to: Rational(-1)!))
        XCTAssertThrowsError(try JSONDecoder().decode(Rational.self, from: Data("{\"numerator\":1,\"denominator\":0}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Rational.self, from: Data("{\"numerator\":2,\"denominator\":4}".utf8)))
    }

    func testDuplicateCardsRemainIndependentAndBothBranchesCanBeBuilt() throws {
        var board = try TwentyFourBoard(numbers: [6, 6, 6, 6], seed: 5)
        XCTAssertEqual(Set(board.cards.map(\.id)).count, 4)
        XCTAssertFalse(board.combine(firstID: 0, secondID: 0, operation: .add))
        XCTAssertTrue(board.combine(firstID: 0, secondID: 1, operation: .add))
        XCTAssertFalse(board.combine(firstID: 0, secondID: 2, operation: .multiply))
        XCTAssertTrue(board.combine(firstID: 2, secondID: 3, operation: .add))
        XCTAssertEqual(board.cards.map(\.id), [4, 5])
        XCTAssertTrue(board.combine(firstID: 4, secondID: 5, operation: .add))
        XCTAssertTrue(board.isComplete)
        XCTAssertEqual(board.cards.first?.expression, "((6 + 6) + (6 + 6))")
        XCTAssertEqual(board.cards.first?.sourceMask, 15)
        XCTAssertEqual(board.solvedCount, 1)
        let completed = board
        XCTAssertFalse(board.combine(firstID: 6, secondID: 0, operation: .add))
        XCTAssertEqual(board, completed)
        XCTAssertTrue(board.isValidSave)
        var partial = try TwentyFourBoard(numbers: [1, 2, 3, 12], seed: 5)
        XCTAssertTrue(partial.combine(firstID: 1, secondID: 3, operation: .multiply))
        XCTAssertEqual(partial.cards.last?.value, Rational(24))
        XCTAssertFalse(partial.isComplete, "Making 24 before using all four physical cards is not a win")
        XCTAssertEqual(partial.solvedCount, 0)
    }

    func testFractionalSolutionUsesEveryCardOnceWithoutFloatingPoint() throws {
        var board = try TwentyFourBoard(numbers: [3, 3, 8, 8], seed: 24)
        XCTAssertEqual(board.difficulty, .hard)
        XCTAssertTrue(board.combine(firstID: 2, secondID: 0, operation: .divide))
        XCTAssertEqual(board.cards.last?.value, Rational(8, 3))
        XCTAssertTrue(board.combine(firstID: 1, secondID: 4, operation: .subtract))
        XCTAssertEqual(board.cards.last?.value, Rational(1, 3))
        XCTAssertTrue(board.combine(firstID: 3, secondID: 5, operation: .divide))
        XCTAssertEqual(board.cards.first?.value, Rational(24))
        XCTAssertTrue(board.isComplete)
        XCTAssertTrue(board.isValidSave)
    }

    func testNegativeIntermediateAndNoncommutativeOrder() throws {
        var board = try TwentyFourBoard(numbers: [1, 4, 2, 10], seed: 3)
        XCTAssertTrue(board.combine(firstID: 0, secondID: 1, operation: .subtract))
        XCTAssertEqual(board.cards.last?.value, Rational(-3))
        XCTAssertTrue(board.combine(firstID: 2, secondID: 3, operation: .subtract))
        XCTAssertEqual(board.cards.last?.value, Rational(-8))
        XCTAssertTrue(board.combine(firstID: 4, secondID: 5, operation: .multiply))
        XCTAssertTrue(board.isComplete)
        var ordered = try TwentyFourBoard(numbers: [1, 2, 3, 4], seed: 5)
        XCTAssertTrue(ordered.combine(firstID: 0, secondID: 3, operation: .divide))
        XCTAssertEqual(ordered.cards.last?.value, Rational(1, 4))
        XCTAssertTrue(ordered.undo())
        XCTAssertTrue(ordered.combine(firstID: 3, secondID: 0, operation: .divide))
        XCTAssertEqual(ordered.cards.last?.value, Rational(4))
    }

    func testZeroDivisionAndIncorrectFinalDoNotCountAsSuccess() throws {
        var board = try TwentyFourBoard(numbers: [1, 1, 6, 8], seed: 4)
        XCTAssertTrue(board.combine(firstID: 0, secondID: 1, operation: .subtract))
        let before = board
        XCTAssertFalse(board.canCombine(firstID: 2, secondID: 4, operation: .divide))
        XCTAssertFalse(board.combine(firstID: 2, secondID: 4, operation: .divide))
        XCTAssertEqual(board, before)
        XCTAssertTrue(board.combine(firstID: 4, secondID: 2, operation: .divide))
        XCTAssertTrue(board.combine(firstID: 3, secondID: 5, operation: .add))
        XCTAssertTrue(board.isEnded)
        XCTAssertFalse(board.isComplete)
        XCTAssertEqual(board.solvedCount, 0)
        XCTAssertTrue(board.isValidSave)
        XCTAssertTrue(board.undo())
        XCTAssertFalse(board.isEnded)
    }

    func testUndoResetNextAndScoreCannotBeFarmed() throws {
        var board = try TwentyFourBoard(numbers: [1, 2, 3, 4], seed: 24)
        func solve(_ board: inout TwentyFourBoard) {
            XCTAssertTrue(board.combine(firstID: 0, secondID: 1, operation: .add))
            XCTAssertTrue(board.combine(firstID: 2, secondID: 4, operation: .add))
            XCTAssertTrue(board.combine(firstID: 3, secondID: 5, operation: .multiply))
        }
        XCTAssertFalse(board.undo())
        solve(&board)
        XCTAssertTrue(board.undo())
        XCTAssertTrue(board.isValidSave)
        XCTAssertTrue(board.combine(firstID: 3, secondID: 5, operation: .multiply))
        XCTAssertEqual(board.solvedCount, 1)
        board.elapsedSeconds = 45
        board.reset()
        XCTAssertEqual(board.elapsedSeconds, 0)
        XCTAssertEqual(board.cards.count, 4)
        XCTAssertEqual(board.history, [])
        solve(&board)
        XCTAssertEqual(board.solvedCount, 1)
        board.nextPuzzle()
        XCTAssertEqual(board.puzzleIndex, 1)
        XCTAssertEqual(board.solvedCount, 1)
        XCTAssertFalse(board.recordedSuccess)
        XCTAssertEqual(board.history, [])
        XCTAssertFalse(board.isComplete)
        XCTAssertTrue(board.isValidSave)
    }

    func testDifficultyClassificationsAreConcrete() {
        XCTAssertEqual(TwentyFourSolver.difficulty(of: [1, 2, 3, 4]), .easy)
        XCTAssertFalse(TwentyFourSolver.isSolvable([1, 1, 6, 8], policy: .nonnegativeWithoutDivision))
        XCTAssertTrue(TwentyFourSolver.isSolvable([1, 1, 6, 8], policy: .nonnegativeIntegers))
        XCTAssertEqual(TwentyFourSolver.difficulty(of: [1, 1, 6, 8]), .normal)
        XCTAssertFalse(TwentyFourSolver.isSolvable([3, 3, 8, 8], policy: .nonnegativeIntegers))
        XCTAssertTrue(TwentyFourSolver.isSolvable([3, 3, 8, 8]))
        XCTAssertEqual(TwentyFourSolver.difficulty(of: [3, 3, 8, 8]), .hard)
        XCTAssertNil(TwentyFourSolver.difficulty(of: [1, 1, 1, 1]))
        XCTAssertFalse(TwentyFourSolver.isSolvable([0, 2, 3, 4]))
        XCTAssertThrowsError(try TwentyFourBoard(numbers: [1, 1, 1, 1]))
        XCTAssertThrowsError(try TwentyFourBoard(numbers: [1, 2, 3]))
        XCTAssertThrowsError(try TwentyFourBoard(numbers: [1, 2, 3, 14]))
    }

    func testAll1362DistinctCatalogPuzzlesWithIndependentExactOracle() {
        var oracle = IndependentTwentyFourOracle()
        var unique = Set<[Int]>()
        XCTAssertEqual(TwentyFourGenerator.totalDistinctPuzzles, 1_362)
        for difficulty in TwentyFourDifficulty.allCases {
            for numbers in TwentyFourGenerator.catalog(for: difficulty) {
                XCTAssertTrue(unique.insert(numbers).inserted, "Duplicate multiset \(numbers)")
                XCTAssertEqual(numbers, numbers.sorted())
                XCTAssertTrue(numbers.allSatisfy { (1...13).contains($0) })
                XCTAssertTrue(oracle.canSolve(numbers), "Independent oracle rejected \(numbers)")
                XCTAssertTrue(TwentyFourSolver.isSolvable(numbers), "Subset solver rejected \(numbers)")
                XCTAssertEqual(TwentyFourGenerator.catalogDifficulty(of: numbers), difficulty)
            }
        }
        XCTAssertGreaterThan(unique.count, 1_000)
    }

    func testEveryCatalogDifficultyMatchesIndependentSolverPolicies() {
        for difficulty in TwentyFourDifficulty.allCases {
            for numbers in TwentyFourGenerator.catalog(for: difficulty) {
                XCTAssertEqual(TwentyFourSolver.difficulty(of: numbers), difficulty, "Wrong difficulty \(numbers)")
            }
        }
    }

    func testSeededGeneratorTraversesWholeCatalogBeforeRepeating() {
        for difficulty in TwentyFourDifficulty.allCases {
            let count = TwentyFourGenerator.catalog(for: difficulty).count
            let samples = (0..<count).map { TwentyFourGenerator.numbers(difficulty: difficulty, seed: 0xCAFE, index: $0).sorted() }
            XCTAssertEqual(Set(samples).count, count)
            XCTAssertEqual(samples.first, TwentyFourGenerator.numbers(difficulty: difficulty, seed: 0xCAFE, index: count).sorted())
            XCTAssertEqual(TwentyFourGenerator.numbers(difficulty: difficulty, seed: 12), TwentyFourGenerator.numbers(difficulty: difficulty, seed: 12))
        }
        let randomSeeds = (0..<50).map { TwentyFourGenerator.numbers(difficulty: .easy, seed: UInt64($0)).sorted() }
        XCTAssertGreaterThan(Set(randomSeeds).count, 40)
    }

    func testGenerationAndSaveValidationAreBounded() {
        let start = Date()
        for seed in UInt64(0)..<60 {
            for difficulty in TwentyFourDifficulty.allCases {
                let board = TwentyFourBoard(difficulty: difficulty, seed: seed)
                for _ in 0..<50 { XCTAssertTrue(board.isValidSave) }
            }
        }
        // Broad enough for an unoptimized CI runner, while detecting unbounded search on saves.
        XCTAssertLessThan(Date().timeIntervalSince(start), 15)
    }

    func testActiveExpressionAndElapsedRoundTripInIsolatedSaveNamespace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaveStore(directory: directory)
        let sliding = try SlidingBoard(size: 3, difficulty: .normal, seed: 11)
        try store.save(sliding, namespace: "sliding")
        var board = try TwentyFourBoard(numbers: [3, 3, 8, 8], seed: 24)
        board.combine(firstID: 2, secondID: 0, operation: .divide)
        board.combine(firstID: 1, secondID: 4, operation: .subtract)
        board.elapsedSeconds = 73
        try store.save(board, namespace: "twentyfour")
        let loaded = try XCTUnwrap(store.load(TwentyFourBoard.self, namespace: "twentyfour"))
        XCTAssertEqual(loaded, board)
        XCTAssertEqual(loaded.cards, board.cards)
        XCTAssertEqual(loaded.cards.last?.value, Rational(1, 3))
        XCTAssertEqual(loaded.elapsedSeconds, 73)
        XCTAssertTrue(loaded.isValidSave)
        XCTAssertEqual(try store.load(SlidingBoard.self, namespace: "sliding"), sliding)
    }

    func testCorruptSavedMoveReferencesAndCountsAreRejected() throws {
        let board = try TwentyFourBoard(numbers: [1, 2, 3, 4], seed: 24)
        func changed(_ modify: (inout [String: Any]) -> Void) throws -> TwentyFourBoard {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(board)) as? [String: Any])
            modify(&object)
            return try JSONDecoder().decode(TwentyFourBoard.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertFalse(try changed { $0["elapsedSeconds"] = -1 }.isValidSave)
        XCTAssertFalse(try changed { $0["elapsedSeconds"] = Int.max }.isValidSave)
        XCTAssertFalse(try changed { $0["puzzleIndex"] = -1 }.isValidSave)
        XCTAssertFalse(try changed { $0["puzzleIndex"] = Int.max }.isValidSave)
        XCTAssertFalse(try changed { $0["solvedCount"] = 100 }.isValidSave)
        var invalidCounters = try changed { $0["solvedCount"] = Int.max }
        XCTAssertFalse(invalidCounters.combine(firstID: 0, secondID: 1, operation: .add))
        XCTAssertFalse(invalidCounters.undo())
        invalidCounters.reset()
        invalidCounters.nextPuzzle()
        XCTAssertFalse(invalidCounters.isValidSave)
        XCTAssertFalse(try changed { $0["recordedSuccess"] = true }.isValidSave)
        XCTAssertFalse(try changed { $0["difficulty"] = "hard" }.isValidSave)
        XCTAssertFalse(try changed { $0["numbers"] = [1, 1, 1, 1] }.isValidSave)
        XCTAssertFalse(try changed { $0["numbers"] = [1, 2, 3] }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = [["firstID": 0, "secondID": 0, "operation": "add"]] }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = [["firstID": 0, "secondID": 99, "operation": "add"]] }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = [["firstID": 0, "secondID": 1, "operation": "add"], ["firstID": 0, "secondID": 2, "operation": "multiply"]] }.isValidSave)
        XCTAssertFalse(try changed { $0["history"] = Array(repeating: ["firstID": 0, "secondID": 1, "operation": "add"], count: 4) }.isValidSave)
        XCTAssertThrowsError(try changed { $0["history"] = [["firstID": 0, "secondID": 1, "operation": "power"]] })
        let zero = try TwentyFourBoard(numbers: [1, 1, 6, 8], seed: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(zero)) as? [String: Any])
        object["history"] = [["firstID": 0, "secondID": 1, "operation": "subtract"], ["firstID": 2, "secondID": 4, "operation": "divide"]]
        let invalidDivision = try JSONDecoder().decode(TwentyFourBoard.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(invalidDivision.isValidSave)
        XCTAssertEqual(invalidDivision.cards, [])
    }
}

/// A second arithmetic implementation and recursive pair-reduction algorithm, with memoization.
/// It intentionally shares neither the production fraction arithmetic nor its subset solver.
private struct IndependentTwentyFourOracle {
    private struct Fraction: Hashable, Comparable {
        let n: Int64
        let d: Int64
        init(_ numerator: Int64, _ denominator: Int64 = 1) {
            var a = abs(numerator), b = abs(denominator)
            while b != 0 { (a, b) = (b, a % b) }
            let divisor = max(1, a)
            n = numerator / divisor * (denominator < 0 ? -1 : 1)
            d = abs(denominator) / divisor
        }
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.n * rhs.d < rhs.n * lhs.d }
    }
    private var memo: [[Fraction]: Bool] = [:]
    mutating func canSolve(_ numbers: [Int]) -> Bool { search(numbers.map { Fraction(Int64($0)) }.sorted()) }
    private mutating func search(_ cards: [Fraction]) -> Bool {
        if cards.count == 1 { return cards[0] == Fraction(24) }
        if let known = memo[cards] { return known }
        for i in cards.indices {
            for j in cards.indices where j > i {
                let a = cards[i], b = cards[j]
                var candidates: Set<Fraction> = [Fraction(a.n * b.d + b.n * a.d, a.d * b.d),
                                                Fraction(a.n * b.d - b.n * a.d, a.d * b.d),
                                                Fraction(b.n * a.d - a.n * b.d, a.d * b.d),
                                                Fraction(a.n * b.n, a.d * b.d)]
                if b.n != 0 { candidates.insert(Fraction(a.n * b.d, a.d * b.n)) }
                if a.n != 0 { candidates.insert(Fraction(b.n * a.d, b.d * a.n)) }
                let remaining = cards.indices.filter { $0 != i && $0 != j }.map { cards[$0] }
                for result in candidates {
                    if search((remaining + [result]).sorted()) { memo[cards] = true; return true }
                }
            }
        }
        memo[cards] = false
        return false
    }
}
