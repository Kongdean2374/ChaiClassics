import XCTest
@testable import ChaiCore

final class UpgradeTests: XCTestCase {
    private func preparedStore() throws -> (URL, SaveStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for namespace in ["sudoku", "minesweeper", "sliding"] {
            let source = try XCTUnwrap(Bundle.module.url(forResource: "v010-" + namespace, withExtension: "json", subdirectory: "Fixtures"))
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(namespace + ".json"))
        }
        return (directory, try SaveStore(directory: directory))
    }
    func testV010SavesAndNewPreferencesRemainIndependent() throws {
        let (directory, store) = try preparedStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let originals = try ["sudoku", "minesweeper", "sliding"].map { try Data(contentsOf: directory.appendingPathComponent($0 + ".json")) }
        let catalog = try SudokuPuzzle.bundled()
        let sudoku = try XCTUnwrap(store.load(SudokuProgress.self, namespace: "sudoku"))
        let puzzle = try XCTUnwrap(catalog.first)
        let board = try XCTUnwrap(sudoku.boards[puzzle.id])
        XCTAssertTrue(board.isValidSave(for: puzzle)); XCTAssertEqual(board.mode, .pencil)
        XCTAssertEqual(board.notes[board.selected!], [2,7]); XCTAssertTrue(sudoku.completed.contains(puzzle.id))
        XCTAssertTrue(sudoku.isUnlocked(catalog[1], catalog: catalog))
        let mines = try XCTUnwrap(store.load(MinesweeperBoard.self, namespace: "minesweeper"))
        XCTAssertTrue(mines.isValidSave); XCTAssertEqual(mines.mode, .flag); XCTAssertEqual(mines.elapsedSeconds, 37)
        XCTAssertEqual(mines.flags, [30]); XCTAssertEqual(mines.mines, [30,31,32,39,41,48,49,50,70,71])
        let sliding = try XCTUnwrap(store.load(SlidingBoard.self, namespace: "sliding"))
        XCTAssertTrue(sliding.isValidSave); XCTAssertEqual(sliding.moves, 35); XCTAssertEqual(sliding.elapsedSeconds, 91)
        XCTAssertEqual(sliding.tiles, [1,2,3,4,5,6,7,0,8])
        let suite = "upgrade." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = AppPreferences(); preferences.language = .english; preferences.appearance = .dark
        preferences.keepScreenAwake = true; preferences.haptics = false
        PreferencesStore(defaults: defaults).save(preferences)
        XCTAssertEqual(PreferencesStore(defaults: defaults).load(), preferences)
        XCTAssertEqual(try ["sudoku", "minesweeper", "sliding"].map { try Data(contentsOf: directory.appendingPathComponent($0 + ".json")) }, originals)
        let restarted = try SaveStore(directory: directory)
        XCTAssertEqual(try restarted.load(SudokuProgress.self, namespace: "sudoku"), sudoku)
        XCTAssertEqual(try restarted.load(MinesweeperBoard.self, namespace: "minesweeper"), mines)
        XCTAssertEqual(try restarted.load(SlidingBoard.self, namespace: "sliding"), sliding)
    }
    func testDirectMinesGesturesIgnoreLegacyModeAndRespectTerminalState() throws {
        let (directory, store) = try preparedStore(); defer { try? FileManager.default.removeItem(at: directory) }
        var board = try XCTUnwrap(store.load(MinesweeperBoard.self, namespace: "minesweeper"))
        let minePositions = board.mines; let oldFlags = board.flags
        XCTAssertFalse(board.revealed.contains(40))
        board.reveal(40) // UI single tap uses this, never the legacy mode-dependent tap().
        XCTAssertTrue(board.revealed.contains(40)); XCTAssertEqual(board.flags, oldFlags)
        XCTAssertEqual(board.mines, minePositions); XCTAssertEqual(board.mode, .flag)
        var ready = MinesweeperBoard(configuration: .easy, seed: 23); ready.mode = .flag
        ready.toggleFlag(0); XCTAssertTrue(ready.revealed.isEmpty); XCTAssertEqual(ready.status, .ready)
        ready.reveal(0); XCTAssertTrue(ready.revealed.isEmpty)
        ready.toggleFlag(0); ready.reveal(0); XCTAssertTrue(ready.revealed.contains(0))
        let afterReveal = ready; ready.toggleFlag(0); XCTAssertEqual(ready, afterReveal)
        let mine = try XCTUnwrap(ready.mines.first); ready.reveal(mine); XCTAssertEqual(ready.status, .lost)
        let lost = ready; ready.toggleFlag(1); ready.reveal(2); XCTAssertEqual(ready, lost)
        for i in 0..<board.cellCount where !board.mines.contains(i) { board.reveal(i) }
        XCTAssertEqual(board.status, .won)
        XCTAssertEqual(GameSummary.mines(board).state, .completed)
        let won = board; board.reveal(30); board.toggleFlag(30); XCTAssertEqual(board, won)
    }
    func testSummariesComeFromActualBoards() throws {
        let catalog = try SudokuPuzzle.bundled()
        XCTAssertEqual(GameSummary.sudoku(SudokuProgress(), catalog: catalog).state, .notStarted)
        XCTAssertEqual(GameSummary.mines(nil).state, .notStarted)
        XCTAssertEqual(GameSummary.sliding(nil).state, .notStarted)
        let (directory, store) = try preparedStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let progress = try XCTUnwrap(store.load(SudokuProgress.self, namespace: "sudoku"))
        let summary = GameSummary.sudoku(progress, catalog: catalog)
        XCTAssertEqual(summary.state, .inProgress) // Historic completion does not falsely mark a restarted board complete.
        guard case let .sudoku(difficulty, number, filled, total) = summary.detail else { return XCTFail("Missing real Sudoku detail") }
        XCTAssertEqual(difficulty, .easy); XCTAssertEqual(number, 1); XCTAssertEqual(filled, 1)
        XCTAssertEqual(total, catalog[0].givens.filter { $0 == 0 }.count)
        var mines = try XCTUnwrap(store.load(MinesweeperBoard.self, namespace: "minesweeper"))
        XCTAssertEqual(GameSummary.mines(mines).state, .inProgress)
        mines.reveal(31); XCTAssertEqual(GameSummary.mines(mines).state, .failed)
        var slide = try XCTUnwrap(store.load(SlidingBoard.self, namespace: "sliding"))
        XCTAssertEqual(GameSummary.sliding(slide).state, .inProgress)
        guard case let .sliding(size, _, moves, seconds) = GameSummary.sliding(slide).detail else { return XCTFail("Missing sliding detail") }
        XCTAssertEqual(size, 3); XCTAssertEqual(moves, 35); XCTAssertEqual(seconds, 91)
        slide.move(8); XCTAssertEqual(GameSummary.sliding(slide).state, .completed)
        let solution = (0..<9).flatMap { row in (0..<9).map { column in (row * 3 + row / 3 + column) % 9 + 1 } }
        let solvedPuzzle = SudokuPuzzle(id: "synthetic.complete", difficulty: .easy, number: 1, givens: solution)
        var solved = SudokuProgress(); solved.record(SudokuBoard(puzzle: solvedPuzzle), puzzle: solvedPuzzle)
        XCTAssertEqual(GameSummary.sudoku(solved, catalog: [solvedPuzzle]).state, .completed)
    }
    func testPreferenceModesAndForegroundAwakePolicy() throws {
        let suite = "settings." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load().appearance, .system)
        for appearance in AppAppearance.allCases {
            for language in AppLanguage.allCases {
                var value = AppPreferences(); value.appearance = appearance; value.language = language; value.keepScreenAwake = true
                store.save(value); XCTAssertEqual(PreferencesStore(defaults: defaults).load(), value)
                XCTAssertTrue(value.shouldKeepAwake(gameIsActive: true, appIsActive: true))
                XCTAssertFalse(value.shouldKeepAwake(gameIsActive: false, appIsActive: true))
                XCTAssertFalse(value.shouldKeepAwake(gameIsActive: true, appIsActive: false))
                value.keepScreenAwake = false
                XCTAssertFalse(value.shouldKeepAwake(gameIsActive: true, appIsActive: true))
            }
        }
    }
    func testSmallBoardFitsAndCentersWithoutShrinkingLargeCells() {
        let scale = BoardViewport.minimumScale(boardWidth: 306, boardHeight: 306, viewportWidth: 358, viewportHeight: 400)
        XCTAssertEqual(scale, 358.0 / 306, accuracy: 0.001)
        XCTAssertEqual(BoardViewport.centering(content: 306 * scale, viewport: 358), 0, accuracy: 0.001)
        XCTAssertEqual(BoardViewport.centering(content: 306, viewport: 600), 147)
        XCTAssertEqual(BoardViewport.minimumScale(boardWidth: 1360, boardHeight: 1360, viewportWidth: 358, viewportHeight: 400), 1)
        XCTAssertEqual(BoardViewport.centering(content: 1360, viewport: 358), 0)
    }
}
