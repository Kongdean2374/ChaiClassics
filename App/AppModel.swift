import SwiftUI
import UIKit
import ChaiCore

@MainActor
final class AppModel: ObservableObject {
    enum Notice { case storageUnavailable, unreadable(GameID), recovered(GameID), writeFailed, puzzleCreation }
    @Published private(set) var sudoku = SudokuProgress()
    @Published private(set) var sliding: SlidingBoard?
    @Published private(set) var mines: MinesweeperBoard?
    @Published private(set) var puzzles: [SudokuPuzzle] = []
    @Published private(set) var preferences = AppPreferences()
    @Published var notice: Notice?
    @Published private(set) var blocked: Set<GameID> = []
    let store: SaveStore?
    private let preferenceStore: PreferencesStore
    private var activeGame: GameID?
    private var sceneActive = true
    private var gameActive = false

    init() {
        var defaults = UserDefaults.standard
        var testDirectory: URL?
        #if DEBUG && targetEnvironment(simulator)
        if let test = UITestBootstrap.configuration() {
            defaults = test.defaults; testDirectory = test.directory
            UITestBootstrap.prepare(test)
        }
        #endif
        preferenceStore = PreferencesStore(defaults: defaults)
        preferences = preferenceStore.load()
        do {
            let directory: URL
            if let testDirectory { directory = testDirectory }
            else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("ChaiClassics", isDirectory: true)
            }
            store = try SaveStore(directory: directory)
        } catch { store = nil; notice = .storageUnavailable; blocked = Set(GameID.allCases) }
        do {
            puzzles = try SudokuPuzzle.bundled()
            if let saved = try store?.load(SudokuProgress.self, namespace: "sudoku") {
                guard saved.boards.allSatisfy({ id, board in
                    guard let puzzle = puzzles.first(where: { $0.id == id }) else { return false }
                    return board.isValidSave(for: puzzle)
                }), saved.currentID == nil || puzzles.contains(where: { $0.id == saved.currentID }) else { throw SaveStore.StoreError.corrupt }
                sudoku = saved
            }
            if store?.recoveredBackup == true { notice = .recovered(.sudoku) }
        } catch { blocked.insert(.sudoku); notice = .unreadable(.sudoku) }
        do {
            if let saved = try store?.load(MinesweeperBoard.self, namespace: "minesweeper") {
                guard saved.isValidSave else { throw SaveStore.StoreError.corrupt }
                mines = saved
            }
            if store?.recoveredBackup == true { notice = .recovered(.minesweeper) }
        } catch { blocked.insert(.minesweeper); notice = .unreadable(.minesweeper) }
        do {
            if let saved = try store?.load(SlidingBoard.self, namespace: "sliding") {
                guard saved.isValidSave else { throw SaveStore.StoreError.corrupt }
                sliding = saved
            }
            if store?.recoveredBackup == true { notice = .recovered(.sliding) }
        } catch { blocked.insert(.sliding); notice = .unreadable(.sliding) }
    }

    var noticeText: String {
        switch notice {
        case .storageUnavailable: return t("storage.unavailable")
        case let .unreadable(game): return t("storage.unreadable", gameTitle(game))
        case let .recovered(game): return t("storage.recovered", gameTitle(game))
        case .writeFailed: return t("storage.writeFailed")
        case .puzzleCreation: return t("storage.puzzleCreation")
        case nil: return ""
        }
    }
    func updatePreferences(_ change: (inout AppPreferences) -> Void) {
        var next = preferences; change(&next)
        preferenceStore.save(next); preferences = next; updateIdleTimer()
    }
    func feedback() { if preferences.haptics { UISelectionFeedbackGenerator().selectionChanged() } }
    func setSceneActive(_ active: Bool) { sceneActive = active; updateIdleTimer() }
    func setGameActivity(_ game: GameID, active: Bool) { activeGame = game; gameActive = active; updateIdleTimer() }
    func endGameActivity(_ game: GameID) {
        if activeGame == game { activeGame = nil; gameActive = false; updateIdleTimer() }
    }
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = preferences.shouldKeepAwake(gameIsActive: activeGame != nil && gameActive, appIsActive: sceneActive)
    }
    @discardableResult func saveSudoku(_ next: SudokuProgress) -> Bool {
        guard !blocked.contains(.sudoku), let store else { return false }
        do { try store.save(next, namespace: "sudoku"); sudoku = next; return true }
        catch { notice = .writeFailed; return false }
    }
    func open(_ puzzle: SudokuPuzzle, restart: Bool = false) {
        var next = sudoku
        if restart || next.boards[puzzle.id] == nil { next.boards[puzzle.id] = SudokuBoard(puzzle: puzzle) }
        next.currentID = puzzle.id
        if next != sudoku { saveSudoku(next) }
    }
    @discardableResult func edit(_ puzzle: SudokuPuzzle, _ change: (inout SudokuBoard) -> Void) -> Bool {
        guard var board = sudoku.boards[puzzle.id] else { return false }
        let previous = board; change(&board)
        guard board != previous else { return false }
        var next = sudoku; next.record(board, puzzle: puzzle); return saveSudoku(next)
    }
    @discardableResult func saveMines(_ next: MinesweeperBoard) -> Bool {
        guard !blocked.contains(.minesweeper), let store else { return false }
        do { try store.save(next, namespace: "minesweeper"); mines = next; return true }
        catch { notice = .writeFailed; return false }
    }
    @discardableResult func editMines(_ change: (inout MinesweeperBoard) -> Void) -> Bool {
        guard var board = mines else { return false }
        let previous = board; change(&board)
        return board != previous && saveMines(board)
    }
    @discardableResult func saveSliding(_ next: SlidingBoard) -> Bool {
        guard !blocked.contains(.sliding), let store else { return false }
        do { try store.save(next, namespace: "sliding"); sliding = next; return true }
        catch { notice = .writeFailed; return false }
    }
    @discardableResult func editSliding(_ change: (inout SlidingBoard) -> Void) -> Bool {
        guard var board = sliding else { return false }
        let previous = board; change(&board)
        return board != previous && saveSliding(board)
    }
}
