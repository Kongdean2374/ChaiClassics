import XCTest
@testable import ChaiCore

final class SaveStoreTests: XCTestCase {
    private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testIsolationAndRestart() throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save([1,2,3], namespace: "sudoku")
        try store.save([9], namespace: "minesweeper")
        let restarted = try SaveStore(directory: dir)
        XCTAssertEqual(try restarted.load([Int].self, namespace: "sudoku"), [1,2,3])
        XCTAssertEqual(try restarted.load([Int].self, namespace: "minesweeper"), [9])
    }
    func testInterruptedWriteAndCorruptRecovery() throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save([1], namespace: "sudoku"); try store.save([2], namespace: "sudoku")
        // Simulate an abandoned staging file; the committed primary must survive.
        try Data("partial".utf8).write(to: dir.appendingPathComponent("staging.tmp"))
        XCTAssertEqual(try store.load([Int].self, namespace: "sudoku"), [2])
        try Data("broken".utf8).write(to: dir.appendingPathComponent("sudoku.json"))
        XCTAssertEqual(try store.load([Int].self, namespace: "sudoku"), [1])
        XCTAssertTrue(store.recoveredBackup)
        try store.save([3], namespace: "sudoku")
        XCTAssertEqual(try store.load([Int].self, namespace: "sudoku"), [3])
    }
    func testMigrationAndFutureVersionProtection() throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save([1], namespace: "sudoku", version: 1)
        let migrated = try store.load([Int].self, namespace: "sudoku", version: 2) { old, _ in
            XCTAssertEqual(old, 1); return [1,2]
        }
        XCTAssertEqual(migrated, [1,2])
        try store.save(migrated, namespace: "sudoku", version: 2)
        XCTAssertThrowsError(try store.load([Int].self, namespace: "sudoku", version: 1))
        XCTAssertThrowsError(try store.save([0], namespace: "sudoku", version: 1))
        XCTAssertThrowsError(try store.save([0], namespace: "../escape"))
    }
    func testSudokuNotesPersistAcrossLaunch() throws {
        let dir = location(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = try XCTUnwrap(SudokuPuzzle.bundled().first)
        var board = SudokuBoard(puzzle: p); board.selected = p.givens.firstIndex(of: 0); board.mode = .pencil; board.enter(7, puzzle: p)
        var progress = SudokuProgress(); progress.record(board, puzzle: p)
        try SaveStore(directory: dir).save(progress, namespace: "sudoku")
        let loaded = try SaveStore(directory: dir).load(SudokuProgress.self, namespace: "sudoku")
        XCTAssertEqual(loaded, progress)
        XCTAssertEqual(GameRegistry.columns, 3)
    }
}
