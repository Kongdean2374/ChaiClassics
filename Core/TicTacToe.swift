import Foundation

/// A standard alternating X/O round. Every saved position is checked by replaying its legal moves.
public struct TicTacToeBoard: Codable, Equatable, Sendable {
    private struct CompletedRound: Codable, Equatable, Sendable {
        let history: [Int]
        let perspective: DuelPlayer
    }
    public let mode: DuelMode
    public let difficulty: DuelDifficulty
    public let humanPlayer: DuelPlayer
    public let seed: UInt64
    public private(set) var sessionID: UUID
    public private(set) var cells: [DuelPlayer?]
    public private(set) var history: [Int]
    public var elapsedSeconds = 0
    private var completedRounds: [CompletedRound] = []
    private var includeCurrentResult = true

    public init(mode: DuelMode = .singlePlayer, difficulty: DuelDifficulty = .normal,
                humanPlayer: DuelPlayer = .first, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.mode = mode; self.difficulty = difficulty; self.humanPlayer = humanPlayer; self.seed = seed
        sessionID = UUID(); cells = Array(repeating: nil, count: 9); history = []
    }
    public var moves: Int { history.count }
    public var currentPlayer: DuelPlayer { moves.isMultiple(of: 2) ? .first : .second }
    public var winningLine: [Int] { Self.line(in: cells) }
    public var winner: DuelPlayer? { winningLine.first.flatMap { cells[$0] } }
    public var isDraw: Bool { cells.count == 9 && moves == 9 && winner == nil }
    public var isFinished: Bool { winner != nil || isDraw }
    public var isComputerTurn: Bool { mode == .singlePlayer && currentPlayer != humanPlayer && !isFinished }
    private var perspective: DuelPlayer { mode == .singlePlayer ? humanPlayer : .first }

    public var statistics: DuelStatistics {
        var value = DuelStatistics()
        for round in completedRounds {
            if let replay = Self.replay(round.history), replay.finished {
                value.record(winner: replay.winner, humanPlayer: round.perspective)
            }
        }
        if includeCurrentResult && isFinished { value.record(winner: winner, humanPlayer: perspective) }
        return value
    }
    public func canPlay(at index: Int, by player: DuelPlayer) -> Bool {
        cells.count == 9 && history.count < 9 && cells.indices.contains(index) && cells[index] == nil &&
        player == currentPlayer && !isFinished
    }
    /// Human input always belongs to the configured human side in solo play.
    /// This also guards queued taps before the view redraws for the AI turn.
    public func canHumanPlay(at index: Int, active: Bool) -> Bool {
        active && canPlay(at: index, by: mode == .singlePlayer ? humanPlayer : currentPlayer)
    }
    @discardableResult public mutating func play(at index: Int, by player: DuelPlayer) -> Bool {
        guard canPlay(at: index, by: player) else { return false }
        cells[index] = player; history.append(index); return true
    }
    /// Restart keeps completed results once, and abandons an unfinished round without recording a loss.
    public mutating func restart() {
        archiveCurrentRound()
        sessionID = UUID(); cells = Array(repeating: nil, count: 9); history = []; elapsedSeconds = 0; includeCurrentResult = true
    }
    public func newGame(mode: DuelMode, difficulty: DuelDifficulty, humanPlayer: DuelPlayer,
                        seed: UInt64 = UInt64.random(in: .min ... .max)) -> TicTacToeBoard {
        var old = self; old.archiveCurrentRound()
        var next = TicTacToeBoard(mode: mode, difficulty: difficulty, humanPlayer: humanPlayer, seed: seed)
        next.completedRounds = old.completedRounds
        return next
    }
    public mutating func clearStatistics() {
        completedRounds = []; includeCurrentResult = !isFinished
    }
    private mutating func archiveCurrentRound() {
        if includeCurrentResult && isFinished {
            completedRounds.append(CompletedRound(history: history, perspective: perspective))
        }
    }
    public var isValidSave: Bool {
        guard (0...31_536_000).contains(elapsedSeconds), let replay = Self.replay(history), replay.cells == cells,
              includeCurrentResult || replay.finished else { return false }
        return completedRounds.allSatisfy { Self.replay($0.history)?.finished == true }
    }

    /// Returns an AI move only when it is the computer's turn. Seed injection makes each difficulty reproducible.
    public func computerMove(seed override: UInt64? = nil) -> Int? {
        guard isComputerTurn else { return nil }
        return recommendedMove(seed: override)
    }
    public func recommendedMove(difficulty override: DuelDifficulty? = nil, seed overrideSeed: UInt64? = nil) -> Int? {
        guard isValidSave, !isFinished else { return nil }
        let level = override ?? difficulty
        var rng = SeededRandom(seed: overrideSeed ?? (seed &+ UInt64(moves) &* 0x9e3779b97f4a7c15))
        let available = cells.indices.filter { cells[$0] == nil }.shuffled(using: &rng)
        guard level != .easy else { return available.first }
        for player in [currentPlayer, currentPlayer.opponent] {
            if let winning = available.first(where: { index in
                var next = cells; next[index] = player; return !Self.line(in: next).isEmpty
            }) { return winning }
        }
        if level == .normal {
            if cells[4] == nil { return 4 }
            return available.first
        }
        // Reaching the same board through a different move order has exactly
        // the same minimax value. Keep a per-search transposition table rather
        // than repeatedly visiting all permutations of the remaining moves.
        // It is local: no save fields, shared mutable cache or changed tie-break.
        var memo: [Int:Int] = [:]
        var best = Int.min, chosen: Int?
        for index in available {
            var next = cells; next[index] = currentPlayer
            let score = Self.minimax(next, player: currentPlayer.opponent, actor: currentPlayer, depth: 1, memo: &memo)
            if score > best { best = score; chosen = index }
        }
        return chosen
    }
    private static func minimax(_ grid: [DuelPlayer?], player: DuelPlayer, actor: DuelPlayer, depth: Int, memo: inout [Int:Int]) -> Int {
        // Actor and root depth are fixed for this table. For a given board,
        // the number of occupied squares uniquely determines search depth.
        let key = grid.reduce(0) { $0*3+($1?.rawValue ?? 0) }*3+player.rawValue
        if let cached = memo[key] { return cached }
        let winning = line(in: grid)
        if let first = winning.first { return grid[first] == actor ? 10 - depth : depth - 10 }
        let empty = grid.indices.filter { grid[$0] == nil }
        if empty.isEmpty { return 0 }
        let maximizing = player == actor
        var best = maximizing ? Int.min : Int.max
        for index in empty {
            var next = grid; next[index] = player
            let score = minimax(next, player: player.opponent, actor: actor, depth: depth + 1, memo: &memo)
            best = maximizing ? max(best, score) : min(best, score)
        }
        memo[key] = best
        return best
    }
    private static let lines = [[0,1,2], [3,4,5], [6,7,8], [0,3,6], [1,4,7], [2,5,8], [0,4,8], [2,4,6]]
    private static func line(in grid: [DuelPlayer?]) -> [Int] {
        guard grid.count == 9 else { return [] }
        return lines.first { line in grid[line[0]] != nil && grid[line[0]] == grid[line[1]] && grid[line[1]] == grid[line[2]] } ?? []
    }
    private static func replay(_ history: [Int]) -> (cells: [DuelPlayer?], winner: DuelPlayer?, finished: Bool)? {
        guard history.count <= 9 else { return nil }
        var grid: [DuelPlayer?] = Array(repeating: nil, count: 9)
        var result: DuelPlayer?
        for (move, index) in history.enumerated() {
            guard grid.indices.contains(index), grid[index] == nil, result == nil else { return nil }
            let player: DuelPlayer = move.isMultiple(of: 2) ? .first : .second
            grid[index] = player
            if let first = line(in: grid).first { result = grid[first] }
        }
        return (grid, result, result != nil || history.count == 9)
    }
}
