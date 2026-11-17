import Foundation

public enum GameDataScope: Codable, Equatable, Sendable {
    case all
    case game(GameID)
    public var gameIDs: [GameID] {
        switch self { case .all: return GameID.allCases; case .game(let game): return [game] }
    }
}

/// The enum preserves each released, typed schema-1 payload. No archive can
/// introduce another namespace or inject an arbitrary filename into storage.
public enum GameSavePayload: Codable, Equatable, Sendable {
    case sudoku(SudokuProgress)
    case minesweeper(MinesweeperBoard)
    case sliding(SlidingBoard)
    case ticTacToe(TicTacToeBoard)
    case connectFour(ConnectFourBoard)
    case twentyFour(TwentyFourBoard)
    case memory(MemoryBoard)
    case maze(MazeBoard)

    public var gameID: GameID {
        switch self {
        case .sudoku: return .sudoku
        case .minesweeper: return .minesweeper
        case .sliding: return .sliding
        case .ticTacToe: return .ticTacToe
        case .connectFour: return .connectFour
        case .twentyFour: return .twentyFour
        case .memory: return .memory
        case .maze: return .maze
        }
    }

    public func isValid(catalog: [SudokuPuzzle]) -> Bool {
        switch self {
        case .sudoku(let progress):
            let known = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
            guard progress.boards.count <= known.count, progress.completed.isSubset(of: Set(known.keys)),
                  progress.currentID == nil || known[progress.currentID!] != nil else { return false }
            return progress.boards.allSatisfy { id, board in known[id].map { board.isValidSave(for: $0) } == true }
        case .minesweeper(let board): return board.isValidSave && board.elapsedSeconds <= 315_360_000
        case .sliding(let board): return board.isValidSave && board.elapsedSeconds <= 315_360_000 && board.moves <= 1_000_000_000
        case .ticTacToe(let board): return board.isValidSave
        case .connectFour(let board): return board.isValidSave
        case .twentyFour(let board): return board.isValidSave
        case .memory(let board): return board.isValidSave
        case .maze(let board): return board.isValidSave && board.elapsedSeconds <= 315_360_000
        }
    }

    func isCoherent(with session: GameSessionState, catalog: [SudokuPuzzle]) -> Bool {
        guard let snapshot = snapshot(catalog: catalog), snapshot.exists, session.gameID == gameID else { return false }
        if gameID == .sudoku && session.mode != snapshot.mode { return false }
        if !session.difficulty.isEmpty && session.difficulty != snapshot.difficulty { return false }
        if !session.mode.isEmpty && !snapshot.mode.isEmpty && session.mode != snapshot.mode { return false }
        guard session.recordID != nil else { return true }
        if session.outcome == .abandoned { return true }
        guard snapshot.ended, snapshot.outcome == session.outcome else { return false }
        // Legacy game files and the sidecar are separately saved during active
        // play; a crash may leave their clocks apart. Immutable finished metrics
        // must agree, while Sudoku/Mines moves are intentionally sidecar-only.
        if gameID != .sudoku && snapshot.elapsedSeconds != session.elapsedSeconds { return false }
        if gameID != .sudoku && gameID != .minesweeper && snapshot.moves != session.moves { return false }
        return true
    }

    func isCoherent(withParkedSudoku states: [String: GameSessionState], catalog: [SudokuPuzzle]) -> Bool {
        guard !states.isEmpty else { return true }
        guard case .sudoku(let progress) = self else { return false }
        return states.allSatisfy { id, state in
            guard progress.boards[id] != nil else { return false }
            var selected = progress; selected.currentID = id
            return GameSavePayload.sudoku(selected).isCoherent(with: state, catalog: catalog)
        }
    }

    public func snapshot(catalog: [SudokuPuzzle]) -> GameRunSnapshot? {
        switch self {
        case .sudoku(let progress):
            guard let id = progress.currentID, let board = progress.boards[id], let puzzle = catalog.first(where: { $0.id == id }) else { return nil }
            let ended = board.isComplete(puzzle: puzzle)
            return GameRunSnapshot(game: .sudoku, exists: true, ended: ended, outcome: ended ? .completed : nil,
                                   elapsedSeconds: 0, moves: 0, difficulty: puzzle.difficulty.rawValue, mode: id)
        case .minesweeper(let board):
            return GameRunSnapshot(game: .minesweeper, exists: true, ended: board.isFinished,
                                   outcome: board.status == .won ? .won : board.status == .lost ? .lost : nil,
                                   elapsedSeconds: board.elapsedSeconds, moves: 0,
                                   difficulty: String(board.configuration.difficultyKey.dropFirst("difficulty.".count)),
                                   mode: "\(board.configuration.width)×\(board.configuration.height) · \(board.configuration.mineCount)")
        case .sliding(let board):
            return GameRunSnapshot(game: .sliding, exists: true, ended: board.isComplete, outcome: board.isComplete ? .completed : nil,
                                   elapsedSeconds: board.elapsedSeconds, moves: board.moves, difficulty: board.difficulty.rawValue, mode: "\(board.size)×\(board.size)")
        case .ticTacToe(let board):
            let outcome: GameOutcome? = board.winner.map { $0 == (board.mode == .singlePlayer ? board.humanPlayer : .first) ? .won : .lost } ?? (board.isDraw ? .draw : nil)
            return GameRunSnapshot(game: .ticTacToe, exists: true, ended: board.isFinished, outcome: outcome,
                                   elapsedSeconds: board.elapsedSeconds, moves: board.moves, difficulty: board.difficulty.rawValue, mode: board.mode.rawValue)
        case .connectFour(let board):
            let outcome: GameOutcome? = board.winner.map { $0 == (board.mode == .singlePlayer ? board.humanPlayer : .first) ? .won : .lost } ?? (board.isDraw ? .draw : nil)
            return GameRunSnapshot(game: .connectFour, exists: true, ended: board.isFinished, outcome: outcome,
                                   elapsedSeconds: board.elapsedSeconds, moves: board.moves, difficulty: board.difficulty.rawValue, mode: board.mode.rawValue)
        case .twentyFour(let board):
            return GameRunSnapshot(game: .twentyFour, exists: true, ended: board.isEnded,
                                   outcome: board.isEnded ? (board.isComplete ? .completed : .lost) : nil,
                                   elapsedSeconds: board.elapsedSeconds, moves: board.moves, difficulty: board.difficulty.rawValue, mode: "")
        case .memory(let board):
            return GameRunSnapshot(game: .memory, exists: true, ended: board.isComplete, outcome: board.isComplete ? .completed : nil,
                                   elapsedSeconds: board.elapsedSeconds, moves: board.moves, difficulty: board.mode.rawValue, mode: "")
        case .maze(let board):
            return GameRunSnapshot(game: .maze, exists: true, ended: board.isComplete, outcome: board.isComplete ? .completed : nil,
                                   elapsedSeconds: board.elapsedSeconds, moves: board.moves, difficulty: board.difficulty.rawValue, mode: "\(board.size)×\(board.size)")
        }
    }

    func envelopeData() throws -> Data {
        switch self {
        case .sudoku(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .minesweeper(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .sliding(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .ticTacToe(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .connectFour(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .twentyFour(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .memory(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        case .maze(let value): return try JSONEncoder().encode(GameDataEnvelope(payload: value))
        }
    }

    static func decodeEnvelope(_ data: Data, game: GameID) throws -> Self {
        let decoder = JSONDecoder()
        switch game {
        case .sudoku: return .sudoku(try decoder.decode(GameDataEnvelope<SudokuProgress>.self, from: data).payload)
        case .minesweeper: return .minesweeper(try decoder.decode(GameDataEnvelope<MinesweeperBoard>.self, from: data).payload)
        case .sliding: return .sliding(try decoder.decode(GameDataEnvelope<SlidingBoard>.self, from: data).payload)
        case .ticTacToe: return .ticTacToe(try decoder.decode(GameDataEnvelope<TicTacToeBoard>.self, from: data).payload)
        case .connectFour: return .connectFour(try decoder.decode(GameDataEnvelope<ConnectFourBoard>.self, from: data).payload)
        case .twentyFour: return .twentyFour(try decoder.decode(GameDataEnvelope<TwentyFourBoard>.self, from: data).payload)
        case .memory: return .memory(try decoder.decode(GameDataEnvelope<MemoryBoard>.self, from: data).payload)
        case .maze: return .maze(try decoder.decode(GameDataEnvelope<MazeBoard>.self, from: data).payload)
        }
    }
}

public struct GameArchiveEntry: Codable, Equatable, Sendable {
    public let gameID: GameID
    /// nil explicitly means no progress, including removal of an old backup.
    public let payload: GameSavePayload?
    public init(gameID: GameID, payload: GameSavePayload?) { self.gameID = gameID; self.payload = payload }
}

public struct GameDataArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let format: String
    public let version: Int
    public let createdAt: Date
    public let scope: GameDataScope
    public let preferences: AppPreferences?
    public let games: [GameArchiveEntry]
    public let metadata: GameSessionData

    public init(scope: GameDataScope, preferences: AppPreferences?, games: [GameArchiveEntry],
                metadata: GameSessionData, createdAt: Date = Date()) {
        format = "ChaiClassics.GameDataArchive"; version = Self.currentVersion
        self.scope = scope; self.preferences = preferences; self.games = games
        self.metadata = metadata; self.createdAt = createdAt
    }

    public func isValid(catalog: [SudokuPuzzle]) -> Bool {
        let allowed = Set(scope.gameIDs)
        guard format == "ChaiClassics.GameDataArchive", version == Self.currentVersion,
              createdAt.timeIntervalSince1970.isFinite, (0...253_402_300_799).contains(createdAt.timeIntervalSince1970),
              games.count == allowed.count, Set(games.map(\.gameID)) == allowed,
              metadata.isValid,
              metadata.records.allSatisfy({ allowed.contains($0.gameID) }),
              Set(metadata.sessions.keys).isSubset(of: allowed), Set(metadata.gamePreferences.keys).isSubset(of: allowed),
              Set(metadata.legacyDuelStatistics.keys).isSubset(of: allowed),
              metadata.sudokuSessions.isEmpty || allowed.contains(.sudoku),
              games.allSatisfy({ entry in
                  if metadata.sessions[entry.gameID] != nil && entry.payload == nil { return false }
                  if entry.gameID == .sudoku && !metadata.sudokuSessions.isEmpty && entry.payload == nil { return false }
                  guard let payload = entry.payload else { return true }
                  guard payload.gameID == entry.gameID, payload.isValid(catalog: catalog) else { return false }
                  if entry.gameID == .sudoku && !payload.isCoherent(withParkedSudoku: metadata.sudokuSessions, catalog: catalog) { return false }
                  return metadata.sessions[entry.gameID].map { payload.isCoherent(with: $0, catalog: catalog) } ?? true
              }) else { return false }
        switch scope { case .all: return preferences != nil; case .game: return preferences == nil }
    }
}

public struct GameDataImportResult: Sendable {
    public let scope: GameDataScope
    public let preferences: AppPreferences?
    public let metadata: GameSessionData
}

struct GameDataEnvelope<T: Codable>: Codable {
    var schemaVersion = 1
    let payload: T
}
