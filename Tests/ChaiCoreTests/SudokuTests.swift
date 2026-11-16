import XCTest
@testable import ChaiCore

final class SudokuTests: XCTestCase {
    func testCatalogAndUniqueSolutions() throws {
        let puzzles = try SudokuPuzzle.bundled()
        XCTAssertEqual(puzzles.count, 150)
        XCTAssertEqual(Set(puzzles.map(\.id)).count, 150)
        XCTAssertEqual(Set(puzzles.map(\.givens)).count, 150)
        for difficulty in SudokuDifficulty.allCases {
            XCTAssertEqual(puzzles.filter { $0.difficulty == difficulty }.map(\.number), Array(1...50))
        }
        for puzzle in puzzles {
            XCTAssertTrue(SudokuRules.validGivens(puzzle.givens), puzzle.id)
            var grid = puzzle.givens
            XCTAssertEqual(solve(&grid, limit: 2).count, 1, puzzle.id)
        }
    }
    // Test-only solver, absent from the app's rules engine and UI.
    private func solve(_ grid: inout [Int], limit: Int) -> [[Int]] {
        var best: Int?; var options = [Int]()
        for i in grid.indices where grid[i] == 0 {
            let peers = SudokuRules.units.filter { $0.contains(i) }.flatMap { $0 }
            let choices = (1...9).filter { !Set(peers.map { grid[$0] }).contains($0) }
            if choices.isEmpty { return [] }
            if best == nil || choices.count < options.count { best = i; options = choices }
        }
        guard let i = best else { return [grid] }
        var result = [[Int]]()
        for d in options {
            grid[i] = d; result += solve(&grid, limit: limit - result.count)
            if result.count >= limit { break }
        }
        grid[i] = 0; return result
    }
    func testPaperInputAndCompletion() throws {
        let p = try XCTUnwrap(SudokuPuzzle.bundled().first)
        let blanks = p.givens.indices.filter { p.givens[$0] == 0 }
        let i = blanks[0], j = blanks[1]
        var b = SudokuBoard(puzzle: p)
        b.selected = i; b.mode = .pencil; b.enter(2, puzzle: p); b.enter(8, puzzle: p)
        XCTAssertEqual(b.notes[i], [2,8])
        b.enter(2, puzzle: p); XCTAssertEqual(b.notes[i], [8])
        b.selected = j; b.enter(3, puzzle: p)
        b.selected = i; b.mode = .answer; b.enter(9, puzzle: p)
        XCTAssertEqual(b.cells[i], 9); XCTAssertTrue(b.notes[i].isEmpty); XCTAssertEqual(b.notes[j], [3])
        b.erase(puzzle: p); XCTAssertEqual(b.cells[i], 0)
        let fixed = try XCTUnwrap(p.givens.firstIndex(where: { $0 != 0 }))
        b.selected = fixed; b.enter(1, puzzle: p); b.erase(puzzle: p)
        XCTAssertEqual(b.cells[fixed], p.givens[fixed])
        for index in blanks { b.selected = index; b.enter(1, puzzle: p) }
        XCTAssertFalse(b.isComplete(puzzle: p)) // Wrong full board remains ordinary editable input.
        XCTAssertEqual(b.cells[blanks[0]], 1)
        var grid = p.givens; let solution = try XCTUnwrap(solve(&grid, limit: 1).first)
        for index in blanks { b.selected = index; b.enter(solution[index], puzzle: p) }
        XCTAssertTrue(b.isComplete(puzzle: p))
        b.erase(puzzle: p); XCTAssertFalse(b.isComplete(puzzle: p))
    }
    func testUnlockAndAppendStableIDs() throws {
        var catalog = try SudokuPuzzle.bundled()
        let p = try XCTUnwrap(catalog.first)
        var progress = SudokuProgress()
        XCTAssertTrue(progress.isUnlocked(p, catalog: catalog))
        XCTAssertFalse(progress.isUnlocked(catalog[1], catalog: catalog))
        progress.completed.insert(p.id)
        XCTAssertTrue(progress.isUnlocked(catalog[1], catalog: catalog))
        XCTAssertFalse(progress.isUnlocked(catalog[51], catalog: catalog))
        var board = SudokuBoard(puzzle: p); board.selected = 0; progress.record(board, puzzle: p)
        let old = progress
        catalog.append(SudokuPuzzle(id: "sudoku.easy.0051", difficulty: .easy, number: 51, givens: p.givens))
        let restored = try JSONDecoder().decode(SudokuProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(old, restored)
        progress.completed.insert("sudoku.easy.0050")
        XCTAssertTrue(progress.isUnlocked(catalog.last!, catalog: catalog))
    }
}
