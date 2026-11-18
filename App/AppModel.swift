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
    @Published private(set) var expandedGames: [GameID: ExpandedGameSave] = [:]
    @Published private(set) var puzzles: [SudokuPuzzle] = []
    @Published private(set) var preferences = AppPreferences()
    @Published var notice: Notice?
    @Published private(set) var blocked: Set<GameID> = []
    @Published private(set) var newerSaves: Set<GameID> = []
    private(set) var store: SaveStore?
    var transferStore: GameDataTransferStore?
    @Published private(set) var sessionData = GameSessionData()
    private var sessionStorageAvailable = true
    private var clockAnchor: (game: GameID, session: UUID, uptime: TimeInterval)?
    private var visibleSession: GameID?
    private var pendingNewGame: GameID?
    private var preparedNewGame: GameID?
    private var synchronizingClock = false
    @Published private(set) var navigationTouchLocked = false
    private var navigationTouchToken: UUID?
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
        var preparedStore: SaveStore?
        do {
            let directory: URL
            if let testDirectory { directory = testDirectory }
            else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("ChaiClassics", isDirectory: true)
            }
            // Recover an interrupted import before reading any released save.
            transferStore = try GameDataTransferStore(directory: directory)
            preparedStore = try SaveStore(directory: directory)
            recovery = GameSaveRecovery(directory: directory)
        } catch { notice = .storageUnavailable; blocked = Set(GameID.allCases); sessionStorageAvailable = false }
        store = preparedStore
        do {
            if let transferStore {
                sessionData = try transferStore.loadSessionData()
                if let imported = try transferStore.loadImportedPreferences() {
                    preferences = imported; preferenceStore.save(imported)
                }
                // A terminated process never resumes a running clock implicitly.
                for game in GameID.allCases {
                    if let token = sessionData.sessions[game]?.pendingToken { _ = sessionData.sessions[game]?.cancelConfirmation(token) }
                    _ = sessionData.sessions[game]?.pause()
                }
                try transferStore.saveSessionData(sessionData)
            }
        } catch { sessionStorageAvailable = false; notice = .storageUnavailable; blocked = Set(GameID.allCases) }
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
        for game in GameID.allCases where game.isExpanded {
            expandedGames[game] = restore(ExpandedGameSave.self, game: game) { $0.gameID == game && $0.isValidSave }
        }
        if sessionStorageAvailable {
            // Preserve real pre-0.2.2 totals without inventing dated records.
            // Zero markers also stop a new install from reclassifying future wins.
            var metadata = sessionData
            if metadata.legacyDuelStatistics[.ticTacToe] == nil { metadata.legacyDuelStatistics[.ticTacToe] = ticTacToe?.statistics ?? DuelStatistics() }
            if metadata.legacyDuelStatistics[.connectFour] == nil { metadata.legacyDuelStatistics[.connectFour] = connectFour?.statistics ?? DuelStatistics() }
            if metadata != sessionData { _ = commitSessionData(metadata) }
        }
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
        guard sessionStorageAvailable, blocked.contains(game), !newerSaves.contains(game), let recovery else { return false }
        do {
            try recovery.quarantine(game)
            guard let transferStore else { return false }
            var metadata = sessionData; metadata.sessions[game] = nil
            if game == .sudoku { metadata.sudokuSessions = [:] }
            let result = try transferStore.replaceGame(game, payload: nil, metadata: metadata)
            sessionData = result.metadata
            if clockAnchor?.game == game { clockAnchor = nil }
            switch game {
            case .sudoku: sudoku = SudokuProgress()
            case .minesweeper: mines = nil
            case .sliding: sliding = nil
            case .ticTacToe: ticTacToe = nil
            case .connectFour: connectFour = nil
            case .twentyFour: twentyFour = nil
            case .memory: memory = nil
            case .maze: maze = nil
            default: expandedGames[game] = nil
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
        do {
            guard sessionStorageAvailable, let transferStore else { return }
            try transferStore.saveImportedPreferences(next)
            preferenceStore.save(next); preferences = next; updateIdleTimer()
        } catch { notice = .writeFailed }
    }
    func feedback() { if preferences.haptics { UISelectionFeedbackGenerator().selectionChanged() } }
    func setSceneActive(_ active: Bool) {
        if !active, let game = visibleSession { pauseSession(game) }
        sceneActive = active; updateIdleTimer()
    }
    func setGameActivity(_ game: GameID, active: Bool) { activeGame = game; gameActive = active; updateIdleTimer() }
    func endGameActivity(_ game: GameID) {
        if activeGame == game { activeGame = nil; gameActive = false; updateIdleTimer() }
    }
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = preferences.shouldKeepAwake(gameIsActive: activeGame != nil && gameActive, appIsActive: sceneActive)
    }
    @discardableResult func saveSudoku(_ next: SudokuProgress) -> Bool {
        flushSessionClock(.sudoku)
        guard !blocked.contains(.sudoku), let store else { return false }
        if pendingNewGame == .sudoku {
            guard persistNewGamePayload(.sudoku(next)) else { return false }
            sudoku = next; return true
        }
        if next.currentID != sudoku.currentID, let transferStore {
            do {
                var metadata = sessionData
                _ = metadata.parkSudokuSession()
                if let id = next.currentID { _ = metadata.restoreSudokuSession(puzzleID: id) }
                let result = try transferStore.replaceGame(.sudoku, payload: .sudoku(next), metadata: metadata)
                sessionData = result.metadata; sudoku = next; return true
            } catch { notice = .writeFailed; return false }
        }
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
        flushSessionClock(.sudoku)
        guard var board = sudoku.boards[puzzle.id] else { return false }
        let previous = board; change(&board)
        guard board != previous else { return false }
        var next = sudoku; next.record(board, puzzle: puzzle)
        guard saveSudoku(next) else { return false }
        if board.cells != previous.cells || board.notes != previous.notes { noteSessionMove(.sudoku) }
        return true
    }
    @discardableResult func saveMines(_ candidate: MinesweeperBoard) -> Bool {
        if pendingNewGame == .minesweeper {
            guard persistNewGamePayload(.minesweeper(candidate)) else { return false }
            mines = candidate; return true
        }
        flushSessionClock(.minesweeper)
        var next = candidate
        if sessionIsPlaying(.minesweeper) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.minesweeper]?.elapsedSeconds ?? 0) }
        guard !blocked.contains(.minesweeper), let store else { return false }
        do { try store.save(next, namespace: "minesweeper"); mines = next; return true }
        catch { notice = .writeFailed; return false }
    }
    @discardableResult func editMines(_ change: (inout MinesweeperBoard) -> Void) -> Bool {
        flushSessionClock(.minesweeper)
        guard var board = mines else { return false }
        let previous = board; change(&board)
        guard board != previous, saveMines(board) else { return false }
        if board.revealed != previous.revealed || board.flags != previous.flags { noteSessionMove(.minesweeper) }
        return true
    }
    @discardableResult func saveSliding(_ candidate: SlidingBoard) -> Bool {
        if pendingNewGame == .sliding {
            guard persistNewGamePayload(.sliding(candidate)) else { return false }
            sliding = candidate; return true
        }
        flushSessionClock(.sliding)
        var next = candidate
        if sessionIsPlaying(.sliding) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.sliding]?.elapsedSeconds ?? 0) }
        guard !blocked.contains(.sliding), let store else { return false }
        do { try store.save(next, namespace: "sliding"); sliding = next; syncSessionMoves(.sliding, next.moves); return true }
        catch { notice = .writeFailed; return false }
    }
    @discardableResult func editSliding(_ change: (inout SlidingBoard) -> Void) -> Bool {
        flushSessionClock(.sliding)
        guard var board = sliding else { return false }
        let previous = board; change(&board)
        return board != previous && saveSliding(board)
    }

    @discardableResult func saveTicTacToe(_ candidate: TicTacToeBoard) -> Bool {
        if pendingNewGame == .ticTacToe {
            guard persistNewGamePayload(.ticTacToe(candidate)) else { return false }
            ticTacToe = candidate; return true
        }
        flushSessionClock(.ticTacToe)
        var next = candidate
        if sessionIsPlaying(.ticTacToe) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.ticTacToe]?.elapsedSeconds ?? 0) }
        guard persist(next, game: .ticTacToe, validate: { $0.isValidSave }) else { return false }
        ticTacToe = next; syncSessionMoves(.ticTacToe, next.moves); return true
    }
    @discardableResult func editTicTacToe(_ change: (inout TicTacToeBoard) -> Void) -> Bool {
        flushSessionClock(.ticTacToe)
        guard var next = ticTacToe else { return false }; let previous = next; change(&next)
        return next != previous && saveTicTacToe(next)
    }
    @discardableResult func saveConnectFour(_ candidate: ConnectFourBoard) -> Bool {
        if pendingNewGame == .connectFour {
            guard persistNewGamePayload(.connectFour(candidate)) else { return false }
            connectFour = candidate; return true
        }
        flushSessionClock(.connectFour)
        var next = candidate
        if sessionIsPlaying(.connectFour) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.connectFour]?.elapsedSeconds ?? 0) }
        guard persist(next, game: .connectFour, validate: { $0.isValidSave }) else { return false }
        connectFour = next; syncSessionMoves(.connectFour, next.moves); return true
    }
    @discardableResult func editConnectFour(_ change: (inout ConnectFourBoard) -> Void) -> Bool {
        flushSessionClock(.connectFour)
        guard var next = connectFour else { return false }; let previous = next; change(&next)
        return next != previous && saveConnectFour(next)
    }
    @discardableResult func saveTwentyFour(_ candidate: TwentyFourBoard) -> Bool {
        if pendingNewGame == .twentyFour {
            guard persistNewGamePayload(.twentyFour(candidate)) else { return false }
            twentyFour = candidate; return true
        }
        flushSessionClock(.twentyFour)
        var next = candidate
        if sessionIsPlaying(.twentyFour) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.twentyFour]?.elapsedSeconds ?? 0) }
        guard persist(next, game: .twentyFour, validate: { $0.isValidSave }) else { return false }
        twentyFour = next; syncSessionMoves(.twentyFour, next.moves); return true
    }
    @discardableResult func editTwentyFour(_ change: (inout TwentyFourBoard) -> Void) -> Bool {
        flushSessionClock(.twentyFour)
        guard var next = twentyFour else { return false }; let previous = next; change(&next)
        return next != previous && saveTwentyFour(next)
    }
    @discardableResult func saveMemory(_ candidate: MemoryBoard) -> Bool {
        if pendingNewGame == .memory {
            guard persistNewGamePayload(.memory(candidate)) else { return false }
            memory = candidate; return true
        }
        flushSessionClock(.memory)
        var next = candidate
        if sessionIsPlaying(.memory) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.memory]?.elapsedSeconds ?? 0) }
        guard persist(next, game: .memory, validate: { $0.isValidSave }) else { return false }
        memory = next; syncSessionMoves(.memory, next.moves); return true
    }
    @discardableResult func editMemory(_ change: (inout MemoryBoard) -> Void) -> Bool {
        flushSessionClock(.memory)
        guard var next = memory else { return false }; let previous = next; change(&next)
        return next != previous && saveMemory(next)
    }
    @discardableResult func saveMaze(_ candidate: MazeBoard) -> Bool {
        if pendingNewGame == .maze {
            guard persistNewGamePayload(.maze(candidate)) else { return false }
            maze = candidate; return true
        }
        flushSessionClock(.maze)
        var next = candidate
        if sessionIsPlaying(.maze) { next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[.maze]?.elapsedSeconds ?? 0) }
        if sessionIsPlaying(.maze), let existing = maze, existing.seed == next.seed,
           existing.difficulty == next.difficulty {
            // The frame controller owns position, not a stale copy of the clock.
            next.elapsedSeconds = max(next.elapsedSeconds, existing.elapsedSeconds)
        }
        guard persist(next, game: .maze, validate: { $0.isValidSave }) else { return false }
        maze = next; syncSessionMoves(.maze, next.moves); return true
    }
    @discardableResult func editMaze(_ change: (inout MazeBoard) -> Void) -> Bool {
        flushSessionClock(.maze)
        guard var next = maze else { return false }; let previous = next; change(&next)
        return next != previous && saveMaze(next)
    }
}

struct GameDataImportPreview {
    let createdAt: Date
    let games: [GameID]
    let recordCount: Int
    let includesPreferences: Bool
}

extension AppModel {
    var playRecords: [GamePlayRecord] { sessionData.records }
    func gameStatistics(for game: GameID) -> GameStatistics { sessionData.statistics[game] ?? GameStatistics() }
    func gameSettings(for game: GameID) -> GamePlayPreferences { sessionData.gamePreferences[game] ?? GamePlayPreferences() }
    func updateGameSettings(for game: GameID, _ change: (inout GamePlayPreferences) -> Void) {
        var settings = gameSettings(for: game); change(&settings)
        guard settings.isValid else { return }
        var next = sessionData; next.gamePreferences[game] = settings
        _ = commitSessionData(next)
    }
    func feedback(for game: GameID) { if gameSettings(for: game).haptics { feedback() } }

    func gameSnapshot(for game: GameID) -> GameRunSnapshot {
        var exists = false, ended = false, outcome: GameOutcome?
        var elapsed = 0, moves = 0, difficulty = "", mode = ""
        switch game {
        case .sudoku:
            if let id = sudoku.currentID, let board = sudoku.boards[id], let puzzle = puzzles.first(where: { $0.id == id }) {
                exists = true; ended = board.isComplete(puzzle: puzzle); outcome = ended ? .completed : nil
                difficulty = puzzle.difficulty.rawValue; mode = id
                if let state = sessionData.sessions[game] ?? sessionData.sudokuSessions[id], state.mode == id { elapsed = state.elapsedSeconds; moves = state.moves }
            }
        case .minesweeper:
            if let board = mines {
                exists = true; ended = board.isFinished; elapsed = board.elapsedSeconds
                difficulty = String(board.configuration.difficultyKey.dropFirst("difficulty.".count))
                mode = "\(board.configuration.width)×\(board.configuration.height) · \(board.configuration.mineCount)"
                outcome = board.status == .won ? .won : board.status == .lost ? .lost : nil
                moves = sessionData.sessions[game]?.moves ?? 0
            }
        case .sliding:
            if let board = sliding {
                exists = true; ended = board.isComplete; outcome = ended ? .completed : nil
                elapsed = board.elapsedSeconds; moves = board.moves; difficulty = board.difficulty.rawValue; mode = "\(board.size)×\(board.size)"
            }
        case .ticTacToe:
            if let board = ticTacToe {
                exists = true; ended = board.isFinished; elapsed = board.elapsedSeconds; moves = board.moves
                difficulty = board.difficulty.rawValue; mode = board.mode.rawValue
                outcome = board.winner.map { $0 == (board.mode == .singlePlayer ? board.humanPlayer : .first) ? .won : .lost } ?? (board.isDraw ? .draw : nil)
            }
        case .connectFour:
            if let board = connectFour {
                exists = true; ended = board.isFinished; elapsed = board.elapsedSeconds; moves = board.moves
                difficulty = board.difficulty.rawValue; mode = board.mode.rawValue
                outcome = board.winner.map { $0 == (board.mode == .singlePlayer ? board.humanPlayer : .first) ? .won : .lost } ?? (board.isDraw ? .draw : nil)
            }
        case .twentyFour:
            if let board = twentyFour {
                exists = true; ended = board.isEnded; outcome = ended ? (board.isComplete ? .completed : .lost) : nil
                elapsed = board.elapsedSeconds; moves = board.moves; difficulty = board.difficulty.rawValue
            }
        case .memory:
            if let board = memory {
                exists = true; ended = board.isComplete; outcome = ended ? .completed : nil
                elapsed = board.elapsedSeconds; moves = board.moves; difficulty = board.mode.rawValue
            }
        case .maze:
            if let board = maze {
                exists = true; ended = board.isComplete; outcome = ended ? .completed : nil
                elapsed = board.elapsedSeconds; moves = board.moves; difficulty = board.difficulty.rawValue; mode = "\(board.size)×\(board.size)"
            }
        default:
            if let board = expandedGames[game] { return board.snapshot }
        }
        return GameRunSnapshot(game: game, exists: exists, ended: ended, outcome: outcome, elapsedSeconds: elapsed,
                               moves: moves, difficulty: difficulty, mode: mode)
    }
    func sessionPhase(for game: GameID) -> GameSessionPhase { sessionData.sessions[game]?.phase ?? .paused }
    func sessionIsPlaying(_ game: GameID) -> Bool {
        sessionStorageAvailable && !blocked.contains(game) && sceneActive && visibleSession == game && sessionPhase(for: game) == .playing
    }

    @discardableResult private func commitSessionData(_ next: GameSessionData) -> Bool {
        guard sessionStorageAvailable, let transferStore else { return false }
        do { try transferStore.saveSessionData(next); sessionData = next; return true }
        catch { notice = .writeFailed; return false }
    }
    private func noteSessionMove(_ game: GameID) {
        guard sessionIsPlaying(game), let id = sessionData.sessions[game]?.id else { return }
        var next = sessionData
        if next.sessions[game]?.recordMove(expectedSessionID: id) == true { _ = commitSessionData(next) }
    }
    private func syncSessionMoves(_ game: GameID, _ moves: Int) {
        guard sessionIsPlaying(game), let state = sessionData.sessions[game], state.moves != moves else { return }
        var next = sessionData
        if next.sessions[game]?.syncMoves(moves, expectedSessionID: state.id) == true { _ = commitSessionData(next) }
    }
    /// Adopt a released save without inventing a historical start date or old matches.
    func preparePreviousSession(_ game: GameID) {
        let snapshot = gameSnapshot(for: game)
        guard snapshot.exists else { return }
        if let state = sessionData.sessions[game], game != .sudoku || state.mode == snapshot.mode { return }
        var next = sessionData
        if game == .sudoku {
            _ = next.parkSudokuSession()
            if next.restoreSudokuSession(puzzleID: snapshot.mode) { _ = commitSessionData(next); return }
        }
        let state = GameSessionState(gameID: game, difficulty: snapshot.difficulty, mode: snapshot.mode,
                                     phase: .paused, elapsedSeconds: snapshot.elapsedSeconds, moves: snapshot.moves)
        if snapshot.ended, let outcome = snapshot.outcome {
            guard next.adoptUntrackedFinishedSession(state, outcome: outcome,
                elapsedSeconds: snapshot.elapsedSeconds, moves: snapshot.moves) else { return }
        } else { next.sessions[game] = state }
        _ = commitSessionData(next)
    }
    func performNewGameRequest(_ game: GameID, action: () -> Void) {
        guard pendingNewGame == nil, !blocked.contains(game), sessionStorageAvailable else { return }
        pendingNewGame = game
        defer { pendingNewGame = nil; preparedNewGame = nil }
        action()
    }
    /// All released board bytes and the new session are committed together.
    private func persistNewGamePayload(_ payload: GameSavePayload) -> Bool {
        let game = payload.gameID
        guard pendingNewGame == game, let transferStore, let snapshot = payload.snapshot(catalog: puzzles),
              snapshot.exists else { return false }
        var next = sessionData
        if game == .sudoku, next.sessions[game]?.mode != snapshot.mode {
            _ = next.parkSudokuSession()
            _ = next.restoreSudokuSession(puzzleID: snapshot.mode)
        }
        if var previous = next.sessions[game], previous.recordID == nil,
           let record = previous.finish(result: .abandoned, elapsedSeconds: previous.elapsedSeconds, moves: previous.moves) {
            do { try next.append(record) } catch { notice = .writeFailed; return false }
        }
        next.sessions[game] = GameSessionState(gameID: game, difficulty: snapshot.difficulty, mode: snapshot.mode)
        do {
            let result = try transferStore.replaceGame(game, payload: payload, metadata: next)
            sessionData = result.metadata; clockAnchor = nil; preparedNewGame = game; return true
        } catch { notice = .writeFailed; return false }
    }
    func startNewSession(_ game: GameID) {
        // Save succeeded inside the confirmed, synchronous request above.
        guard preparedNewGame == game else { notice = .writeFailed; return }
        preparedNewGame = nil
    }
    func beginContinuing(_ game: GameID) {
        preparePreviousSession(game)
        pauseSession(game)
        // A completed round opens its immutable result, including after Done.
        if gameSnapshot(for: game).ended { finishSessionIfNeeded(game, resultReady: true) }
    }
    func enterSession(_ game: GameID, resultReady: Bool) {
        preparePreviousSession(game)
        visibleSession = game
        if sessionPhase(for: game) == .playing {
            if game == .maze, var board = maze, board.isPaused { board.resume(); _ = saveMaze(board) }
            resetClock(game)
        }
        finishSessionIfNeeded(game, resultReady: resultReady)
        setGameActivity(game, active: sessionIsPlaying(game) && !gameSnapshot(for: game).ended)
    }
    func leaveSession(_ game: GameID) {
        pauseSession(game)
        if visibleSession == game { visibleSession = nil; clockAnchor = nil }
        endGameActivity(game)
    }
    func pauseSession(_ game: GameID) {
        flushSessionClock(game)
        var next = sessionData
        if next.sessions[game]?.pause() == true { _ = commitSessionData(next) }
        if game == .maze, var board = maze, !board.isPaused, !board.isComplete { board.pause(); _ = saveMaze(board) }
        if clockAnchor?.game == game { clockAnchor = nil }
        setGameActivity(game, active: false)
    }
    @discardableResult func resumeSession(_ game: GameID) -> Bool {
        guard sceneActive, visibleSession == game, !gameSnapshot(for: game).ended else { return false }
        var next = sessionData
        guard next.sessions[game]?.resume() == true, commitSessionData(next) else { return false }
        if game == .maze, var board = maze {
            board.resume()
            guard saveMaze(board) else { pauseSession(game); return false }
        }
        resetClock(game); setGameActivity(game, active: true); return true
    }
    private func resetClock(_ game: GameID) {
        guard let id = sessionData.sessions[game]?.id else { return }
        clockAnchor = (game, id, ProcessInfo.processInfo.systemUptime)
    }
    /// The callback cadence affects redraws only. Elapsed time comes from a monotonic clock.
    func tickSession(_ game: GameID, resultReady: Bool) {
        flushSessionClock(game)
        finishSessionIfNeeded(game, resultReady: resultReady)
    }
    private func flushSessionClock(_ game: GameID) {
        guard !synchronizingClock, sessionIsPlaying(game), let anchor = clockAnchor, anchor.game == game,
              anchor.session == sessionData.sessions[game]?.id else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Completed boards have already frozen their clock in the mutation path.
        if gameSnapshot(for: game).ended { clockAnchor = nil; return }
        var next = sessionData
        let seconds = next.sessions[game]?.advance(by: max(0, now - anchor.uptime), expectedSessionID: anchor.session) ?? 0
        if seconds > 0 {
            guard commitSessionData(next) else { return } // Keep the old anchor for a successful retry.
            clockAnchor = (game, anchor.session, now)
            synchronizeElapsed(game, seconds: next.sessions[game]?.elapsedSeconds ?? 0)
        } else { sessionData = next; clockAnchor = (game, anchor.session, now) }
    }
    private func synchronizeElapsed(_ game: GameID, seconds: Int) {
        guard !synchronizingClock else { return }
        synchronizingClock = true
        defer { synchronizingClock = false }
        switch game {
        case .sudoku: break // sidecar keeps the released SudokuBoard schema untouched.
        case .minesweeper: if var board = mines { board.elapsedSeconds = seconds; _ = saveMines(board) }
        case .sliding: if var board = sliding { board.elapsedSeconds = seconds; _ = saveSliding(board) }
        case .ticTacToe: if var board = ticTacToe { board.elapsedSeconds = seconds; _ = saveTicTacToe(board) }
        case .connectFour: if var board = connectFour { board.elapsedSeconds = seconds; _ = saveConnectFour(board) }
        case .twentyFour: if var board = twentyFour { board.elapsedSeconds = seconds; _ = saveTwentyFour(board) }
        case .memory: if var board = memory { board.elapsedSeconds = seconds; _ = saveMemory(board) }
        case .maze: if var board = maze { board.elapsedSeconds = seconds; _ = saveMaze(board) }
        default: if var board = expandedGames[game] { board.elapsedSeconds = seconds; _ = saveExpanded(board) }
        }
    }
    func finishSessionIfNeeded(_ game: GameID, resultReady: Bool) {
        let snapshot = gameSnapshot(for: game)
        guard resultReady, snapshot.exists, snapshot.ended, let outcome = snapshot.outcome,
              var state = sessionData.sessions[game] else { return }
        clockAnchor = nil
        var next = sessionData
        if state.recordID == nil {
            guard let record = state.finish(result: outcome, elapsedSeconds: snapshot.elapsedSeconds, moves: snapshot.moves) else { return }
            do { try next.append(record) } catch { notice = .writeFailed; return }
            next.sessions[game] = state
        } else if state.phase == .menu {
            guard state.reopenResult() else { return }
            next.sessions[game] = state
        } else { return }
        _ = commitSessionData(next); endGameActivity(game)
    }
    func reviewSession(_ game: GameID) { var next = sessionData; if next.sessions[game]?.review() == true { _ = commitSessionData(next) } }
    func showSessionResult(_ game: GameID) { var next = sessionData; if next.sessions[game]?.showResult() == true { _ = commitSessionData(next) } }
    @discardableResult func closeSession(_ game: GameID) -> Bool {
        var next = sessionData
        guard next.sessions[game]?.close() == true, commitSessionData(next) else { return false }
        protectNavigationTransition(); return true
    }
    func protectNavigationTransition() {
        let token = UUID(); navigationTouchToken = token; navigationTouchLocked = true
        Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
            guard let self, self.navigationTouchToken == token else { return }
            self.navigationTouchLocked = false
        }
    }
    @discardableResult func clearGameStatistics(_ game: GameID) -> Bool {
        var next = sessionData; next.clearRecords(for: game); return commitSessionData(next)
    }
    @discardableResult func deleteCurrentGame(_ game: GameID, expectedSessionID: UUID? = nil) -> Bool {
        guard !blocked.contains(game), let transferStore,
              expectedSessionID == nil || sessionData.sessions[game]?.id == expectedSessionID else { return false }
        pauseSession(game); preparePreviousSession(game)
        var next = sessionData
        if var state = next.sessions[game], state.recordID == nil,
           let record = state.finish(result: .abandoned, elapsedSeconds: state.elapsedSeconds, moves: state.moves) {
            do { try next.append(record) } catch { notice = .writeFailed; return false }
        }
        next.sessions[game] = nil
        let payload: GameSavePayload?
        if game == .sudoku {
            var progress = sudoku
            if let id = progress.currentID { progress.boards[id] = nil }
            progress.currentID = nil
            payload = .sudoku(progress)
        } else { payload = nil }
        do {
            let result = try transferStore.replaceGame(game, payload: payload, metadata: next)
            sessionData = result.metadata; reloadGameData([game]); return true
        } catch { notice = .writeFailed; return false }
    }
    func exportGameData(game: GameID? = nil) throws -> Data {
        if let visibleSession { pauseSession(visibleSession) }
        guard let transferStore, sessionStorageAvailable else { throw GameDataTransferStore.TransferError.unavailable }
        return try transferStore.exportArchive(scope: game.map(GameDataScope.game) ?? .all, preferences: preferences)
    }
    func previewGameDataImport(_ data: Data) throws -> GameDataImportPreview {
        guard let transferStore else { throw GameDataTransferStore.TransferError.unavailable }
        let archive = try transferStore.validateArchive(data)
        return GameDataImportPreview(createdAt: archive.createdAt, games: archive.games.map(\.gameID),
                                     recordCount: archive.metadata.records.count, includesPreferences: archive.preferences != nil)
    }
    func importGameData(_ data: Data) throws {
        if let visibleSession { pauseSession(visibleSession) }
        guard let transferStore else { throw GameDataTransferStore.TransferError.unavailable }
        let archive = try transferStore.validateArchive(data)
        var metadata = archive.metadata
        for game in archive.scope.gameIDs {
            if let token = metadata.sessions[game]?.pendingToken { _ = metadata.sessions[game]?.cancelConfirmation(token) }
            _ = metadata.sessions[game]?.pause()
        }
        let normalized = GameDataArchive(scope: archive.scope, preferences: archive.preferences, games: archive.games,
                                         metadata: metadata, createdAt: archive.createdAt)
        // Pause normalization is part of the same rollback-protected import.
        // Nothing that can fail writes a second time after the transaction commits.
        let result = try transferStore.applyArchive(JSONEncoder().encode(normalized))
        clockAnchor = nil; sessionData = result.metadata
        if let imported = result.preferences { preferenceStore.save(imported); preferences = imported }
        sessionStorageAvailable = true
        reloadGameData(result.scope.gameIDs); updateIdleTimer()
    }
    private func reloadGameData(_ games: [GameID]) {
        for game in games {
            blocked.remove(game); newerSaves.remove(game)
            switch game {
            case .sudoku: sudoku = restore(SudokuProgress.self, game: game) { progress in
                progress.boards.allSatisfy { id, board in puzzles.first(where: { $0.id == id }).map { board.isValidSave(for: $0) } == true }
            } ?? SudokuProgress()
            case .minesweeper: mines = restore(MinesweeperBoard.self, game: game) { $0.isValidSave }
            case .sliding: sliding = restore(SlidingBoard.self, game: game) { $0.isValidSave }
            case .ticTacToe: ticTacToe = restore(TicTacToeBoard.self, game: game) { $0.isValidSave }
            case .connectFour: connectFour = restore(ConnectFourBoard.self, game: game) { $0.isValidSave }
            case .twentyFour: twentyFour = restore(TwentyFourBoard.self, game: game) { $0.isValidSave }
            case .memory: memory = restore(MemoryBoard.self, game: game) { $0.isValidSave }
            case .maze: maze = restore(MazeBoard.self, game: game) { $0.isValidSave }
            default: expandedGames[game] = restore(ExpandedGameSave.self, game:game) { $0.gameID == game && $0.isValidSave }
            }
        }
    }

    @discardableResult func saveExpanded(_ candidate: ExpandedGameSave, resultReady: Bool = true) -> Bool {
        let game = candidate.gameID
        guard game.isExpanded, candidate.isValidSave else { return false }
        if pendingNewGame == game {
            guard persistNewGamePayload(.expanded(candidate)) else { return false }
            expandedGames[game] = candidate; return true
        }
        flushSessionClock(game)
        var next = candidate
        next.elapsedSeconds = max(next.elapsedSeconds, sessionData.sessions[game]?.elapsedSeconds ?? 0)
        guard persist(next, game:game, validate:{$0.gameID == game && $0.isValidSave}) else { return false }
        expandedGames[game] = next; syncSessionMoves(game,next.state.moves)
        finishSessionIfNeeded(game, resultReady: resultReady); return true
    }

    @discardableResult func editExpanded(_ game: GameID, resultReady: Bool = true, _ change: (inout ExpandedGameState) -> Bool) -> Bool {
        guard sessionIsPlaying(game), var board = expandedGames[game], board.outcome == nil else { return false }
        let before = board.state
        guard change(&board.state), board.state != before, saveExpanded(board, resultReady: resultReady) else { return false }
        feedback(for:game); return true
    }
}
