import SwiftUI
import UIKit
import ChaiCore

@MainActor
final class AppModel: ObservableObject {
    enum Notice { case storageUnavailable, unreadable(GameID), recovered(GameID), writeFailed, puzzleCreation }
    @Published private(set) var sudoku = SudokuProgress()
    @Published private(set) var sliding: SlidingBoard?
    @Published private(set) var mines: MinesweeperBoard?
    @Published private(set) var ticTacToe: TicTacToeBoard?
    @Published private(set) var connectFour: ConnectFourBoard?
    @Published private(set) var twentyFour: TwentyFourBoard?
    @Published private(set) var memory: MemoryBoard?
    @Published private(set) var maze: MazeBoard?
    @Published private(set) var puzzles: [SudokuPuzzle] = []
    @Published private(set) var preferences = AppPreferences()
    @Published var notice: Notice?
    @Published private(set) var blocked: Set<GameID> = []
    @Published private(set) var newerSaves: Set<GameID> = []
    let store: SaveStore?
    private var recovery: GameSaveRecovery?
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
            recovery = GameSaveRecovery(directory: directory)
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
        } catch { recordLoadFailure(error, game: .sudoku) }
        do {
            if let saved = try store?.load(MinesweeperBoard.self, namespace: "minesweeper") {
                guard saved.isValidSave else { throw SaveStore.StoreError.corrupt }
                mines = saved
            }
            if store?.recoveredBackup == true { notice = .recovered(.minesweeper) }
        } catch { recordLoadFailure(error, game: .minesweeper) }
        do {
            if let saved = try store?.load(SlidingBoard.self, namespace: "sliding") {
                guard saved.isValidSave else { throw SaveStore.StoreError.corrupt }
                sliding = saved
            }
            if store?.recoveredBackup == true { notice = .recovered(.sliding) }
        } catch { recordLoadFailure(error, game: .sliding) }
        ticTacToe = restore(TicTacToeBoard.self, game: .ticTacToe) { $0.isValidSave }
        connectFour = restore(ConnectFourBoard.self, game: .connectFour) { $0.isValidSave }
        twentyFour = restore(TwentyFourBoard.self, game: .twentyFour) { $0.isValidSave }
        memory = restore(MemoryBoard.self, game: .memory) { $0.isValidSave }
        maze = restore(MazeBoard.self, game: .maze) { $0.isValidSave }
    }

    private func recordLoadFailure(_ error: Error, game: GameID) {
        if let storeError = error as? SaveStore.StoreError,
           case let .unsupportedVersion(version) = storeError, version > 1 { newerSaves.insert(game) }
        blocked.insert(game); notice = .unreadable(game)
    }

    private func restore<T: Codable>(_ type: T.Type, game: GameID, validate: (T) -> Bool) -> T? {
        guard let store else { return nil }
        do {
            guard let saved = try store.load(type, namespace: game.rawValue) else { return nil }
            guard validate(saved) else { throw SaveStore.StoreError.corrupt }
            if store.recoveredBackup { notice = .recovered(game) }
            return saved
        } catch { recordLoadFailure(error, game: game); return nil }
    }

    private func persist<T: Codable>(_ next: T, game: GameID, validate: (T) -> Bool) -> Bool {
        guard !blocked.contains(game), let store, validate(next) else { return false }
        do { try store.save(next, namespace: game.rawValue); return true }
        catch { notice = .writeFailed; return false }
    }

    /// Called only by a confirmed recovery control; future schemas cannot be reset.
    @discardableResult func recoverGame(_ game: GameID) -> Bool {
        guard blocked.contains(game), !newerSaves.contains(game), let recovery else { return false }
        do {
            try recovery.quarantine(game)
            switch game {
            case .sudoku: sudoku = SudokuProgress()
            case .minesweeper: mines = nil
            case .sliding: sliding = nil
            case .ticTacToe: ticTacToe = nil
            case .connectFour: connectFour = nil
            case .twentyFour: twentyFour = nil
            case .memory: memory = nil
            case .maze: maze = nil
            }
            blocked.remove(game); notice = nil; return true
        } catch { notice = .writeFailed; return false }
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

    @discardableResult func saveTicTacToe(_ next: TicTacToeBoard) -> Bool {
        guard persist(next, game: .ticTacToe, validate: { $0.isValidSave }) else { return false }
        ticTacToe = next; return true
    }
    @discardableResult func editTicTacToe(_ change: (inout TicTacToeBoard) -> Void) -> Bool {
        guard var next = ticTacToe else { return false }; let previous = next; change(&next)
        return next != previous && saveTicTacToe(next)
    }
    @discardableResult func saveConnectFour(_ next: ConnectFourBoard) -> Bool {
        guard persist(next, game: .connectFour, validate: { $0.isValidSave }) else { return false }
        connectFour = next; return true
    }
    @discardableResult func editConnectFour(_ change: (inout ConnectFourBoard) -> Void) -> Bool {
        guard var next = connectFour else { return false }; let previous = next; change(&next)
        return next != previous && saveConnectFour(next)
    }
    @discardableResult func saveTwentyFour(_ next: TwentyFourBoard) -> Bool {
        guard persist(next, game: .twentyFour, validate: { $0.isValidSave }) else { return false }
        twentyFour = next; return true
    }
    @discardableResult func editTwentyFour(_ change: (inout TwentyFourBoard) -> Void) -> Bool {
        guard var next = twentyFour else { return false }; let previous = next; change(&next)
        return next != previous && saveTwentyFour(next)
    }
    @discardableResult func saveMemory(_ next: MemoryBoard) -> Bool {
        guard persist(next, game: .memory, validate: { $0.isValidSave }) else { return false }
        memory = next; return true
    }
    @discardableResult func editMemory(_ change: (inout MemoryBoard) -> Void) -> Bool {
        guard var next = memory else { return false }; let previous = next; change(&next)
        return next != previous && saveMemory(next)
    }
    @discardableResult func saveMaze(_ next: MazeBoard) -> Bool {
        guard persist(next, game: .maze, validate: { $0.isValidSave }) else { return false }
        maze = next; return true
    }
    @discardableResult func editMaze(_ change: (inout MazeBoard) -> Void) -> Bool {
        guard var next = maze else { return false }; let previous = next; change(&next)
        return next != previous && saveMaze(next)
    }
}
